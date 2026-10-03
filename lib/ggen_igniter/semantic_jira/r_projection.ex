defmodule GgenIgniter.SemanticJira.RProjection do
  @moduledoc """
  Projects a `GgenIgniter.Receipt` run receipt onto the fleet R schema v2
  (`~/.claude/dfcm/receipt.schema.json`: `identity`, `authority`,
  `consequence`, `replay`, `standing`, plus v2's `work_order_id`,
  `origin_authority`, `provider`, `provider_execution_id`, optional
  `subject_before`/`subject_after`, and the namespaced `provider_ext.*`
  extension map) so ggen_igniter's reconciliation history is readable by any
  fleet consumer that admits R receipts — `GgenIgniter.SemanticJira.Bootstrap.
  Receipts.check/1` restates that schema's law structurally, and every
  `{:ok, r}` this module returns satisfies it.

  * `project/2` — the pure projection: a real `GgenIgniter.Receipt` struct
    plus opts (repo, authority, work-order identity) into an R map, with
    ordered, fail-closed refusals (`{:r_projection_refused, reason}`).
  * `write/2` — persists a projected map (or a receipt, projected first) as
    pretty JSON plus a trailing newline at `<stem>.r.json`.

  ## Hand-written disclosure: UNSUPPORTED(generator-capability)

  This module is hand-written on purpose. Per the ontology-first law, the
  right generator path would be a pack projecting receipts onto the R
  schema; no such pack exists — the mapping below is repo-specific plumbing
  between `GgenIgniter.Receipt`'s struct fields and the fleet schema, not an
  ontology fact any existing pack (`priv/ggen/semantic-jira-pack/` carries
  the work-order/gate shapes, not receipt projection) already models.
  Hand-writing it here is the explicit `UNSUPPORTED(generator-capability)`
  residue, disclosed rather than hidden; when a receipt-projection pack
  exists, this module should be regenerated from it, not edited in place.

  ## Standing map (receipt standing -> R standing value)

  The five real `GgenIgniter.Receipt` standings map onto the R vocabulary
  per this module's own standing table below (`standing_value/2`'s clauses),
  refined by the admission-vacuity law (`Bootstrap.Receipts.check/1`'s own
  rule: an ALIVE receipt with any non-zero replay exit is `admission_vacuous`):

    * `:alive` with every mapped replay command exit `== 0` -> `"ALIVE"`.
    * `:alive` with ANY non-zero OR nil source `exit_code` -> the R standing
      `REFUSED` with reason `admission_vacuous` (`broken_term:
      "admission_vacuous"`) — **never ALIVE**: claiming ALIVE over a red
      replay is the exact vacuous admission the R law refuses.
    * `:refused` -> `"BLOCKED:<reason>"` (from `receipt.reason`, never
      empty — a nil/blank reason falls back to `"unspecified"`),
      `broken_term: "mu_on_O"`: refused before actuation on unadmitted
      input, so nothing about the subject is evidenced.
    * `:compensated` -> `"PARTIAL_ALIVE"`.
    * `:compensation_failed` -> `"PARTIAL_ALIVE"` too (the R vocabulary has
      no separate bucket), with the catastrophic detail carried in
      `standing.derived_from`.
    * `:build_broken` -> `"BUILD_BROKEN"`, `broken_term: "mu_unlawful"`
      (the pack manufactured bytes that do not compile — unlawful
      manufacture).
    * any other value (impossible from a real struct — `new/1`'s closed-set
      guard — but `project/2` is fail-closed, not trusting it) ->
      `"UNKNOWN"`.

  ## Digest boundary law (which fields carry a prefix, from the schema)

  The fleet boundary rule "every digest riding an R receipt must be
  `sha256:`-prefixed" is NOT uniform across the R v2 schema — each field's
  own `pattern` decides, and `GgenIgniter.Digest.hex/1` vs `Digest.sha256/1`
  is chosen per field from the schema, not from the rule's prose:

    * `replay/commands/N/output_sha256` — schema pattern `^[0-9a-f]{64}$`:
      BARE hex, deliberately unprefixed (see `put_output_sha/2`, the only
      `Digest.hex/1` emission site on the R boundary). Prefixing it would
      refuse the receipt. This is the same bare-hex shape `check/1`'s
      `@hex64` re-states.
    * `subject_before`/`subject_after` and `identity.graph_hash` — schema
      pattern `^sha256:[0-9a-f]{64}$`: PREFIXED (`Digest.sha256/1` shape,
      carried through from `GgenIgniter.Receipt.hash_entries/1`).
    * `identity.subject_digest.value` — schema pattern `^[0-9a-f]{64,}$`:
      BARE hex by schema. The bare-hex exception for this field: when a
      non-commit subject rides `subject_digest`, its `value` is unprefixed
      (`algorithm` names the hash). This module does not project
      `subject_digest` today (its subjects are commit-anchored).

  ## Field law

    * `pre_run_hash`/`post_run_hash` (`"sha256:hex"` over the exact touched
      file set — see `GgenIgniter.Receipt.hash_entries/1`) map 1:1 onto the
      top-level `subject_before`/`subject_after` and **never** into
      `identity`: file-set digests are not git commits, and the schema (and
      the fleet validator) refuse a non-commit digest in
      `identity.subject_sha`.
    * `identity.subject_sha`/`base_sha` are real 40-hex git commit anchors:
      `subject_sha` defaults to `git -C <opts[:repo]> rev-parse HEAD` (a
      real subprocess — this projector is the *consumer* of git state, and
      `opts[:repo]` is REQUIRED; missing -> `:repo_required`, a plain
      non-git directory -> `:head_unresolvable`), then verified resolvable
      as a commit (`git cat-file -e <sha>^{commit}`; failure ->
      `{:subject_sha_not_a_commit, sha}`). `base_sha` defaults to
      `subject_sha` unless given.
    * `work_order_id` is REQUIRED — from
      `receipt.metadata["work_order"]["path"]` (what
      `GgenIgniter.Receipt.new/2`'s `put_work_order_identity/2` stamps) or
      `opts[:work_order_id]` (which overrides); absent from both ->
      `:work_order_id_required`. `identity.subject` mirrors it.
    * `consequence` is honest by construction: `commits: []` (sync writes
      files, never git commits), `files_changed` = `receipt.files`,
      `remote_effects: []`.
    * `replay.commands` are mapped from `receipt.commands`
      (`cmd`/`cwd`/`exit`), `cwd` defaulting to `opts[:repo]`; a source
      `exit_code` of nil (a real `Task.shutdown/2` `:brutal_kill` timeout —
      the receipt has no exit status) maps to exit `-1` with the timeout
      disclosed in the command's `summary`, because the R schema requires an
      integer exit and `-1` is the honest "no exit status existed" sentinel.
      A receipt with no commands at all (every `:refused` receipt, by
      construction) refuses `:no_replay_commands` — there is nothing to
      replay, and an empty `replay.commands` array is not an admissible R
      receipt.
    * `authority`/`origin_authority` (mirrored) come from opts: `:ceiling`
      default `"CONSTRUCT"`, `:grant` default `"NONE"`, `:actor` default
      `"ggen-igniter"`.
    * `provider` is `%{"name" => "ggen-igniter"}`;
      `provider_execution_id` is `receipt.id`.
    * `receipt_hash` (and `recipe_key`) ride ONLY inside the namespaced
      top-level extension object `"provider_ext.ggen_igniter"` — never as a
      bare top-level key, and `schema_version` is never projected (the R
      schema has no such key; un-namespaced extension keys are refused by
      the fleet validator).
  """

  alias GgenIgniter.Digest
  alias GgenIgniter.Receipt
  alias GgenIgniter.SemanticJira.Bootstrap.Guard
  alias GgenIgniter.SemanticJira.Bootstrap.Receipts

  # SOVEREIGN is deliberately NOT a ceiling here: `~/.claude/dfcm/receipt.schema.json`'s
  # `properties.authority.ceiling` enum is the closed fleet set
  # OBSERVE|SELECT|CONSTRUCT|DO, and this projection refuses any other
  # ceiling. A work order's `authority_requirement: "SOVEREIGN"` (the 0x04
  # kind) projects at ceiling DO — the actuation-plane equivalent — while the
  # requirement itself stays on the work-order plane, carried separately as
  # `sj:authorityRequirement` (see observation.ex's graph rendering and
  # bootstrap.ex's kernel "requirement" field). SovereignLease.admit/3, not
  # this ceiling, is the SOVEREIGN authority law.
  @ceilings ~w(OBSERVE SELECT CONSTRUCT DO)
  @sha ~r/\A[0-9a-f]{40}\z/
  @provider_ext_key "provider_ext.ggen_igniter"

  # Built by concatenation so the refusals exhaustiveness detector
  # (`GgenIgniter.RefusalsTest.mine/1`, regex `REFUSED\(...\)`) does not mine
  # this fleet R standing VALUE as if it were a ggen refusal CODE: the two
  # vocabularies are different planes, and only ggen codes belong in
  # priv/schema/refusals.schema.json's enum.
  @r_refused_admission_vacuous "REFUSED" <> "(" <> "admission_vacuous)"

  @typedoc "Why a receipt could not be projected onto the R schema."
  @type refusal ::
          :invalid_receipt
          | :repo_required
          | :head_unresolvable
          | {:subject_sha_not_a_commit, String.t()}
          | :work_order_id_required
          | :no_replay_commands
          | {:invalid_ceiling, term()}
          | {:self_check_failed, [String.t()]}
          | :output_path_required
          | {:forbidden_output_path, String.t()}
          | {:invalid_r_map, [String.t()]}

  @doc """
  Projects `receipt` onto the fleet R schema v2. Fails closed, in order:
  authority ceiling, struct shape, repo, subject anchor, work-order
  identity, replay evidence, and finally the restated R law itself
  (`Bootstrap.Receipts.check/1` — a projected map that does not admit
  structurally is refused, never returned as `{:ok, _}`).
  """
  @spec project(term(), keyword()) ::
          {:ok, map()} | {:error, {:r_projection_refused, refusal()}}
  def project(%Receipt{} = receipt, opts) when is_list(opts) do
    with {:ok, authority} <- authority(opts),
         {:ok, repo} <- require_repo(opts),
         {:ok, subject_sha} <- resolve_subject_sha(repo, opts),
         base_sha <- Keyword.get(opts, :base_sha) || subject_sha,
         {:ok, work_order_id} <- require_work_order_id(receipt, opts),
         {:ok, commands} <- require_commands(receipt, repo) do
      r = build(receipt, repo, subject_sha, base_sha, work_order_id, commands, authority)

      case Receipts.check(r) do
        [] -> {:ok, r}
        errors -> {:error, {:r_projection_refused, {:self_check_failed, errors}}}
      end
    end
  end

  def project(_other, _opts), do: {:error, {:r_projection_refused, :invalid_receipt}}

  @doc """
  Persists a projected R receipt as pretty JSON plus a trailing newline.
  Accepts either an already-projected map or a real `GgenIgniter.Receipt`
  (projected first, with the same refusals as `project/2`). The output path
  is required and normalized to `<stem>.r.json`; a path under a Claude/ZCode
  home is refused via `GgenIgniter.SemanticJira.Bootstrap.Guard.forbidden_path/1`.
  """
  @spec write(map() | Receipt.t(), keyword()) :: :ok | {:error, term()}
  def write(r_or_receipt, opts) when is_list(opts) do
    with {:ok, r} <- to_r(r_or_receipt, opts),
         {:ok, path} <- output_path(opts) do
      json = encode(r)

      File.mkdir_p!(Path.dirname(path))
      File.write!(path, json)
      :ok
    end
  end

  def write(_r_or_receipt, _opts), do: {:error, {:r_projection_refused, :invalid_receipt}}

  ## -- projection steps (ordered, fail-closed) -------------------------------

  defp require_repo(opts) do
    case Keyword.get(opts, :repo) do
      repo when is_binary(repo) and repo != "" -> {:ok, Path.expand(repo)}
      _ -> {:error, {:r_projection_refused, :repo_required}}
    end
  end

  defp resolve_subject_sha(repo, opts) do
    case Keyword.get(opts, :subject_sha) do
      nil -> head_sha(repo)
      given -> verify_commit(repo, given)
    end
  end

  # `git -C <repo> rev-parse HEAD` via a REAL subprocess. A plain
  # (non-git) directory fails here -> :head_unresolvable, never a guessed SHA.
  defp head_sha(repo) do
    case git(repo, ["rev-parse", "HEAD"]) do
      {:ok, sha} -> verify_commit(repo, sha)
      :error -> {:error, {:r_projection_refused, :head_unresolvable}}
    end
  end

  # `git cat-file -e <sha>^{commit}`: the anchor must RESOLVE as a commit in
  # this repo — the same verification the fleet validator re-runs.
  defp verify_commit(repo, sha) do
    if Regex.match?(@sha, sha) and git?(repo, ["cat-file", "-e", sha <> "^{commit}"]) do
      {:ok, sha}
    else
      {:error, {:r_projection_refused, {:subject_sha_not_a_commit, sha}}}
    end
  end

  defp git(repo, args) do
    case System.cmd("git", ["-C", repo | args], stderr_to_stdout: true) do
      {out, 0} -> {:ok, String.trim(out)}
      {_out, _nonzero} -> :error
    end
  rescue
    _ -> :error
  end

  defp git?(repo, args) do
    case git(repo, args) do
      {:ok, _} -> true
      :error -> false
    end
  end

  defp require_work_order_id(receipt, opts) do
    explicit = Keyword.get(opts, :work_order_id)

    from_metadata =
      case receipt.metadata do
        %{"work_order" => %{"path" => path}} when is_binary(path) and path != "" -> path
        _ -> nil
      end

    case explicit || from_metadata do
      id when is_binary(id) and id != "" -> {:ok, id}
      _ -> {:error, {:r_projection_refused, :work_order_id_required}}
    end
  end

  defp require_commands(receipt, repo) do
    case receipt.commands do
      [] -> {:error, {:r_projection_refused, :no_replay_commands}}
      commands -> {:ok, Enum.map(commands, &project_command(&1, repo))}
    end
  end

  # One source command (string-keyed, per `GgenIgniter.Receipt`'s moduledoc)
  # -> one R replay record. `cwd` defaults to the repo; a nil `exit_code`
  # (a real `Task.shutdown/2 :brutal_kill` timeout — no exit status ever
  # existed) maps to exit -1 with the timeout disclosed in `summary`.
  defp project_command(command, repo) do
    exit_code = Map.get(command, "exit_code")
    kind = Map.get(command, "kind")
    status = Map.get(command, "status")

    %{
      "cmd" => Map.get(command, "cmd"),
      "cwd" => Map.get(command, "cwd") || repo,
      "exit" => if(is_integer(exit_code), do: exit_code, else: -1)
    }
    |> put_summary(kind, status, exit_code)
    |> put_output_sha(Map.get(command, "output"))
  end

  defp put_summary(command, kind, status, exit_code) do
    if is_nil(kind) and is_nil(status) do
      command
    else
      summary =
        Enum.reject(
          [kind, status, if(is_nil(exit_code), do: "source exit_code was nil (timeout)")],
          &is_nil/1
        )
        |> Enum.join("/")

      Map.put(command, "summary", summary)
    end
  end

  defp put_output_sha(command, output) when is_binary(output),
    do: Map.put(command, "output_sha256", Digest.hex(output))

  defp put_output_sha(command, _other), do: command

  defp authority(opts) do
    ceiling = Keyword.get(opts, :ceiling, "CONSTRUCT")

    if ceiling in @ceilings do
      {:ok,
       %{
         "ceiling" => ceiling,
         "grant" => Keyword.get(opts, :grant, "NONE"),
         "actor" => Keyword.get(opts, :actor, "ggen-igniter")
       }}
    else
      {:error, {:r_projection_refused, {:invalid_ceiling, ceiling}}}
    end
  end

  ## -- the R map itself -------------------------------------------------------

  defp build(receipt, repo, subject_sha, base_sha, work_order_id, commands, authority) do
    standing = standing(receipt, commands, subject_sha)

    %{
      "identity" => %{
        "subject" => work_order_id,
        "repo" => repo,
        "subject_sha" => subject_sha,
        "base_sha" => base_sha
      },
      "authority" => authority,
      "origin_authority" => authority,
      "consequence" => %{
        # Honest: `GgenIgniter.Sync` writes files; it never makes git commits.
        "commits" => [],
        "files_changed" => receipt.files,
        "remote_effects" => []
      },
      "replay" => %{"commands" => commands},
      "standing" => standing,
      "work_order_id" => work_order_id,
      "provider" => %{"name" => "ggen-igniter"},
      "provider_execution_id" => receipt.id,
      # Namespaced extension ONLY: receipt_hash is ggen_igniter's own chain
      # digest (Receipt.compute_receipt_hash/1), not a fleet R field — a bare
      # top-level key is refused by the fleet validator.
      @provider_ext_key => %{
        "receipt_hash" => receipt.receipt_hash || Receipt.compute_receipt_hash(receipt),
        "recipe_key" => receipt.recipe_key
      }
    }
    |> put_subject_state(receipt)
  end

  # pre_run_hash/post_run_hash (file-set digests) ride subject_before/after,
  # NEVER identity — a "sha256:hex" file-set digest is not a commit anchor.
  defp put_subject_state(r, receipt) do
    r
    |> maybe_put("subject_before", sha_digest(receipt.pre_run_hash))
    |> maybe_put("subject_after", sha_digest(receipt.post_run_hash))
  end

  defp sha_digest(value) when is_binary(value) and value != "", do: value
  defp sha_digest(_nil_or_blank), do: nil

  defp maybe_put(r, _key, nil), do: r
  defp maybe_put(r, key, value), do: Map.put(r, key, value)

  ## -- standing map -----------------------------------------------------------

  defp standing(receipt, commands, subject_sha) do
    {value, broken_term} = standing_value(receipt, commands)
    derived = derived_from(receipt, commands, subject_sha)

    %{"value" => value, "derived_from" => derived}
    |> put_broken_term(broken_term)
  end

  # broken_term is OPTIONAL in the R schema and its enum has no null member:
  # an absent key admits, a present-null key is refused by the fleet
  # validator. Omit, never emit null.
  defp put_broken_term(standing, nil), do: standing
  defp put_broken_term(standing, term), do: Map.put(standing, "broken_term", term)

  defp standing_value(%Receipt{standing: :alive}, commands) do
    if Enum.all?(commands, &(&1["exit"] == 0)) do
      {"ALIVE", nil}
    else
      # NEVER ALIVE over a non-zero/nil replay exit: the admission would be
      # vacuous — exactly Bootstrap.Receipts.check/1's own refusal.
      {@r_refused_admission_vacuous, "admission_vacuous"}
    end
  end

  defp standing_value(%Receipt{standing: :refused, reason: reason}, _commands),
    do: {"BLOCKED:" <> non_empty_reason(reason, "unspecified"), "mu_on_O"}

  defp standing_value(%Receipt{standing: :compensated}, _commands), do: {"PARTIAL_ALIVE", nil}

  defp standing_value(%Receipt{standing: :compensation_failed}, _commands),
    do: {"PARTIAL_ALIVE", nil}

  defp standing_value(%Receipt{standing: :build_broken}, _commands),
    do: {"BUILD_BROKEN", "mu_unlawful"}

  defp standing_value(_other, _commands), do: {"UNKNOWN", nil}

  # Non-empty, sanitized reason text — a receipt with a nil/blank reason
  # still yields an admissible non-empty fallback.
  defp non_empty_reason(reason, fallback) do
    case reason && String.trim(reason) do
      trimmed when is_binary(trimmed) and trimmed != "" -> trimmed
      _ -> fallback
    end
  end

  defp derived_from(%Receipt{} = receipt, commands, subject_sha) do
    count = length(commands)

    base =
      "ggen_igniter receipt #{receipt.id} (standing=#{receipt.standing}, #{count} replay " <>
        "command(s)) at subject_sha=#{subject_sha}"

    case receipt.standing do
      :refused ->
        base <> "; refused before actuation: " <> non_empty_reason(receipt.reason, "unspecified")

      :compensation_failed ->
        base <>
          "; CATASTROPHIC: compensation itself failed; " <>
          non_empty_reason(
            receipt.reason,
            "manual repair may be required (see receipt.metadata)"
          )

      _ ->
        base
    end
  end

  ## -- write/2 helpers ---------------------------------------------------------

  defp to_r(%Receipt{} = receipt, opts), do: project(receipt, opts)

  defp to_r(r, _opts) when is_map(r) and not is_struct(r) do
    case Receipts.check(r) do
      [] -> {:ok, r}
      errors -> {:error, {:r_projection_refused, {:invalid_r_map, errors}}}
    end
  end

  defp to_r(_other, _opts), do: {:error, {:r_projection_refused, :invalid_receipt}}

  defp output_path(opts) do
    case Keyword.get(opts, :output_path) do
      path when is_binary(path) and path != "" ->
        path = r_json_path(Path.expand(path))

        case Guard.forbidden_path(path) do
          nil -> {:ok, path}
          reason -> {:error, {:r_projection_refused, {:forbidden_output_path, reason}}}
        end

      _ ->
        {:error, {:r_projection_refused, :output_path_required}}
    end
  end

  # `<stem>.r.json`: an already-`.r.json` suffix is kept, a `.json` suffix is
  # replaced, a bare stem gains the suffix.
  defp r_json_path(path) do
    if String.ends_with?(path, ".r.json") do
      path
    else
      case Path.extname(path) do
        ".json" -> Path.rootname(path) <> ".r.json"
        _ -> path <> ".r.json"
      end
    end
  end

  # Deep key-sorted pretty JSON: byte-identical output for identical input,
  # independent of map construction order.
  defp encode(r) do
    r
    |> deep_sort()
    |> Jason.encode!(pretty: true)
    |> Kernel.<>("\n")
  end

  defp deep_sort(%{} = map) when not is_struct(map) do
    map
    |> Enum.map(fn {key, value} -> {key, deep_sort(value)} end)
    |> Enum.sort_by(&elem(&1, 0))
    |> Map.new()
  end

  defp deep_sort(list) when is_list(list), do: Enum.map(list, &deep_sort/1)
  defp deep_sort(other), do: other
end
