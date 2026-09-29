defmodule B1d.SagaHelper do
  @moduledoc """
  Shared Chicago-style plumbing for the B1d reactor-pack tests: writes an ontology (fixture text,
  optionally mutated) to a real tmp dir, renders `reactor-scaffold-pack:saga` with a REAL
  `mix ggen_igniter.sync` subprocess (out path is the row's own `rx:outPath` fact), compiles the
  result with the real compiler, and offers real Agent-backed ledger utilities. No doubles.
  """
  alias GgenIgniter.Test.PackCompile

  @fixtures Path.expand(".", __DIR__)

  def fixture(name), do: File.read!(Path.join(@fixtures, name))

  def render(ttl_text, pack \\ "reactor-scaffold-pack:saga", out \\ "<%= out_path %>") do
    dir = PackCompile.tmp_project!(%{"ontology.ttl" => ttl_text})

    try do
      PackCompile.render(
        pack,
        [ontology: Path.join(dir, "ontology.ttl"), out: out] ++ pack_dir_opt()
      )
    after
      PackCompile.cleanup(dir)
    end
  end

  # B1D_PACK_DIR points the same tests at another pack tree (used to witness RED against the
  # pre-change pack exported from git); unset in normal runs.
  defp pack_dir_opt do
    case System.get_env("B1D_PACK_DIR") do
      nil -> []
      dir -> [pack_dir: dir]
    end
  end

  @doc """
  Real sync subprocess into a known tmp dir; returns `{exit_status, output, files_written}` where
  `files_written` are the generated files (manifest bookkeeping excluded) - for refusal tests.
  """
  def refuse(ttl_text, pack \\ "reactor-scaffold-pack:saga") do
    dir = PackCompile.tmp_project!(%{"ontology.ttl" => ttl_text})

    pack_args =
      case pack_dir_opt() do
        [] ->
          ["--pack", pack]

        [pack_dir: d] ->
          [_, stem] = String.split(pack, ":")
          {:ok, t} = GgenIgniter.Pack.discover_template(Path.expand(d), stem)
          ["--pack-dir", Path.expand(d), "--template", t]
      end

    {out, status} =
      System.cmd(
        "mix",
        ["ggen_igniter.sync"] ++
          pack_args ++
          [
            "--engine",
            "sparql",
            "--ontology",
            Path.join(dir, "ontology.ttl"),
            "--out",
            Path.join(dir, "<%= out_path %>"),
            "--manifest-dir",
            dir,
            "--verify-cwd",
            File.cwd!()
          ],
        cd: File.cwd!(),
        stderr_to_stdout: true
      )

    written =
      dir
      |> Path.join("**/*")
      |> Path.wildcard(match_dot: true)
      |> Enum.reject(
        &(File.dir?(&1) or String.ends_with?(&1, "ontology.ttl") or
            String.contains?(&1, "/.ggen_igniter/"))
      )

    PackCompile.cleanup(dir)
    {status, out, written}
  end

  def render!(ttl_text, pack \\ "reactor-scaffold-pack:saga", out \\ "<%= out_path %>") do
    {:ok, r} = render(ttl_text, pack, out)
    r
  end

  @doc "Render + compile; runs `fun.(modules, render_result)` then always purges and cleans up."
  def with_saga(ttl_text, extra_sources \\ [], fun) do
    r = render!(ttl_text)
    ex = Enum.filter(r.files, &String.ends_with?(&1, ".ex"))
    aux = PackCompile.tmp_project!(Map.new(extra_sources, fn {n, src} -> {n, src} end))

    modules =
      try do
        PackCompile.compile!(Path.wildcard(Path.join(aux, "**/*.ex")) ++ ex)
      rescue
        e ->
          PackCompile.cleanup(r.out_dir)
          PackCompile.cleanup(aux)
          reraise e, __STACKTRACE__
      end

    try do
      fun.(modules, r)
    after
      PackCompile.purge(modules)
      PackCompile.cleanup(r.out_dir)
      PackCompile.cleanup(aux)
    end
  end

  @doc """
  Builds a ledger-saga ontology (test INPUT). `steps` is `[{name, deps, props}]` where `props` is a
  keyword of `rx:` predicates to string values (e.g. `failAlways: "true"`); `reactor_props` likewise.
  """
  def saga_ttl(module, ledger, steps, reactor_props \\ []) do
    slug = module |> String.replace(".", "_") |> String.downcase()

    reactor =
      [
        "ex:reactor a rx:Reactor ; rx:moduleName #{inspect(module)} ; rx:outPath #{inspect("lib/#{slug}.ex")}",
        "rx:ledger #{inspect(ledger)}"
      ] ++ for({k, v} <- reactor_props, do: "rx:#{k} #{inspect(to_string(v))}")

    stanzas =
      for {name, deps, props} <- steps do
        parts =
          [
            "ex:#{name} a rx:SagaStep",
            "rx:inReactor ex:reactor",
            "rx:name #{inspect(name)}",
            "rx:kind \"ledger\""
          ] ++
            if(deps == [],
              do: [],
              else: ["rx:dependsOn " <> Enum.map_join(deps, ", ", &"ex:#{&1}")]
            ) ++
            for({k, v} <- props, do: "rx:#{k} #{inspect(to_string(v))}")

        Enum.join(parts, " ;\n    ") <> " ."
      end

    "@prefix rx: <https://ggen-igniter.dev/ontology/reactor-scaffold#> .\n@prefix ex: <https://example.test/#{slug}#> .\n" <>
      Enum.join(reactor, " ;\n    ") <> " .\n" <> Enum.join(stanzas, "\n")
  end

  def start_ledger(name) do
    {:ok, pid} = Agent.start_link(fn -> [] end, name: name)
    pid
  end

  def ledger(name), do: name |> Agent.get(& &1) |> Enum.reverse()

  def stop_ledger(pid), do: if(Process.alive?(pid), do: Agent.stop(pid))

  @doc "Peak simultaneous in-flight count from an ordered ledger of {:enter,_}/{:leave,_} events."
  def high_water(events) do
    events
    |> Enum.reduce({0, 0}, fn
      {:enter, _}, {cur, max} -> {cur + 1, max(cur + 1, max)}
      {:leave, _}, {cur, max} -> {cur - 1, max}
      _, acc -> acc
    end)
    |> elem(1)
  end

  @doc "Step graph of a compiled reactor: %{step => MapSet of upstream step names}."
  def step_graph(mod) do
    for step <- Reactor.Info.to_struct!(mod).steps, into: %{} do
      ups =
        for %{source: %Reactor.Template.Result{name: n}} <- step.arguments,
            into: MapSet.new(),
            do: n

      {step.name, ups}
    end
  end
end
