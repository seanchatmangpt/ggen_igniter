defmodule GgenIgniter.Test.PackCompile do
  @moduledoc """
  Chicago-style harness: render a pack with a REAL `mix ggen_igniter.sync`
  subprocess into a real tmp dir, then compile the output with the real
  compiler (`Kernel.ParallelCompiler.compile_to_path/3`) against the real deps.
  No doubles; callers assert on returned state (files, modules, diagnostics).

  ## API

    * `render!/2`, `render/2` - real sync subprocess (`--engine sparql`).
    * `compile/2`, `compile!/2` - real compile into a tmp ebin; modules are loaded.
    * `purge/1` - unload modules, drop their tmp ebin from the code path.
    * `with_compiled/3` - render + compile + callback + purge (always).
    * `tmp_project!/1`, `cleanup/1` - real tmp dir with files; removal.

  ## Concurrency caveat

  Compiled modules live in the one global code server. Two tests that generate
  a module with the SAME name cannot coexist: the later compile replaces the
  earlier, and `purge/1` from either removes it for both. Use `async: false`
  or give each test's generated module a unique name. Nothing here enforces it.
  Temp dirs are unique (`System.unique_integer/1`), so rendering itself is
  parallel-safe.

  ## Deviation note

  The sync subprocess runs with `cd:` set to the ggen_igniter project root (the
  only place the `ggen_igniter.sync` mix task exists); the fresh tmp dir is the
  manifest dir, verify cwd, and out root (`--manifest-dir`/`--verify-cwd`, as
  `--out` must be inside the project root the manifest is anchored to).
  """

  defmodule RenderError do
    defexception [:exit_status, :output]

    @impl true
    def message(%{exit_status: s, output: o}),
      do: "ggen_igniter.sync exited #{s}:\n#{o}"
  end

  defmodule CompileError do
    defexception [:diagnostics]

    @impl true
    def message(%{diagnostics: d}),
      do: "compile failed:\n" <> Enum.map_join(d, "\n", &format_diag/1)

    defp format_diag(%{file: f, line: l, message: m}), do: "#{f}:#{l}: #{m}"
  end

  @type diagnostic :: %{
          severity: :error | :warning,
          file: String.t() | nil,
          line: non_neg_integer() | nil,
          message: String.t()
        }

  @type render_result :: %{out_dir: String.t(), files: [String.t()], output: String.t()}

  # ---------------------------------------------------------------- render

  @doc """
  Renders `pack_spec` (`"name"` or `"name:template_stem"`) into a fresh tmp dir.
  Raises `RenderError` on a non-zero exit (a refusal).

  Options: `:ontology`, `:out` (relative to the tmp dir), `:extra_args`, `:env`,
  `:pack_dir`, `:timeout` (default 300_000).
  """
  @spec render!(String.t(), keyword()) :: render_result()
  def render!(pack_spec, opts \\ []) do
    case render(pack_spec, opts) do
      {:ok, result} -> result
      {:error, %{exit_status: s, output: o}} -> raise RenderError, exit_status: s, output: o
    end
  end

  @spec render(String.t(), keyword()) ::
          {:ok, render_result()} | {:error, %{exit_status: integer(), output: String.t()}}
  def render(pack_spec, opts \\ []) do
    dir = fresh_dir("pack_render")
    {name, stem} = split_spec(pack_spec)
    out_rel = opts[:out] || "lib/#{stem || name}.ex"
    out = Path.join(dir, out_rel)

    args =
      ["ggen_igniter.sync"] ++
        pack_args(name, stem, opts[:pack_dir]) ++
        ontology_args(opts[:ontology]) ++
        [
          "--engine",
          "sparql",
          "--out",
          out,
          "--manifest-dir",
          dir,
          "--verify-cwd",
          File.cwd!()
        ] ++ List.wrap(opts[:extra_args])

    case run_mix(args, opts[:env] || [], opts[:timeout] || 300_000) do
      {output, 0} ->
        {:ok, %{out_dir: dir, files: generated_files(dir), output: output}}

      {output, status} ->
        {:error, %{exit_status: status, output: output}}
    end
  end

  defp split_spec(spec) do
    case String.split(spec, ":", parts: 2) do
      [name, stem] -> {name, stem}
      [name] -> {name, nil}
    end
  end

  defp pack_args(name, stem, nil), do: ["--pack", if(stem, do: "#{name}:#{stem}", else: name)]

  defp pack_args(_name, nil, pack_dir), do: ["--pack-dir", Path.expand(pack_dir)]

  defp pack_args(_name, stem, pack_dir) do
    # `--pack-dir` does not take a `:STEM` suffix; resolve the template explicitly.
    {:ok, template} = GgenIgniter.Pack.discover_template(Path.expand(pack_dir), stem)
    ["--pack-dir", Path.expand(pack_dir), "--template", template]
  end

  defp ontology_args(nil), do: []
  defp ontology_args(path), do: ["--ontology", Path.expand(path)]

  # Runs `mix` through a Port so that on timeout the real OS process tree is
  # killed (`Task.shutdown(:brutal_kill)` around `System.cmd/3` only kills the
  # Erlang task and leaves `mix`/`beam` running).
  defp run_mix(args, env, timeout) do
    exe = System.find_executable("mix") || raise "mix executable not found on PATH"

    port =
      Port.open({:spawn_executable, exe}, [
        :binary,
        :exit_status,
        :stderr_to_stdout,
        :hide,
        args: args,
        cd: File.cwd!(),
        env: Enum.map(env, fn {k, v} -> {String.to_charlist(k), String.to_charlist(v)} end)
      ])

    os_pid = port |> Port.info(:os_pid) |> elem(1)
    deadline = System.monotonic_time(:millisecond) + timeout
    collect(port, os_pid, deadline, timeout, [])
  end

  defp collect(port, os_pid, deadline, timeout, acc) do
    remaining = max(deadline - System.monotonic_time(:millisecond), 0)

    receive do
      {^port, {:data, d}} ->
        collect(port, os_pid, deadline, timeout, [acc | d])

      {^port, {:exit_status, status}} ->
        {IO.iodata_to_binary(acc), status}
    after
      remaining ->
        kill_tree(os_pid)
        catch_close(port)
        out = IO.iodata_to_binary(acc)
        {out <> "sync subprocess timed out after #{timeout}ms", 124}
    end
  end

  defp catch_close(port) do
    Port.close(port)
  catch
    _, _ -> :ok
  after
    receive do
      {^port, _} -> :ok
    after
      0 -> :ok
    end
  end

  # Kills `pid` and every descendant (children first so they cannot be re-parented).
  defp kill_tree(pid) do
    {out, _} = System.cmd("pgrep", ["-P", Integer.to_string(pid)], stderr_to_stdout: true)

    for line <- String.split(out, "\n", trim: true),
        {child, ""} <- [Integer.parse(String.trim(line))],
        do: kill_tree(child)

    System.cmd("kill", ["-KILL", Integer.to_string(pid)], stderr_to_stdout: true)
    :ok
  end

  defp generated_files(dir) do
    dir
    |> Path.join("**/*")
    |> Path.wildcard(match_dot: true)
    |> Enum.reject(&(File.dir?(&1) or String.contains?(&1, "/.ggen_igniter/")))
    |> Enum.sort()
  end

  # --------------------------------------------------------------- compile

  @doc """
  Compiles `.ex` files (a list of paths, or a directory searched for `**/*.ex`)
  into a fresh tmp ebin and loads the modules. Options: `:load_path` (extra ebin
  dirs prepended to the code path for the compile).

  Returns `{:ok, modules, warning_diagnostics}` or `{:error, diagnostics}`.
  Verifier refusals (e.g. a Spark `DslError`) surface as diagnostics.
  """
  @spec compile([String.t()] | String.t(), keyword()) ::
          {:ok, [module()], [diagnostic()]} | {:error, [diagnostic()]}
  def compile(files_or_dir, opts \\ []) do
    files = expand_files(files_or_dir)
    ebin = fresh_dir("pack_compile_ebin")
    extra = opts |> Keyword.get(:load_path, []) |> List.wrap()
    Enum.each(extra, &Code.prepend_path/1)
    previous = Code.get_compiler_option(:ignore_module_conflict)
    Code.put_compiler_option(:ignore_module_conflict, true)

    try do
      case Kernel.ParallelCompiler.compile_to_path(files, ebin, return_diagnostics: true) do
        {:ok, modules, %{compile_warnings: cw, runtime_warnings: rw}} ->
          load!(modules, ebin)
          {:ok, modules, diagnostics(cw ++ rw, :warning)}

        {:error, errors, %{compile_warnings: cw, runtime_warnings: rw}} ->
          File.rm_rf!(ebin)
          {:error, diagnostics(errors, :error) ++ diagnostics(cw ++ rw, :warning)}
      end
    rescue
      e ->
        File.rm_rf!(ebin)
        {:error, [exception_diagnostic(e, files)]}
    after
      Code.put_compiler_option(:ignore_module_conflict, previous)
      Enum.each(extra, &Code.delete_path/1)
    end
  end

  @spec compile!([String.t()] | String.t(), keyword()) :: [module()]
  def compile!(files_or_dir, opts \\ []) do
    case compile(files_or_dir, opts) do
      {:ok, modules, _warnings} -> modules
      {:error, diagnostics} -> raise CompileError, diagnostics: diagnostics
    end
  end

  defp expand_files(list) when is_list(list), do: Enum.map(list, &Path.expand/1)

  defp expand_files(dir) when is_binary(dir) do
    if File.dir?(dir),
      do: dir |> Path.join("**/*.ex") |> Path.wildcard() |> Enum.sort(),
      else: [Path.expand(dir)]
  end

  defp load!(modules, ebin) do
    true = Code.prepend_path(ebin)

    for m <- modules do
      :code.purge(m)
      :code.delete(m)
      :code.purge(m)
      {:module, ^m} = Code.ensure_loaded(m)
    end
  end

  defp diagnostics(list, default_severity) do
    list
    |> Enum.map(&to_diagnostic(&1, default_severity))
    |> Enum.reject(&(&1.message =~ "already been consolidated"))
  end

  defp to_diagnostic(%{message: m} = d, default) do
    %{
      severity: Map.get(d, :severity, default),
      file: d |> Map.get(:file) |> file_string(),
      line: d |> Map.get(:position) |> line_of(),
      message: to_string(m)
    }
  end

  defp to_diagnostic(other, default),
    do: %{severity: default, file: nil, line: nil, message: inspect(other)}

  defp file_string(nil), do: nil
  defp file_string(f), do: to_string(f)

  defp line_of({l, _c}) when is_integer(l), do: l
  defp line_of(l) when is_integer(l), do: l
  defp line_of(_), do: nil

  defp exception_diagnostic(e, files) do
    %{
      severity: :error,
      file: Map.get(e, :file) || List.first(files),
      line: Map.get(e, :line),
      message: Exception.message(e)
    }
  end

  # ----------------------------------------------------------------- purge

  @doc "Unloads `modules` and removes their tmp ebin dirs from the code path and disk."
  @spec purge([module()]) :: :ok
  def purge(modules) do
    ebins =
      for m <- modules,
          path = :code.which(m),
          is_list(path),
          dir = path |> List.to_string() |> Path.dirname(),
          String.contains?(dir, "pack_compile_ebin_"),
          uniq: true,
          do: dir

    for m <- modules do
      :code.purge(m)
      :code.delete(m)
      :code.purge(m)
    end

    for dir <- ebins do
      Code.delete_path(dir)
      File.rm_rf!(dir)
    end

    :ok
  end

  # --------------------------------------------------------- with_compiled

  @doc """
  `render!/2` + `compile!/2` + `fun.(modules, render_result)`; always purges the
  modules and removes the render dir afterwards, even if `fun` raises.
  """
  @spec with_compiled(String.t(), keyword(), ([module()], render_result() -> result)) ::
          result
        when result: term()
  def with_compiled(pack_spec, render_opts, fun) do
    rendered = render!(pack_spec, render_opts)

    modules =
      try do
        compile!(Enum.filter(rendered.files, &String.ends_with?(&1, ".ex")))
      rescue
        e ->
          cleanup(rendered.out_dir)
          reraise e, __STACKTRACE__
      end

    try do
      fun.(modules, rendered)
    after
      purge(modules)
      cleanup(rendered.out_dir)
    end
  end

  # ----------------------------------------------------------- tmp projects

  @doc "Creates a real tmp dir containing `files` (`%{relative_path => content}`)."
  @spec tmp_project!(%{String.t() => String.t()}) :: String.t()
  def tmp_project!(files) do
    dir = fresh_dir("pack_project")

    for {rel, content} <- files do
      path = Path.join(dir, rel)
      File.mkdir_p!(Path.dirname(path))
      File.write!(path, content)
    end

    dir
  end

  @doc "Removes a tmp dir created by this module (use in `on_exit`)."
  @spec cleanup(String.t()) :: :ok
  def cleanup(dir) do
    File.rm_rf!(dir)
    :ok
  end

  defp fresh_dir(prefix) do
    dir = Path.join(System.tmp_dir!(), "#{prefix}_#{System.unique_integer([:positive])}")
    File.rm_rf!(dir)
    File.mkdir_p!(dir)
    dir
  end
end
