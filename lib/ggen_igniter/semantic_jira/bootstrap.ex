defmodule GgenIgniter.SemanticJira.Bootstrap do
  @moduledoc """
  Cold bootstrap (GC-26.9.23 gate GC23-1; PRD section 8.1, PR-006, PR-013;
  ARD sections 7 and 16): reconstructs the bounded system state from durable
  artifacts only and emits it as canonical JSON plus
  `state_digest = "sha256:" <> hex(sha256(canonical JSON of the state))`.

  Allowed sources (ARD section 16), each an explicit argument:

    * git refs -- `git -C <checkout>` reads of `HEAD`, branches and the
      covered-path history (`Bootstrap.Git`);
    * canonical RDF -- the goal graph (`--goal`, exactly one root
      GoalCheckpoint by `prose/root.rq`) and work graphs (`--graphs`, Turtle
      or kernel JSON), read through the pack queries
      `priv/ggen/semantic-jira-pack/bootstrap/*.rq` (`Bootstrap.Graph`);
    * receipts -- fleet R-schema JSON in `--receipts-dir` directories
      (`Bootstrap.Receipts`; each directory is reported in `inputs` as
      `"read"` or `"absent"`, and an unreadable one is refused
      `input_unreadable`);
    * OCEL/TransitionLog -- `--ledger`, read through
      `GgenIgniter.SemanticJira.TransitionLog.fetch/1` (a tampered ledger is
      refused);
    * provider registry -- `--registry`, a recipe registry export (JSON
      object `capability_id => recipe`, optionally under `"recipes"`);
    * explicit configuration -- `--fleet` (fleet matrix or universe) and
      `--checkout owner/repo=DIR` (`Bootstrap.Subjects`);
    * authority rules -- `sj:authorityCeiling` / `sj:authorityRequirement` /
      `sj:exclusion` of the graphs.

  Forbidden dependencies are refused before anything is read
  (`Bootstrap.Guard`): any path under `.claude` / `.zcode` or naming a
  transcript (`forbidden_input`), and any LLM credential variable in the
  environment (`llm_credential_present`, broken_term `mu_on_O`).

  Output (`run/1` -> `%{state: map, json: binary, digest: String.t()}`):

    * `checkpoint` -- the active GoalCheckpoint: root, gates (boundary
      class, court command, orders, last gate receipt; a gate receipt
      confers its standing only at the root repository's exact `HEAD`),
      successor buckets;
    * `subjects` -- repositories, exact `HEAD` SHAs, branches, fleet class;
    * `capabilities` -- `sj:capabilityId`s from the graphs and the registry,
      with the orders requiring each;
    * `authority` -- root and per-order ceilings, requirements, exclusions;
    * `orders` -- per work order: derived standing and its source, the
      linked receipt, invalidated/unlinked receipts, tuple digest,
      definition digest, dependencies and frontier class;
    * `frontier` -- `GgenIgniter.SemanticJira.frontier_from_events/4` over
      the kernel orders, the applicable ledger events and the receipt
      evidence, with origins resolved against the goal graph's admission
      index (`Authority.index/1`, SJ-002 AC-04);
    * `ledger`, `receipts`, `registry`, `inputs` (content digests and
      host-independent refs of every input and pack query) and
      `exceptions` (BLOCKED / UNSUPPORTED / REFUSED state).

  Derived standing (PR-006: standing is never read from a stored literal;
  `sj:standing` is not even selected). An order's standing is the precedence
  best of its CURRENT linked receipts (`Bootstrap.Receipts.best/1`), then the
  latest applicable TransitionLog event. A receipt is current iff its
  `identity.subject_sha` covers the order's path scope at the observed
  `HEAD` (`Bootstrap.Git.covered_commit/3` equal at both revisions; path
  scope minus cross-repository entries and minus `receipts/`, since a
  receipt cannot be part of its own subject). A receipt whose subject no
  longer covers the current commit confers nothing: the order returns to
  UNKNOWN and re-enters the frontier (F6); deleting a receipt removes its
  standing and changes the digest (F5). The order's `covered_commit_status`
  says what `HEAD` showed -- `observed`, `none_in_scope` (no commit ever
  changed a covered path), `unreadable` (the git read failed) or
  `subject_unresolved` -- and an invalidated receipt carries the matching
  reason: `subject_advanced` only for an observed later change,
  `scope_never_committed` and `current_covered_commit_unreadable` otherwise.

  A ledger event is a transition record, not a source of standing. It
  applies only when its `definition_digest` equals the order's current
  kernel definition digest and, unless its `to` is `UNKNOWN` (a demotion
  confers nothing and only returns the order to the frontier), only when its
  `receipt_digest` is the `sha256` of a CURRENT linked receipt of that order
  whose kernel standing equals `to` (`receipt_binding/2`). Otherwise the
  event is reported inapplicable: `receipt_not_current` (it names a receipt
  of the order that the covered-path law invalidated), `receipt_digest_unresolved`
  (it names no linked receipt of the order: absent, deleted, unlinked or
  fabricated) or `receipt_standing_mismatch` (the receipt it names carries
  another standing). So a ledger line cannot confer a standing that no
  current receipt carries: deleting the receipt (F5) or a commit on the
  covered path (F6) withdraws the event's standing together with the
  receipt's. An ALIVE event of an order with `candidate_sha` additionally
  applies only while that SHA still covers the order's path scope.

  The state carries no timestamp, no absolute path and no home directory
  (`Guard.absolute_paths/1` refuses `absolute_path_in_state`), so two cold
  runs over the same artifacts are byte-identical. No LLM, network or clock
  participates.
  """

  alias GgenIgniter.Digest
  alias GgenIgniter.SemanticJira
  alias GgenIgniter.SemanticJira.{Authority, Reconciler, TransitionLog}
  alias GgenIgniter.SemanticJira.Bootstrap.{Git, Graph, Guard, Receipts, Subjects}

  @schema "semantic-jira-bootstrap/v1"
  @capability ~r/\A[a-z0-9][a-z0-9_.-]*:[a-z0-9][a-z0-9_.:-]*\z/
  @cross_repository ~r/\A[A-Za-z0-9_.-]+:/
  @successor Graph.sj() <> "Successor"

  @type refusal :: %{code: atom(), subject: String.t() | nil, detail: String.t()}
  @type result :: %{state: map(), json: String.t(), digest: String.t()}

  @doc "The state schema identifier."
  @spec schema() :: String.t()
  def schema, do: @schema

  @doc """
  Runs the bootstrap. Options: `:fleet`, `:goal`, `:ledger` (paths,
  required); `:graphs`, `:receipts_dirs` (path lists); `:registry` (path);
  `:checkouts` (`"owner/repo=DIR"` strings); `:pack_dir`; `:env` (the
  environment map checked for LLM credentials, default `System.get_env/0`).
  """
  @spec run(keyword()) :: {:ok, result()} | {:refused, [refusal()]}
  def run(opts) do
    with :ok <- no_llm(Keyword.get_lazy(opts, :env, &System.get_env/0)),
         {:ok, args} <- arguments(opts),
         :ok <- fence(args),
         {:ok, queries} <- queries(args.pack_dir),
         {:ok, world} <- observe(args, queries) do
      world |> derive() |> finish()
    end
  end

  @doc "Canonical JSON: object keys sorted at every depth, compact separators."
  @spec canonical_json(term()) :: String.t()
  def canonical_json(term), do: term |> ordered() |> Jason.encode!()

  defp ordered(%{} = map) when not is_struct(map) do
    map
    |> Enum.map(fn {key, value} -> {to_string(key), ordered(value)} end)
    |> Enum.sort_by(&elem(&1, 0))
    |> Jason.OrderedObject.new()
  end

  defp ordered(list) when is_list(list), do: Enum.map(list, &ordered/1)
  defp ordered(atom) when is_atom(atom) and atom not in [nil, true, false], do: to_string(atom)
  defp ordered(value), do: value

  @doc "The document `run/1` writes: `{\"state\": ..., \"state_digest\": ...}` + newline."
  @spec document(result()) :: String.t()
  def document(%{state: state, digest: digest}),
    do: canonical_json(%{"state" => state, "state_digest" => digest}) <> "\n"

  @doc "One line per refusal."
  @spec render_refusal(refusal()) :: String.t()
  def render_refusal(%{code: code, subject: subject, detail: detail}),
    do: "REFUSED(#{code}) #{subject || "-"}: #{detail}"

  # ── fences ──────────────────────────────────────────────────────────────

  defp no_llm(env) do
    case Guard.llm_credentials(env) do
      [] ->
        :ok

      names ->
        refused(
          :llm_credential_present,
          nil,
          "LLM credential variables set: #{Enum.join(names, ", ")} (broken_term mu_on_O: " <>
            "the cold bootstrap is a no-LLM court input; run it under env -i)"
        )
    end
  end

  defp arguments(opts) do
    with {:ok, fleet} <- required(opts, :fleet),
         {:ok, goal} <- required(opts, :goal),
         {:ok, ledger} <- required(opts, :ledger),
         {:ok, checkouts} <- checkouts(Keyword.get(opts, :checkouts, [])) do
      {:ok,
       %{
         fleet: fleet,
         goal: goal,
         ledger: ledger,
         graphs: Keyword.get(opts, :graphs, []),
         receipts_dirs: Keyword.get(opts, :receipts_dirs, []),
         registry: Keyword.get(opts, :registry),
         checkouts: checkouts,
         pack_dir: Keyword.get_lazy(opts, :pack_dir, &default_pack_dir/0)
       }}
    end
  end

  defp default_pack_dir,
    do: :ggen_igniter |> :code.priv_dir() |> to_string() |> Path.join("ggen/semantic-jira-pack")

  defp required(opts, key) do
    case Keyword.get(opts, key) do
      value when is_binary(value) and value != "" -> {:ok, value}
      _ -> refused(:usage, nil, "--#{key} is required")
    end
  end

  defp checkouts(values) do
    Enum.reduce_while(values, {:ok, []}, fn value, {:ok, acc} ->
      case String.split(value, "=", parts: 2) do
        [repository, dir] when repository != "" and dir != "" ->
          {:cont, {:ok, acc ++ [{repository, dir}]}}

        _ ->
          {:halt, refused(:usage, value, "--checkout must be owner/repo=DIR")}
      end
    end)
  end

  defp fence(args) do
    paths =
      [fleet: args.fleet, goal: args.goal, ledger: args.ledger, pack_dir: args.pack_dir] ++
        Enum.map(args.graphs, &{:graphs, &1}) ++
        Enum.map(args.receipts_dirs, &{:receipts_dir, &1}) ++
        Enum.map(List.wrap(args.registry), &{:registry, &1}) ++
        Enum.map(args.checkouts, fn {_repo, dir} -> {:checkout, dir} end)

    paths
    |> Enum.flat_map(fn {role, path} ->
      case Guard.forbidden_path(path) do
        nil -> []
        reason -> [refusal(:forbidden_input, Atom.to_string(role), reason)]
      end
    end)
    |> verdict()
  end

  defp queries(pack_dir) do
    case Graph.read_queries(pack_dir) do
      {:ok, queries} -> {:ok, queries}
      {:error, detail} -> refused(:input_unreadable, "pack_dir", detail)
    end
  end

  # ── observation (read every durable artifact once) ───────────────────────

  defp observe(args, queries) do
    with {:ok, fleet} <- read_fleet(args.fleet, queries),
         subjects = Subjects.build(fleet, args.checkouts),
         {:ok, goal_bytes} <- read(args.goal, "goal"),
         {:ok, goal} <- parse_ttl(goal_bytes, "goal"),
         {:ok, root} <- root(goal, queries),
         {:ok, graphs} <- read_graphs(args.graphs, subjects),
         {:ok, orders} <-
           orders(goal, graphs, queries, Subjects.ref(subjects, args.goal, "goal")),
         {:ok, receipts, receipt_dirs} <- read_receipts(args.receipts_dirs, subjects),
         {:ok, events} <- read_ledger(args.ledger),
         {:ok, registry} <- read_registry(args.registry, subjects) do
      merged = Enum.reduce(graphs, goal, fn {_ref, _sha, graph}, acc -> merge(acc, graph) end)

      {:ok,
       %{
         args: args,
         queries: queries,
         subjects: subjects,
         root: root,
         # SJ-002 AC-04: origins resolve against the GOAL graph only --
         # never `merged`, so a work graph read from another repository can
         # neither mint nor re-stamp an authority. G1: the goal index is
         # pinned against the canonical trust roots here, and again by
         # `Authority.index_from/1` wherever it is resolved.
         authority: pinned_goal_index(goal),
         checkpoints: Graph.checkpoints(merged, queries),
         capabilities: Graph.capabilities(merged, queries),
         orders: orders,
         receipts: receipts,
         events: events,
         registry: registry,
         inputs: inputs(args, subjects, goal_bytes, graphs, queries, registry, receipt_dirs)
       }}
    end
  end

  # An unreadable trust root pins nothing: every goal authority is refused
  # (fail closed), never admitted unpinned.
  defp pinned_goal_index(goal) do
    case Authority.trust_roots() do
      {:ok, pins} -> Authority.pin(Authority.index(goal), pins)
      {:error, _unavailable} -> Authority.pin(Authority.index(goal), %{})
    end
  end

  defp merge(acc, %RDF.Graph{} = graph), do: RDF.Graph.add(acc, graph)
  defp merge(acc, _json), do: acc

  defp read(path, role) do
    case File.read(path) do
      {:ok, bytes} ->
        {:ok, bytes}

      {:error, reason} ->
        refused(:input_unreadable, role, :file.format_error(reason) |> to_string())
    end
  end

  defp parse_ttl(bytes, role) do
    case Graph.parse(bytes) do
      {:ok, graph} -> {:ok, graph}
      {:error, detail} -> refused(:input_invalid, role, "not Turtle: #{detail}")
    end
  end

  defp root(goal, queries) do
    case Graph.root(goal, queries) do
      {:ok, root} -> {:ok, root}
      {:error, detail} -> refused(:goal_root, "goal", detail)
    end
  end

  defp read_fleet(path, queries) do
    with {:ok, bytes} <- read(path, "fleet") do
      if json_path?(path), do: universe(bytes), else: matrix(bytes, queries)
    end
  end

  defp universe(bytes) do
    case Jason.decode(bytes) do
      {:ok, %{"repositories" => [_ | _] = rows}} ->
        if Enum.all?(rows, &(is_map(&1) and is_binary(&1["name"] || &1["github"]))),
          do: {:ok, {:universe, rows}},
          else: refused(:input_invalid, "fleet", "every repository needs a name or github")

      _ ->
        refused(:input_invalid, "fleet", "universe JSON needs a non-empty \"repositories\" array")
    end
  end

  defp matrix(bytes, queries) do
    with {:ok, graph} <- parse_ttl(bytes, "fleet") do
      case Graph.fleet_rows(graph, queries) do
        [] -> refused(:input_invalid, "fleet", "fleet matrix has no sj:FleetMatrixRow")
        rows -> {:ok, {:matrix, rows}}
      end
    end
  end

  defp read_graphs(paths, subjects) do
    Enum.reduce_while(paths, {:ok, []}, fn path, {:ok, acc} ->
      ref = Subjects.ref(subjects, path, "graph")

      with {:ok, bytes} <- read(path, ref),
           {:ok, graph} <- parse_graph(path, bytes, ref) do
        {:cont, {:ok, acc ++ [{ref, Digest.sha256(bytes), graph}]}}
      else
        refusal -> {:halt, refusal}
      end
    end)
  end

  defp parse_graph(path, bytes, ref) do
    if json_path?(path) do
      case Jason.decode(bytes) do
        {:ok, decoded} -> {:ok, {:json, decoded}}
        {:error, _} -> refused(:input_invalid, ref, "not JSON")
      end
    else
      parse_ttl(bytes, ref)
    end
  end

  defp json_path?(path), do: path |> Path.extname() |> String.downcase() == ".json"

  defp orders(goal, graphs, queries, goal_ref) do
    orders =
      [Graph.orders(goal, queries, goal_ref)] ++
        Enum.map(graphs, fn
          {ref, _sha, %RDF.Graph{} = graph} -> Graph.orders(graph, queries, ref)
          {ref, _sha, {:json, decoded}} -> Graph.json_orders(decoded, ref)
        end)

    with {:ok, lists} <- collect_orders(orders) do
      lists |> List.flatten() |> unique_orders()
    end
  end

  defp unique_orders(all) do
    case all |> Enum.frequencies_by(& &1.id) |> Enum.filter(fn {_id, n} -> n > 1 end) do
      [] -> {:ok, Enum.sort_by(all, & &1.id)}
      dups -> refused(:duplicate_work_order, nil, "identities defined twice: #{inspect(dups)}")
    end
  end

  defp collect_orders(results) do
    Enum.reduce_while(results, {:ok, []}, fn
      {:ok, list}, {:ok, acc} -> {:cont, {:ok, [list | acc]}}
      {:error, detail}, _acc -> {:halt, refused(:input_invalid, "graphs", detail)}
      list, {:ok, acc} when is_list(list) -> {:cont, {:ok, [list | acc]}}
    end)
  end

  defp read_receipts(dirs, subjects) do
    dirs
    |> Enum.with_index()
    |> Enum.map(fn {dir, index} ->
      {dir, Subjects.ref(subjects, dir, "receipts-dir-#{index}")}
    end)
    |> Receipts.read()
    |> case do
      {:ok, entries, reports} -> {:ok, entries, reports}
      {:error, {code, ref, detail}} -> refused(code, ref, detail)
    end
  end

  defp read_ledger(path) do
    case TransitionLog.fetch(path) do
      {:ok, events} -> {:ok, events}
      {:error, reason} -> refused(:ledger_refused, "ledger", inspect(reason))
    end
  end

  defp read_registry(nil, _subjects), do: {:ok, %{"present" => false}}

  defp read_registry(path, subjects) do
    ref = Subjects.ref(subjects, path, "registry")

    with {:ok, bytes} <- read(path, ref) do
      case Jason.decode(bytes) do
        {:ok, %{"recipes" => %{} = recipes}} -> {:ok, registry(ref, bytes, recipes)}
        {:ok, %{} = recipes} -> {:ok, registry(ref, bytes, recipes)}
        _ -> refused(:input_invalid, ref, "registry export must be a JSON object")
      end
    end
  end

  defp registry(ref, bytes, recipes) do
    {valid, invalid} =
      recipes
      |> Enum.sort_by(&elem(&1, 0))
      |> Enum.split_with(&Regex.match?(@capability, elem(&1, 0)))

    %{
      "present" => true,
      "ref" => ref,
      "sha256" => Digest.sha256(bytes),
      "entries" =>
        Enum.map(valid, fn {id, recipe} ->
          %{
            "capability_id" => id,
            "provider" => provider(id),
            "sha256" => Digest.sha256(canonical_json(recipe))
          }
        end),
      "refused" =>
        Enum.map(invalid, fn {id, _recipe} ->
          %{"capability_id" => id, "reason" => "capability_id_noncanonical"}
        end)
    }
  end

  defp provider(id), do: id |> String.split(":", parts: 2) |> hd()

  defp inputs(args, subjects, goal_bytes, graphs, queries, registry, receipt_dirs) do
    law =
      queries
      |> Enum.sort()
      |> Enum.map(fn {name, text} ->
        file = if name == "root", do: "prose/root.rq", else: "bootstrap/#{name}.rq"

        %{
          "role" => "law",
          "ref" => "semantic-jira-pack:" <> file,
          "sha256" => Digest.sha256(text)
        }
      end)

    fleet_bytes = File.read!(args.fleet)

    [
      %{
        "role" => "goal",
        "ref" => Subjects.ref(subjects, args.goal, "goal"),
        "sha256" => Digest.sha256(goal_bytes)
      },
      %{
        "role" => "fleet",
        "ref" => Subjects.ref(subjects, args.fleet, "fleet"),
        "sha256" => Digest.sha256(fleet_bytes)
      }
    ] ++
      Enum.map(graphs, fn {ref, sha, _graph} ->
        %{"role" => "graph", "ref" => ref, "sha256" => sha}
      end) ++
      if(registry["present"],
        do: [%{"role" => "registry", "ref" => registry["ref"], "sha256" => registry["sha256"]}],
        else: []
      ) ++ receipt_dirs ++ law
  end

  # ── derivation ──────────────────────────────────────────────────────────

  defp derive(world) do
    closure = closure(world.checkpoints, world.root)
    judged = Enum.map(world.orders, &judge(&1, world, closure))

    kernel_orders = Enum.map(judged, & &1.kernel)
    {applied, ledger_report} = applicable_events(world.events, judged, world.subjects)

    evidence =
      for order <- judged, order.receipt, into: %{} do
        {order.id,
         %{
           "standing" => Receipts.kernel_standing(order.receipt["standing"]),
           "receipt_digest" => order.receipt["sha256"]
         }}
      end

    {projected, _logged} = SemanticJira.project(kernel_orders, applied)

    frontier =
      SemanticJira.frontier_from_events(kernel_orders, applied, evidence,
        authority: world.authority
      )

    logged_ids = applied |> Enum.map(& &1["identity"]) |> MapSet.new()

    orders =
      judged
      |> Enum.zip(projected)
      |> Map.new(fn {order, projection} ->
        {order.id, order_json(order, projection, frontier, logged_ids)}
      end)

    %{
      world: world,
      closure: closure,
      orders: orders,
      judged: judged,
      frontier: frontier,
      ledger: Map.merge(ledger_report, ledger_summary(world, applied))
    }
  end

  # Root plus every GoalCheckpoint reaching it over sj:checkpointOf.
  defp closure(checkpoints, root) do
    edges =
      for {iri, fields} <- checkpoints,
          parent <- Map.get(fields, "checkpoint_of", []),
          do: {iri, parent}

    grow(MapSet.new([root]), edges)
  end

  defp grow(set, edges) do
    next =
      Enum.reduce(edges, set, fn {child, parent}, acc ->
        if MapSet.member?(acc, parent), do: MapSet.put(acc, child), else: acc
      end)

    if MapSet.size(next) == MapSet.size(set), do: set, else: grow(next, edges)
  end

  defp judge(order, world, closure) do
    subject = Subjects.for_repository(world.subjects, order.kernel["repository"])
    {scope, cross} = covered_scope(order.kernel["path_scope"] || [])
    {covered_status, current} = current_covered(subject, scope)
    linked = link(order, world.receipts, subject, scope, {covered_status, current})
    best = Receipts.best(linked.current)
    standing = if best, do: best.standing, else: "UNKNOWN"

    kernel = Map.put(order.kernel, "standing", Receipts.kernel_standing(standing))

    Map.merge(order, %{
      kernel: kernel,
      subject: subject,
      scope: scope,
      cross_scope: cross,
      covered_commit: current,
      covered_status: covered_status,
      receipt: best && receipt_json(best),
      receipt_standing: standing,
      current_receipts: linked.current,
      invalidated: linked.invalidated,
      unlinked: linked.unlinked,
      critical_path: critical_path?(order, closure),
      admission: SemanticJira.admit_work_order(kernel)
    })
  end

  defp critical_path?(order, closure) do
    under? = Enum.any?(Map.get(order.fields, "checkpoint_of", []), &MapSet.member?(closure, &1))
    under? and @successor not in Map.get(order.fields, "boundary_class", [])
  end

  # Path scope entries that name this repository's tree, minus every entry
  # with a `receipts` path component (`receipts/v26.9.23/V23-B.json`,
  # `docs/sjira/v26.9.23/receipts/`): a receipt is out-of-subject evidence and
  # cannot cover itself. Entries carrying another repository's alias
  # (`xaas:docs/...`) are reported, not checked against this history.
  defp covered_scope(path_scope) do
    {cross, local} = Enum.split_with(path_scope, &Regex.match?(@cross_repository, &1))
    local = Enum.reject(local, &("receipts" in Path.split(&1)))
    scope = if local == [], do: [".", ":(exclude)receipts"], else: Enum.sort(local)
    {scope, Enum.sort(cross)}
  end

  # What HEAD shows for the covered scope: `{status, covered_commit | nil}`.
  defp current_covered(nil, _scope), do: {"subject_unresolved", nil}

  defp current_covered(subject, scope) do
    case Git.covered_commit(subject.toplevel, subject.head_sha, scope) do
      {:ok, nil} -> {"none_in_scope", nil}
      {:ok, sha} -> {"observed", sha}
      :error -> {"unreadable", nil}
    end
  end

  # Whether a revision whose covered commit is `at` (a receipt's subject or
  # a ledger event's candidate) still covers the order at HEAD. `:current`
  # only for an observed, equal covered commit; every other outcome names
  # why it is not current.
  defp coverage({"observed", current}, {:ok, current}), do: :current
  defp coverage({"observed", _current}, {:ok, _other}), do: {:stale, "subject_advanced"}
  defp coverage({"none_in_scope", nil}, {:ok, _at}), do: {:stale, "scope_never_committed"}

  defp coverage({"unreadable", nil}, {:ok, _at}),
    do: {:stale, "current_covered_commit_unreadable"}

  defp coverage({"subject_unresolved", nil}, {:ok, _at}), do: {:stale, "subject_unresolved"}

  defp coverage(_current, :error), do: {:unreadable, "covered_commit_unreadable"}

  defp link(order, receipts, subject, scope, current) do
    local = order.iri && Graph.local_name(order.iri)

    receipts
    |> Enum.filter(&Receipts.names_order?(&1, order.id, local))
    |> Enum.reduce(%{current: [], invalidated: [], unlinked: []}, fn entry, acc ->
      case classify(entry, order, subject, scope, current) do
        {:current, item} ->
          %{acc | current: acc.current ++ [item]}

        {:invalidated, item} ->
          %{acc | invalidated: acc.invalidated ++ [item]}

        {:unlinked, reason} ->
          %{acc | unlinked: acc.unlinked ++ [%{"ref" => entry.ref, "reason" => reason}]}
      end
    end)
  end

  defp classify(%{errors: [_ | _] = errors}, _order, _subject, _scope, _current),
    do: {:unlinked, "refused: " <> Enum.join(errors, "; ")}

  defp classify(entry, order, subject, scope, current) do
    sha = Receipts.identity(entry, "subject_sha")

    cond do
      not match?({:ok, _, _}, order.tuple) ->
        {:unlinked, "tuple_" <> tuple_status(order.tuple)}

      Receipts.identity(entry, "tuple_digest") != elem(order.tuple, 2) ->
        {:unlinked, "tuple_digest_mismatch"}

      subject == nil ->
        {:unlinked, "subject_unresolved"}

      Git.commit(subject.toplevel, sha) == :error ->
        {:unlinked, "subject_sha_unknown (R_missing_identity)"}

      true ->
        currency(entry, subject, scope, current)
    end
  end

  defp currency(entry, subject, scope, {_status, current} = head) do
    sha = Receipts.identity(entry, "subject_sha")
    at = Git.covered_commit(subject.toplevel, sha, scope)

    case coverage(head, at) do
      :current ->
        {:current,
         %{
           ref: entry.ref,
           sha256: entry.sha256,
           standing: Receipts.standing(entry),
           subject_sha: sha,
           covered_commit: current
         }}

      {:stale, reason} ->
        {:ok, at_receipt} = at

        {:invalidated,
         %{
           "ref" => entry.ref,
           "sha256" => entry.sha256,
           "reason" => reason,
           "receipt_subject_sha" => sha,
           "receipt_covered_commit" => at_receipt,
           "current_covered_commit" => current
         }}

      {:unreadable, reason} ->
        {:unlinked, reason}
    end
  end

  defp tuple_status({:ok, _tuple, _digest}), do: "complete"
  defp tuple_status({kind, field}), do: "#{kind}:#{field}"

  defp receipt_json(item) do
    %{
      "ref" => item.ref,
      "sha256" => item.sha256,
      "standing" => item.standing,
      "subject_sha" => item.subject_sha,
      "covered_commit" => item.covered_commit
    }
  end

  # ── ledger ──────────────────────────────────────────────────────────────

  defp applicable_events(events, judged, subjects) do
    by_id = Map.new(judged, &{&1.id, &1})

    {applied, rejected} =
      Enum.reduce(events, {[], []}, fn event, {applied, rejected} ->
        case event_verdict(event, by_id[event["identity"]], subjects) do
          :apply -> {[event | applied], rejected}
          {:reject, reason} -> {applied, [event_report(event, reason) | rejected]}
        end
      end)

    {Enum.reverse(applied), %{"inapplicable" => Enum.reverse(rejected)}}
  end

  defp event_verdict(_event, nil, _subjects), do: {:reject, "unknown_work_order"}

  defp event_verdict(event, order, subjects) do
    cond do
      not match?({:ok, _}, order.admission) ->
        {:reject, "work_order_inadmissible"}

      event["definition_digest"] != elem(order.admission, 1)["definition_digest"] ->
        {:reject, "definition_digest_mismatch"}

      event["to"] == "UNKNOWN" ->
        :apply

      reason = receipt_binding(event, order) ->
        {:reject, reason}

      event["to"] == "ALIVE" ->
        order |> stale_candidate(subjects) |> candidate_verdict()

      true ->
        :apply
    end
  end

  defp candidate_verdict(nil), do: :apply
  defp candidate_verdict(reason), do: {:reject, reason}

  # nil when the event's `receipt_digest` is the sha256 of a CURRENT linked
  # receipt of the order and that receipt's kernel standing is the event's
  # `to`; else the typed reason the event confers nothing (PR-006, ARD
  # sections 7 and 28: a ledger literal is not a receipt).
  defp receipt_binding(event, order) do
    digest = event["receipt_digest"]

    case Enum.find(order.current_receipts, &(&1.sha256 == digest)) do
      %{standing: standing} ->
        if Receipts.kernel_standing(standing) == event["to"],
          do: nil,
          else: "receipt_standing_mismatch"

      nil ->
        if is_binary(digest) and Enum.any?(order.invalidated, &(&1["sha256"] == digest)),
          do: "receipt_not_current",
          else: "receipt_digest_unresolved"
    end
  end

  # nil when the order's candidate SHA (if any) still covers its scope at
  # HEAD, else the typed reason (`candidate_` + the coverage reason).
  defp stale_candidate(%{kernel: %{"candidate_sha" => sha}, subject: subject} = order, _subjects)
       when is_binary(sha) and not is_nil(subject) do
    head = {order.covered_status, order.covered_commit}

    case coverage(head, Git.covered_commit(subject.toplevel, sha, order.scope)) do
      :current -> nil
      {_stale_or_unreadable, reason} -> "candidate_" <> reason
    end
  end

  defp stale_candidate(_order, _subjects), do: nil

  defp event_report(event, reason) do
    %{
      "seq" => event["seq"],
      "identity" => event["identity"],
      "to" => event["to"],
      "event_digest" => event["event_digest"],
      "reason" => reason
    }
  end

  defp ledger_summary(world, applied) do
    %{
      "ref" => Subjects.ref(world.subjects, world.args.ledger, "ledger"),
      "present" => File.exists?(world.args.ledger),
      "events" => length(world.events),
      "applied" => length(applied),
      "tail" => Reconciler.tail_digest(world.events)
    }
  end

  # ── state ───────────────────────────────────────────────────────────────

  defp order_json(order, projection, frontier, logged_ids) do
    {frontier_class, reason} = frontier_class(order, frontier)

    %{
      "iri" => order.iri,
      "source" => order.source,
      "checkpoint" => Map.get(order.fields, "checkpoint_of", []),
      "origin_authority" => order.kernel["origin_authority"],
      "critical_path" => order.critical_path,
      "successor" => @successor in Map.get(order.fields, "boundary_class", []),
      "repository" => order.kernel["repository"],
      "base_sha" => order.kernel["base_sha"],
      "subject" => order.kernel["subject"],
      "subject_head" => order.subject && order.subject.head_sha,
      "path_scope" => order.kernel["path_scope"] || [],
      "covered_scope" => order.scope,
      "cross_repository_scope" => order.cross_scope,
      "covered_commit" => order.covered_commit,
      "covered_commit_status" => order.covered_status,
      "capability" => Map.get(order.fields, "capability", []),
      "tuple" => tuple_status(order.tuple),
      "tuple_digest" => tuple_digest(order.tuple),
      "definition_digest" => definition_digest(order.admission),
      "dependencies" => order.kernel["dependencies"] || [],
      "standing" => projection["standing"],
      "standing_source" => standing_source(order, logged_ids),
      "receipt" => order.receipt,
      "invalidated" => order.invalidated,
      "unlinked" => order.unlinked,
      "frontier" => frontier_class,
      "frontier_reason" => reason
    }
  end

  defp tuple_digest({:ok, _tuple, digest}), do: digest
  defp tuple_digest(_incomplete), do: nil

  defp definition_digest({:ok, admitted}), do: admitted["definition_digest"]
  defp definition_digest(_refused), do: nil

  defp standing_source(order, logged_ids) do
    cond do
      MapSet.member?(logged_ids, order.id) -> "ledger"
      order.receipt -> "receipt"
      true -> "none"
    end
  end

  defp frontier_class(%{admission: {:error, reason}}, _frontier),
    do: {"blocked", "inadmissible: " <> inspect(reason)}

  defp frontier_class(order, frontier) do
    cond do
      Enum.any?(frontier.eligible, &(&1["identity"] == order.id)) ->
        {"eligible", nil}

      blocked = Enum.find(frontier.blocked, &(&1["identity"] == order.id)) ->
        settled_or_blocked(blocked["reason"])

      true ->
        {"blocked", "not_selected"}
    end
  end

  defp settled_or_blocked("standing=" <> _ = reason), do: {"settled", reason}
  defp settled_or_blocked(reason), do: {"blocked", reason}

  defp finish(derived) do
    state = state(derived)

    case Guard.absolute_paths(state) do
      [] ->
        json = canonical_json(state)
        {:ok, %{state: state, json: json, digest: Digest.sha256(json)}}

      pointers ->
        refused(:absolute_path_in_state, nil, "host paths at #{Enum.join(pointers, ", ")}")
    end
  end

  defp state(derived) do
    world = derived.world

    %{
      "schema" => @schema,
      "checkpoint" => checkpoint(world, derived),
      "subjects" => Enum.map(world.subjects, &Subjects.to_json/1),
      "capabilities" => capabilities(world, derived.judged),
      "authority" => authority(world, derived.judged),
      "orders" => derived.orders,
      "frontier" => frontier_json(derived.frontier),
      "ledger" => derived.ledger,
      "receipts" => Enum.map(world.receipts, &receipt_summary(&1, derived)),
      "registry" => world.registry,
      "inputs" => world.inputs,
      "exceptions" => exceptions(world, derived)
    }
  end

  defp frontier_json(frontier) do
    %{
      "eligible" => Enum.sort_by(frontier.eligible, & &1["identity"]),
      "blocked" => Enum.sort_by(frontier.blocked, &{&1["identity"] || "", &1["reason"]})
    }
  end

  defp checkpoint(world, derived) do
    root_fields = Map.get(world.checkpoints, world.root, %{})
    root_id = single(root_fields["identity"]) || world.root
    root_subject = Subjects.for_repository(world.subjects, single(root_fields["repository"]))

    gates =
      world.checkpoints
      |> Enum.filter(fn {_iri, fields} -> world.root in Map.get(fields, "checkpoint_of", []) end)
      |> Enum.map(fn {iri, fields} ->
        gate(iri, fields, root_id, root_subject, world, derived)
      end)
      |> Enum.sort_by(&natural(&1["id"]))

    successors =
      world.checkpoints
      |> Enum.filter(fn {_iri, fields} -> world.root in Map.get(fields, "successor_of", []) end)
      |> Enum.map(fn {iri, fields} ->
        %{
          "id" => single(fields["identity"]) || iri,
          "iri" => iri,
          "orders" => orders_of(iri, derived)
        }
      end)
      |> Enum.sort_by(& &1["id"])

    %{
      "root" => root_json(world.root, root_id, root_fields, root_subject, world),
      "gates" => gates,
      "successors" => successors
    }
  end

  defp root_json(iri, id, fields, subject, world) do
    %{
      "id" => id,
      "iri" => iri,
      "repository" => single(fields["repository"]),
      "base_sha" => single(fields["base_sha"]),
      "source_sha256" => single(fields["source_sha256"]),
      "authority_ceiling" => single(fields["authority_ceiling"]),
      "evidence_horizon" => single(fields["evidence_horizon"]),
      "replay_identity" => single(fields["replay_identity"]),
      "court_command" => Map.get(fields, "court_command", []),
      "stop_query_sha256" => fields |> Map.get("stop_query", []) |> Enum.map(&Digest.sha256/1),
      "successor_of" => Map.get(fields, "successor_of", []),
      "successor_checkpoint" => Map.get(fields, "successor_checkpoint", []),
      "receipt" => node_receipt(world.receipts, id, subject)
    }
  end

  defp gate(iri, fields, root_id, root_subject, world, derived) do
    id = single(fields["identity"]) || iri
    receipt = node_receipt(world.receipts, "#{root_id}/#{id}", root_subject)

    %{
      "id" => id,
      "iri" => iri,
      "boundary_class" =>
        fields |> Map.get("boundary_class", []) |> Enum.map(&Graph.local_name/1),
      "court_command" => Map.get(fields, "court_command", []),
      "exclusions" => Map.get(fields, "exclusions", []),
      "orders" => orders_of(iri, derived),
      "receipt" => receipt,
      "standing" => if(receipt && receipt["at_head"], do: receipt["standing"], else: "UNKNOWN")
    }
  end

  defp orders_of(iri, derived) do
    derived.judged
    |> Enum.filter(&(iri in Map.get(&1.fields, "checkpoint_of", [])))
    |> Enum.map(& &1.id)
    |> Enum.sort()
  end

  # A gate/root receipt (identity.subject "ROOT/GATE" or "ROOT") confers its
  # standing only at the exact HEAD of the root repository it was made at.
  defp node_receipt(receipts, subject_name, subject) do
    receipts
    |> Enum.filter(&(Receipts.names_subject?(&1, subject_name) and &1.errors == []))
    |> Enum.map(fn entry ->
      %{
        ref: entry.ref,
        standing: Receipts.standing(entry),
        subject_sha: Receipts.identity(entry, "subject_sha"),
        sha256: entry.sha256
      }
    end)
    |> Receipts.best()
    |> case do
      nil ->
        nil

      best ->
        %{
          "ref" => best.ref,
          "sha256" => best.sha256,
          "standing" => best.standing,
          "subject_sha" => best.subject_sha,
          "at_head" => subject != nil and best.subject_sha == subject.head_sha
        }
    end
  end

  defp capabilities(world, judged) do
    graph_ids = world.capabilities |> Map.values() |> List.flatten()
    registry_ids = world.registry |> Map.get("entries", []) |> Enum.map(& &1["capability_id"])

    required =
      for order <- judged, id <- Map.get(order.fields, "capability", []), reduce: %{} do
        acc -> Map.update(acc, id, [order.id], &[order.id | &1])
      end

    (graph_ids ++ registry_ids ++ Map.keys(required))
    |> Enum.uniq()
    |> Enum.sort()
    |> Enum.map(fn id ->
      %{
        "id" => id,
        "provider" => provider(id),
        "canonical" => Regex.match?(@capability, id),
        "declared_in_graph" => id in graph_ids,
        "registered" => id in registry_ids,
        "required_by" => required |> Map.get(id, []) |> Enum.sort()
      }
    end)
  end

  defp authority(world, judged) do
    root_fields = Map.get(world.checkpoints, world.root, %{})

    %{
      "root" => %{
        "ceiling" => single(root_fields["authority_ceiling"]),
        "exclusions" => Map.get(root_fields, "exclusions", [])
      },
      "orders" =>
        Map.new(judged, fn order ->
          {order.id,
           %{
             "ceiling" => single(order.fields["authority_ceiling"]),
             "requirement" => order.kernel["authority_requirement"],
             "exclusions" => Map.get(order.fields, "exclusions", [])
           }}
        end)
    }
  end

  defp receipt_summary(entry, derived) do
    %{
      "ref" => entry.ref,
      "sha256" => entry.sha256,
      "verdict" => if(entry.errors == [], do: "admitted", else: "refused"),
      "errors" => entry.errors,
      "subject" => Receipts.identity(entry, "subject"),
      "subject_sha" => Receipts.identity(entry, "subject_sha"),
      "standing" => Receipts.standing(entry),
      "linked_order" => linked_order(entry.ref, derived.judged)
    }
  end

  defp linked_order(ref, judged) do
    Enum.find_value(judged, fn order ->
      order.receipt && order.receipt["ref"] == ref && order.id
    end)
  end

  defp exceptions(world, derived) do
    orders = Enum.sort_by(derived.orders, &elem(&1, 0))

    %{
      "blocked" =>
        order_exceptions(orders, "BLOCKED") ++ frontier_blocks(orders) ++ fleet(world, "Blocked"),
      "unsupported" => order_exceptions(orders, "UNSUPPORTED") ++ fleet(world, "Unsupported"),
      "refused" =>
        order_exceptions(orders, "REFUSED") ++
          fleet(world, "Refused") ++
          refused_receipts(world) ++
          refused_subjects(world) ++
          Enum.map(derived.ledger["inapplicable"], &Map.put(&1, "kind", "ledger_event")) ++
          Enum.map(Map.get(world.registry, "refused", []), &Map.put(&1, "kind", "registry_entry"))
    }
  end

  defp order_exceptions(orders, prefix) do
    for {id, order} <- orders, String.starts_with?(order["standing"] || "", prefix) do
      %{"kind" => "order", "id" => id, "standing" => order["standing"]}
    end
  end

  defp frontier_blocks(orders) do
    for {id, %{"frontier" => "blocked"} = order} <- orders do
      %{"kind" => "frontier", "id" => id, "reason" => order["frontier_reason"]}
    end
  end

  defp fleet(world, class) do
    for subject <- world.subjects, subject.class == class do
      %{"kind" => "fleet", "id" => subject.repository, "class" => class}
    end
  end

  defp refused_receipts(world) do
    for entry <- world.receipts, entry.errors != [] do
      %{"kind" => "receipt", "id" => entry.ref, "reason" => Enum.join(entry.errors, "; ")}
    end
  end

  defp refused_subjects(world) do
    for subject <- world.subjects, String.starts_with?(subject.status, "refused") do
      %{"kind" => "subject", "id" => subject.repository, "reason" => subject.status}
    end
  end

  # ── helpers ─────────────────────────────────────────────────────────────

  defp single([value]), do: value
  defp single(_), do: nil

  defp natural(id) do
    ~r/(\d+)/
    |> Regex.split(to_string(id), include_captures: true, trim: true)
    |> Enum.map(fn part ->
      case Integer.parse(part) do
        {n, ""} -> {0, n, ""}
        _ -> {1, 0, part}
      end
    end)
  end

  defp refusal(code, subject, detail), do: %{code: code, subject: subject, detail: detail}
  defp refused(code, subject, detail), do: {:refused, [refusal(code, subject, detail)]}

  defp verdict([]), do: :ok
  defp verdict(refusals), do: {:refused, refusals}
end
