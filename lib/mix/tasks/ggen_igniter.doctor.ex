defmodule Mix.Tasks.GgenIgniter.Doctor do
  @moduledoc """
  Diagnostic task: `mix ggen_igniter.doctor [--pack NAME | --pack-dir DIR] [--engine sparql|qlever] [--store-id ID] [--fix]`.

  Runs a fixed checklist of real checks (no fabricated pass output):

  1. Elixir/OTP version satisfies this project's `mix.exs` requirement (`~> 1.17`, OTP >= 25).
  2. Required deps (`rdf`, `sparql`, `igniter`, and `gno` when `--engine qlever`) are loaded
     with resolvable `:vsn`.
  3. Advisory for the known `sparql` 0.3.12 `FILTER NOT EXISTS` + `BIND` inside `UNION` bug.
  4. The CURRENT project's own `mix.exs` doesn't restrict its direct `igniter` dependency
     with `:only` (real conflict: `ggen_igniter` needs `igniter` unconditionally, so a
     consumer's own `only: [:dev, :test]`-restricted declaration makes Mix's resolver
     refuse). `--fix` relaxes it for real; without `--fix` this is diagnostic only.
  5. Same as 4, for `sourceror` (only applicable if the current project declares it
     directly at all).
  6. `config :dcatr, env: ...` is present in the current project's `config/config.exs`
     whenever `:gno`/`:dcatr` are in its dependency tree (`:gno`'s `Fuseki` adapter raises
     at compile time without it). `--fix` adds the missing entry for real.
  7. Every Ash domain module (`use Ash.Domain`) found under the current project's `lib/`
     is registered in `config :OTP_APP, ash_domains: [...]` (an unregistered domain is a
     hard compile error under `mix compile --warnings-as-errors`). `--fix` registers any
     missing one(s) for real.
  8. (only with `--engine qlever` or a pack ontology naming a `gnoa:Qlever` store via
     `--store-id`) the QLever endpoint is really reachable via a real `ASK` query.
  9. Pack `ontology.ttl` exists and parses as valid Turtle.
  10. At least one gate query (`gates/*.rq`) is present.
  11. At least one template (`templates/*.{eex,tmpl}`) is present.
  12. Every gate query is syntactically valid SPARQL (parse-only, no execution).
  13. Target (cwd) git status -- clean vs dirty is reported, never fails the run by itself.
  14. `native/ggen_graph_nif` is compiled and up to date: the built `priv/native/ggen_graph_nif.so`
      exists and is newer than every `.rs` source file under the crate (a fast mtime proxy); if
      the `.so` is missing or stale, falls back to a real `cargo build --quiet` and reports real
      stderr on failure.
  15. `GgenIgniter.Query.Oxigraph` actually works: runs a real `SELECT * WHERE { ?s ?p ?o }`
      SPARQL query against a tiny real in-memory `%RDF.Graph{}` through the native oxigraph
      engine and confirms it returns without raising -- a functional smoke test, not just
      "does the NIF load".
  16. (only with `--hex-check`, off by default) hex-publish readiness: shells out to a real
      `mix hex.build` and reports its real output, plus checks `mix.exs`'s `package[:description]`
      and `package[:licenses]` are both present and non-empty.

  Checks 9-12 only run when `--pack`/`--pack-dir` is given; without it, only checks 1-3
  and 4-7 (and 8, if `--engine qlever` was explicitly passed with a graph-free reachability
  check is not possible, so 8 is skipped) run. Checks 4-7 and 13-15 always run. Check 16 only
  runs with `--hex-check` (it shells out to `mix hex.build`, which is slow, so it stays
  off by default to keep `mix ggen_igniter.doctor` fast).

  ## `--fix`

  Checks 4-7 are real fixes (`GgenIgniter.DoctorFixes`), not just diagnostics: passing
  `--fix` applies each detected, safely-recognized fix directly to the CURRENT project
  (`File.cwd!()`) -- the real consumer app `doctor` is running inside, never a
  test-harness scaffold -- and the check line reports exactly what changed (prefixed
  `FIXED:`), or that there was nothing to fix. Without `--fix`, these four checks are
  read-only: a real, fixable problem is reported as a `⚠` warning naming the exact fix to
  run; a real problem whose exact shape isn't safely automatable is reported as a `✘`
  error rather than silently skipped or guessed at.

  Exits non-zero (via `Igniter.add_issue/2`) only if any check comes back `:error`.
  """
  use Igniter.Mix.Task

  alias GgenIgniter.{DoctorFixes, Ontology, Pack}

  @impl Igniter.Mix.Task
  def info(_argv, _composing_task) do
    %Igniter.Mix.Task.Info{
      group: :ggen_igniter,
      example: "mix ggen_igniter.doctor --pack audit-trail-pack",
      positional: [],
      schema: [
        pack: :string,
        pack_dir: :string,
        engine: :string,
        store_id: :string,
        hex_check: :boolean,
        fix: :boolean
      ],
      required: []
    }
  end

  @impl Igniter.Mix.Task
  def igniter(igniter) do
    opts = igniter.args.options

    pack_dir =
      if opts[:pack] not in [nil, ""] or opts[:pack_dir] not in [nil, ""] do
        Pack.resolve_dir!(opts)
      end

    checks =
      [
        check_elixir_otp_version(),
        check_deps(opts),
        check_sparql_advisory(),
        check_igniter_only_relaxation(opts),
        check_sourceror_only_relaxation(opts),
        check_dcatr_env_config(opts),
        check_ash_domains_registered(opts)
      ] ++
        maybe_check_qlever(opts, pack_dir) ++
        if(pack_dir, do: pack_checks(pack_dir), else: []) ++
        [
          check_git_status(),
          check_nif_compiles(),
          check_oxigraph_smoke_test()
        ] ++
        maybe_check_hex_publish(opts)

    igniter = Enum.reduce(checks, igniter, &print_and_collect/2)

    if Enum.any?(checks, fn {status, _msg} -> status == :error end) do
      IO.puts("✘ ggen_igniter.doctor: one or more checks failed (see ✘ lines above)")
      # `Igniter.add_issue/2` only halts the real OS process under `--check`
      # (see `Igniter.halt_if_fails_check!/2`); a doctor task needs a real
      # non-zero exit code unconditionally, so halt directly here.
      System.halt(1)
    else
      Igniter.add_notice(igniter, "ggen_igniter.doctor: all checks passed (see output above)")
    end
  end

  defp print_and_collect({status, message}, igniter) do
    prefix = %{ok: "✔", warn: "⚠", error: "✘"}[status]
    IO.puts("#{prefix} #{message}")
    igniter
  end

  # 1. Elixir/OTP version
  defp check_elixir_otp_version do
    elixir_version = System.version()
    otp_release = :erlang.system_info(:otp_release) |> List.to_string()
    otp_major = otp_release |> String.to_integer()

    elixir_ok? = Version.match?(elixir_version, "~> 1.17")
    otp_ok? = otp_major >= 25

    cond do
      elixir_ok? and otp_ok? ->
        {:ok, "Elixir #{elixir_version} / OTP #{otp_release}"}

      not elixir_ok? ->
        {:error, "Elixir #{elixir_version} does not satisfy ~> 1.17 (mix.exs requirement)"}

      true ->
        {:error, "OTP #{otp_release} is below the required >= 25"}
    end
  end

  # 2. Required deps present + resolvable versions
  defp check_deps(opts) do
    needs_gno? = opts[:engine] == "qlever"

    required = [:rdf, :sparql, :igniter] ++ if needs_gno?, do: [:gno], else: []

    results =
      Enum.map(required, fn app ->
        Application.ensure_loaded(app)

        case Application.spec(app, :vsn) do
          nil -> {:error, app, nil}
          vsn -> {:ok, app, List.to_string(vsn)}
        end
      end)

    case Enum.filter(results, fn {status, _, _} -> status == :error end) do
      [] ->
        summary = Enum.map_join(results, ", ", fn {:ok, app, vsn} -> "#{app} #{vsn}" end)
        {:ok, summary}

      errors ->
        missing = Enum.map_join(errors, ", ", fn {:error, app, _} -> to_string(app) end)
        {:error, ":#{missing} not loaded -- add the missing dep(s) or drop --engine qlever"}
    end
  end

  # 3. Known sparql engine bug advisory
  defp check_sparql_advisory do
    Application.ensure_loaded(:sparql)

    case Application.spec(:sparql, :vsn) do
      nil ->
        {:warn,
         "sparql not loaded -- cannot check for the known 0.3.12 UNION/FILTER NOT EXISTS bug"}

      vsn ->
        version = List.to_string(vsn)

        if Version.match?(version, "<= 0.3.12") do
          {:warn,
           "sparql #{version}: FILTER NOT EXISTS + BIND inside UNION raises Protocol.UndefinedError " <>
             "(see query/qlever.ex moduledoc) -- use --engine qlever for gate queries with this shape"}
        else
          {:ok,
           "sparql #{version} (newer than the known-bad 0.3.12 UNION/FILTER NOT EXISTS advisory)"}
        end
    end
  end

  # 4-7. Real project-hygiene fixes (GgenIgniter.DoctorFixes) -- diagnostic-only
  # without --fix, applied for real to the CURRENT project (File.cwd!()) with it.
  defp check_igniter_only_relaxation(opts) do
    fix_or_check(
      opts,
      &DoctorFixes.check_dep_only(&1, :igniter),
      &DoctorFixes.fix_dep_only!(&1, :igniter)
    )
  end

  defp check_sourceror_only_relaxation(opts) do
    fix_or_check(
      opts,
      &DoctorFixes.check_dep_only(&1, :sourceror),
      &DoctorFixes.fix_dep_only!(&1, :sourceror)
    )
  end

  defp check_dcatr_env_config(opts) do
    fix_or_check(
      opts,
      &DoctorFixes.check_dcatr_env_config/1,
      &DoctorFixes.fix_dcatr_env_config!/1
    )
  end

  defp check_ash_domains_registered(opts) do
    fix_or_check(opts, &DoctorFixes.check_ash_domains/1, &DoctorFixes.fix_ash_domains!/1)
  end

  # Shared glue between a real `DoctorFixes` check/fix pair and doctor's
  # `{:ok | :warn | :error, message}` check-result vocabulary. Without
  # `--fix`, only inspects (never writes); with `--fix`, applies the real
  # fix and reports what changed -- catching (never letting propagate) the
  # `RuntimeError` a fix raises when it hits a shape it refuses to guess at,
  # turning that into a real `:error` check result instead of crashing the
  # whole doctor run.
  defp fix_or_check(opts, check_fn, fix_fn) do
    project_dir = File.cwd!()

    if opts[:fix] do
      try do
        case fix_fn.(project_dir) do
          {:fixed, msg} -> {:ok, "FIXED: #{msg}"}
          {:ok, msg} -> {:ok, msg}
        end
      rescue
        error -> {:error, Exception.message(error)}
      end
    else
      case check_fn.(project_dir) do
        {:ok, msg} -> {:ok, msg}
        {:fixable, msg} -> {:warn, "#{msg} -- run `mix ggen_igniter.doctor --fix` to fix"}
        {:unrecognized, msg} -> {:error, msg}
      end
    end
  end

  # 8. Qlever endpoint reachable (only if --engine qlever and a store can be resolved)
  defp maybe_check_qlever(opts, pack_dir) do
    if opts[:engine] == "qlever" do
      [check_qlever_reachable(opts, pack_dir)]
    else
      []
    end
  end

  defp check_qlever_reachable(opts, pack_dir) do
    store_id = opts[:store_id]
    ontology_path = pack_dir && Pack.default_ontology(pack_dir)

    cond do
      is_nil(store_id) ->
        {:error,
         "--engine qlever given but --store-id is missing -- cannot resolve a QLever store to check"}

      is_nil(ontology_path) or not File.exists?(ontology_path) ->
        {:error,
         "--engine qlever given but no pack ontology found to resolve --store-id #{store_id} against " <>
           "(pass --pack/--pack-dir)"}

      true ->
        try do
          graph = Ontology.load!(ontology_path)
          store = GgenIgniter.Query.Qlever.load_store!(graph, store_id)

          case GgenIgniter.Query.Qlever.run(store, "ASK { ?s ?p ?o }") do
            rows when is_list(rows) ->
              {:ok, "QLever endpoint for #{store_id} reachable"}
          end
        rescue
          error ->
            {:error, "QLever endpoint for #{store_id} unreachable: #{Exception.message(error)}"}
        end
    end
  end

  # 9-12: pack-scoped checks
  defp pack_checks(pack_dir) do
    [
      check_ontology(pack_dir),
      check_gate_queries_present(pack_dir),
      check_template_present(pack_dir),
      check_gate_queries_parse(pack_dir)
    ]
  end

  # 9. Pack ontology present + valid Turtle
  defp check_ontology(pack_dir) do
    path = Pack.default_ontology(pack_dir)

    if File.exists?(path) do
      case RDF.Turtle.read_file(path) do
        {:ok, %RDF.Graph{} = graph} ->
          {:ok, "ontology.ttl parses (#{RDF.Graph.statement_count(graph)} triples)"}

        {:error, reason} ->
          {:error, "ontology.ttl failed to parse: #{inspect(reason)}"}
      end
    else
      {:error, "ontology.ttl missing at #{path}"}
    end
  end

  # 10. At least one gate query present
  defp check_gate_queries_present(pack_dir) do
    queries = Pack.discover_queries(pack_dir)

    if queries == [] do
      {:error, "no *.rq files in #{Path.join(pack_dir, "gates")}"}
    else
      names = Enum.map_join(queries, ", ", fn {name, _path} -> name end)
      count = length(queries)
      {:ok, "#{count} gate quer#{if count == 1, do: "y", else: "ies"} found: #{names}"}
    end
  end

  # 11. At least one template present
  defp check_template_present(pack_dir) do
    templates_dir = Path.join(pack_dir, "templates")
    paths = Path.wildcard(Path.join(templates_dir, "*.{eex,tmpl}"))

    case paths do
      [] ->
        {:error, "no *.eex/*.tmpl files in #{templates_dir}"}

      _ ->
        names = Enum.map_join(paths, ", ", &Path.basename/1)
        count = length(paths)
        {:ok, "#{count} template#{if count == 1, do: "", else: "s"} found: #{names}"}
    end
  end

  # 12. Gate queries are syntactically valid SPARQL
  defp check_gate_queries_parse(pack_dir) do
    queries = Pack.discover_queries(pack_dir)

    failures =
      queries
      |> Enum.map(fn {name, path} ->
        case SPARQL.query(File.read!(path)) do
          %SPARQL.Query{} -> nil
          {:error, reason} -> "#{name} (#{path}) failed to parse: #{inspect(reason)}"
        end
      end)
      |> Enum.reject(&is_nil/1)
      |> then(fn f -> if f == [], do: nil, else: f end)

    cond do
      queries == [] ->
        {:warn, "no gate queries to parse-check"}

      is_nil(failures) ->
        {:ok, "all #{length(queries)} gate queries parse"}

      true ->
        {:error, Enum.join(failures, "; ")}
    end
  rescue
    error -> {:error, "gate query parse check raised: #{Exception.message(error)}"}
  end

  # 13. Target dir git status
  defp check_git_status do
    case System.cmd("git", ["status", "--porcelain"], cd: File.cwd!(), stderr_to_stdout: true) do
      {output, 0} ->
        dirty_count = output |> String.split("\n", trim: true) |> length()

        if dirty_count == 0 do
          {:ok, "git clean"}
        else
          {:warn, "git dirty (#{dirty_count} uncommitted change(s))"}
        end

      {output, _code} ->
        {:error, "not a git repo (or git not on PATH): #{String.trim(output)}"}
    end
  rescue
    error -> {:error, "not a git repo (or git not on PATH): #{Exception.message(error)}"}
  end

  # 14. native/ggen_graph_nif compiles / is up to date
  @nif_crate_dir "native/ggen_graph_nif"
  @nif_so_path "priv/native/ggen_graph_nif.so"

  defp check_nif_compiles do
    crate_dir = Path.join(File.cwd!(), @nif_crate_dir)
    so_path = Path.join(File.cwd!(), @nif_so_path)

    cond do
      not File.dir?(crate_dir) ->
        {:error, "#{@nif_crate_dir} directory not found"}

      nif_so_up_to_date?(so_path, crate_dir) ->
        {:ok,
         "#{@nif_so_path} exists and is newer than every .rs source file (skipped real build)"}

      true ->
        case System.cmd("cargo", ["build", "--quiet"], cd: crate_dir, stderr_to_stdout: true) do
          {_output, 0} ->
            {:ok, "#{@nif_crate_dir} compiles (real cargo build --quiet)"}

          {output, code} ->
            {:error,
             "#{@nif_crate_dir} failed to compile (cargo exit #{code}): #{String.trim(output)}"}
        end
    end
  rescue
    error -> {:error, "#{@nif_crate_dir} compile check raised: #{Exception.message(error)}"}
  end

  defp nif_so_up_to_date?(so_path, crate_dir) do
    with true <- File.exists?(so_path),
         {:ok, %File.Stat{mtime: so_mtime}} <- File.stat(so_path) do
      src_dir = Path.join(crate_dir, "src")

      src_dir
      |> Path.join("**/*.rs")
      |> Path.wildcard()
      |> Enum.all?(&rs_source_not_newer_than?(&1, so_mtime))
    else
      _ -> false
    end
  end

  defp rs_source_not_newer_than?(rs_path, so_mtime) do
    case File.stat(rs_path) do
      {:ok, %File.Stat{mtime: rs_mtime}} -> rs_mtime <= so_mtime
      {:error, _} -> false
    end
  end

  # 15. GgenIgniter.Query.Oxigraph functional smoke test
  defp check_oxigraph_smoke_test do
    graph =
      RDF.Graph.new([
        {RDF.iri("http://example.org/s"), RDF.iri("http://example.org/p"),
         RDF.iri("http://example.org/o")}
      ])

    case GgenIgniter.Query.Oxigraph.run(graph, "SELECT * WHERE { ?s ?p ?o }") do
      rows when is_list(rows) ->
        {:ok,
         "GgenIgniter.Query.Oxigraph real SELECT query against an in-memory graph returned #{length(rows)} row(s)"}
    end
  rescue
    error -> {:error, "GgenIgniter.Query.Oxigraph smoke test raised: #{Exception.message(error)}"}
  end

  # 16. hex-publish readiness (only with --hex-check)
  defp maybe_check_hex_publish(opts) do
    if opts[:hex_check] do
      [check_hex_publish_readiness()]
    else
      []
    end
  end

  defp check_hex_publish_readiness do
    package = Mix.Project.config()[:package] || []
    description = package[:description]
    licenses = package[:licenses]

    metadata_errors =
      []
      |> then(fn acc ->
        if description in [nil, ""],
          do: ["package[:description] is missing/empty" | acc],
          else: acc
      end)
      |> then(fn acc ->
        if licenses in [nil, []], do: ["package[:licenses] is missing/empty" | acc], else: acc
      end)

    case System.cmd("mix", ["hex.build"], cd: File.cwd!(), stderr_to_stdout: true) do
      {output, 0} when metadata_errors == [] ->
        {:ok, "mix hex.build succeeded and package metadata is present:\n#{String.trim(output)}"}

      {output, 0} ->
        {:error,
         "mix hex.build succeeded but metadata is incomplete (#{Enum.join(metadata_errors, "; ")}):\n#{String.trim(output)}"}

      {output, code} ->
        {:error, "mix hex.build failed (exit #{code}): #{String.trim(output)}"}
    end
  rescue
    error -> {:error, "hex-publish readiness check raised: #{Exception.message(error)}"}
  end
end
