defmodule Mix.Tasks.GgenIgniter.Doctor do
  @moduledoc """
  Diagnostic task: `mix ggen_igniter.doctor [--pack NAME | --pack-dir DIR] [--engine sparql|qlever] [--store-id ID]`.

  Runs a fixed checklist of real checks (no fabricated pass output):

  1. Elixir/OTP version satisfies this project's `mix.exs` requirement (`~> 1.17`, OTP >= 25).
  2. Required deps (`rdf`, `sparql`, `igniter`, and `gno` when `--engine qlever`) are loaded
     with resolvable `:vsn`.
  3. Advisory for the known `sparql` 0.3.12 `FILTER NOT EXISTS` + `BIND` inside `UNION` bug.
  4. (only with `--engine qlever` or a pack ontology naming a `gnoa:Qlever` store via
     `--store-id`) the QLever endpoint is really reachable via a real `ASK` query.
  5. Pack `ontology.ttl` exists and parses as valid Turtle.
  6. At least one gate query (`gates/*.rq`) is present.
  7. At least one template (`templates/*.{eex,tmpl}`) is present.
  8. Every gate query is syntactically valid SPARQL (parse-only, no execution).
  9. Target (cwd) git status -- clean vs dirty is reported, never fails the run by itself.

  Checks 5-8 only run when `--pack`/`--pack-dir` is given; without it, only checks 1-3
  (and 4, if `--engine qlever` was explicitly passed with a graph-free reachability
  check is not possible, so 4 is skipped) run.

  Exits non-zero (via `Igniter.add_issue/2`) only if any check comes back `:error`.
  """
  use Igniter.Mix.Task

  alias GgenIgniter.{Ontology, Pack}

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
        store_id: :string
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
        check_sparql_advisory()
      ] ++
        maybe_check_qlever(opts, pack_dir) ++
        (if pack_dir, do: pack_checks(pack_dir), else: []) ++
        [check_git_status()]

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
        {:warn, "sparql not loaded -- cannot check for the known 0.3.12 UNION/FILTER NOT EXISTS bug"}

      vsn ->
        version = List.to_string(vsn)

        if Version.match?(version, "<= 0.3.12") do
          {:warn,
           "sparql #{version}: FILTER NOT EXISTS + BIND inside UNION raises Protocol.UndefinedError " <>
             "(see query/qlever.ex moduledoc) -- use --engine qlever for gate queries with this shape"}
        else
          {:ok, "sparql #{version} (newer than the known-bad 0.3.12 UNION/FILTER NOT EXISTS advisory)"}
        end
    end
  end

  # 4. Qlever endpoint reachable (only if --engine qlever and a store can be resolved)
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
        {:error, "--engine qlever given but --store-id is missing -- cannot resolve a QLever store to check"}

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

  # 5-8: pack-scoped checks
  defp pack_checks(pack_dir) do
    [
      check_ontology(pack_dir),
      check_gate_queries_present(pack_dir),
      check_template_present(pack_dir),
      check_gate_queries_parse(pack_dir)
    ]
  end

  # 5. Pack ontology present + valid Turtle
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

  # 6. At least one gate query present
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

  # 7. At least one template present
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

  # 8. Gate queries are syntactically valid SPARQL
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

  # 9. Target dir git status
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
end
