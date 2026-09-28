defmodule GgenIgniter.Test.UltracodeTwoPortManufactured do
  @moduledoc """
  Test support: manufactures a real UltraCode two-port consumer from
  `priv/ggen/ultracode-two-port-pack` and compiles it for real.

  Chicago-style, no doubles:

    1. the consumer graph is the pack ontology concatenated with an agent
       declaration fixture (plus, for falsifiers, a negative fixture);
    2. every pack template is rendered by a real `mix ggen_igniter.sync`
       subprocess into a real tmp project directory (with its manifest);
    3. the rendered `lib/**/*.ex` sources are compiled with the real compiler,
       and their real BEAM binaries are handed to the generated firewall.

  The SA2A target (`SemanticJira.Work.Task`) is the resource manufactured by
  `GgenIgniter.Test.SemanticA2AManufactured` through the real `ash.gen.*` and
  `ash_a2a.install` generators -- no Ash is hand-written.
  """

  @pack_dir Path.expand("../../priv/ggen/ultracode-two-port-pack", __DIR__)
  @fixture_dir Path.expand("../fixtures/ultracode-two-port", __DIR__)

  def pack_dir, do: @pack_dir
  def fixture(name), do: Path.join(@fixture_dir, name)

  @doc "Pack templates as `{stem, relative_to}` (the frontmatter `to:` of each)."
  def templates do
    @pack_dir
    |> Path.join("templates/*.eex")
    |> Path.wildcard()
    |> Enum.sort()
    |> Enum.map(fn path ->
      [_, to] = Regex.run(~r/^to: "(.*)"$/m, File.read!(path))
      {path |> Path.basename() |> String.split(".") |> hd(), to}
    end)
  end

  @doc "A template's `to:` rendered for the fixture agent (`agent.ttl`)."
  def fixture_path(to),
    do:
      EEx.eval_string(to,
        lib_path: "lib/ultracode_fixture/agent",
        otp_app: "ultracode_fixture",
        agent_name: "ultracode_fixture_agent"
      )

  @doc """
  Render every template against pack ontology + `agent.ttl` + `extra` fixture
  files into `dir` (a fresh tmp dir by default). Returns
  `%{dir:, results: [%{stem:, exit:, output:, path:}]}`; `path` is the
  resolved output path when the frontmatter `to:` is agent-independent, else
  the rendered file found on disk.
  """
  def render!(extra \\ [], dir \\ nil, opts \\ []) do
    dir = dir || fresh_dir!("ultracode_two_port")
    ontology = Path.join(dir, "consumer.ttl")
    agent = if Keyword.get(opts, :agent, true), do: [fixture("agent.ttl")], else: []

    File.write!(
      ontology,
      Enum.map_join(
        [Path.join(@pack_dir, "ontology.ttl")] ++ agent ++ Enum.map(extra, &fixture/1),
        "\n",
        &File.read!/1
      )
    )

    results =
      for {stem, to} <- templates() do
        {output, exit} =
          System.cmd(
            "mix",
            [
              "ggen_igniter.sync",
              "--pack",
              "ultracode-two-port-pack:" <> stem,
              "--ontology",
              ontology,
              "--out",
              Path.join(dir, to),
              "--manifest-dir",
              dir,
              "--verify-cwd",
              File.cwd!()
            ],
            cd: File.cwd!(),
            stderr_to_stdout: true
          )

        %{stem: stem, exit: exit, output: output}
      end

    %{dir: dir, results: results}
  end

  @doc "Rendered `lib/**/*.ex` sources under `dir`, sorted."
  def sources(dir), do: dir |> Path.join("lib/**/*.ex") |> Path.wildcard() |> Enum.sort()

  @doc """
  Compile rendered sources to a real ebin directory (on the code path) and
  return `[{module, beam_binary}]` read back from the written `.beam` files.
  Any compiler warning is a failure (the `--warnings-as-errors` bar).
  """
  def compile!(paths) do
    ebin = Path.join(fresh_dir!("ultracode_ebin"), "ebin")
    File.mkdir_p!(ebin)
    previous = Code.get_compiler_option(:ignore_module_conflict)
    previous_debug = Code.get_compiler_option(:debug_info)
    Code.put_compiler_option(:ignore_module_conflict, true)
    # The firewall reads compiled abstract code; a consumer build keeps
    # debug_info (Mix's default), while this repo's test env turns it off.
    Code.put_compiler_option(:debug_info, true)

    try do
      case Kernel.ParallelCompiler.compile_to_path(paths, ebin, return_diagnostics: true) do
        {:ok, modules, %{compile_warnings: [], runtime_warnings: []}} ->
          true = :code.add_patha(String.to_charlist(ebin))

          Enum.map(modules, fn module ->
            {module, File.read!(Path.join(ebin, Atom.to_string(module) <> ".beam"))}
          end)

        {:ok, _modules, warnings} ->
          raise "generated agent compiled WITH warnings: #{inspect(warnings)}"

        {:error, errors, _} ->
          raise "generated agent failed to compile: #{inspect(errors)}"
      end
    after
      Code.put_compiler_option(:ignore_module_conflict, previous)
      Code.put_compiler_option(:debug_info, previous_debug)
    end
  end

  @doc "Compile one source string and return its `{module, binary}` pairs (for falsifier injection)."
  def compile_string!(source, debug_info \\ true) do
    previous = Code.get_compiler_option(:ignore_module_conflict)
    previous_debug = Code.get_compiler_option(:debug_info)
    Code.put_compiler_option(:ignore_module_conflict, true)
    Code.put_compiler_option(:debug_info, debug_info)

    try do
      Code.compile_string(source)
    after
      Code.put_compiler_option(:ignore_module_conflict, previous)
      Code.put_compiler_option(:debug_info, previous_debug)
    end
  end

  @doc "Render + compile the compliant fixture once per VM (cached)."
  def manufactured! do
    case :persistent_term.get({__MODULE__, :manufactured}, nil) do
      nil ->
        %{dir: dir, results: results} = render!()

        for %{exit: exit, stem: stem, output: output} <- results, exit != 0 do
          raise "render of #{stem} failed:\n#{output}"
        end

        built = %{
          dir: dir,
          results: results,
          sources: sources(dir),
          beams: compile!(sources(dir))
        }

        :persistent_term.put({__MODULE__, :manufactured}, built)
        built

      built ->
        built
    end
  end

  @doc "A fresh real tmp dir (realpath-normalized)."
  def fresh_dir!(prefix) do
    # unique_integer restarts per VM: add the OS pid and a clock so a previous
    # run's directory (with its git history or manifest) is never reused.
    unique =
      "#{System.pid()}_#{System.os_time(:nanosecond)}_#{System.unique_integer([:positive])}"

    dir = Path.join(System.tmp_dir!(), "#{prefix}_#{unique}")
    File.mkdir_p!(dir)
    RealDir.real_dir!(dir)
  end
end
