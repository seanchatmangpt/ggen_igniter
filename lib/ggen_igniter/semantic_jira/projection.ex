defmodule GgenIgniter.SemanticJira.Projection do
  @moduledoc """
  The sjira `:projection` backend (smalt PROJECTION-ARCH-PLAN §D4, wave W8):
  one work order -> one capability row -> one rendered artifact, through the
  REAL reconciliation pipeline, pinned to the pack.lock digest of the pack
  that rendered it.

  Contract (per D4):

    1. **Resolve the pack** from the order's `sj:targetPack`
       (`order["target_pack"]`), pinned by pack.lock digest:
       `GgenIgniter.PackLock.check/2` must pass against `opts[:lock_path]`
       before any byte is rendered or written; a tampered or unpinned pack
       refuses `{:pack_lock_failed, reason}` (`mu_unlawful` at the execute
       hop).
    2. **Scope to one row/template by `sj:capabilityId`**
       (`order["capability_id"]`): the pack carries
       `projections/<capability_id>.rq` -- the capability's row query, a
       SELECT over the pack ontology returning exactly that capability's
       rows. It is bound as the named query `capability` through
       `GgenIgniter.Reconcile.run/1`'s explicit `:query` seam
       (`"capability=<path>"`), so the pack's template renders ONLY the
       scoped row(s): one WO <-> one capability <-> one row-set <-> one
       render. A missing scope query refuses `{:capability_unknown, id}`.
    3. **Write via `GgenIgniter.Actuate.write_file!/3` at
       `sj:targetPath`** (`order["target_path"]`, resolved against
       `opts[:target_dir]`; a path escaping the target root refuses
       `{:bad_output_path, _}`). The guarded write is the idempotency
       surface: `:written` on first write or after a pack-digest change
       (content differs), `:unchanged` on a byte-identical re-run,
       `:skipped_exists` when `unless_exists: true` and the target already
       exists regardless of content.
    4. **Post-render gates**: `GgenIgniter.GateVerify.run/3` +
       `GateVerify.verify_unbound/2` over the pack (the capability's
       `gates/*.rq`, >= 1 row each, plus the projected falsifier gates of
       step 5). Any failure refuses `{:verification_failed, inspect(reason)}`,
       leaving the target tree holding the actuated file with standing NOT
       advanced -- the same fail-closed honesty `Execute`'s local backend
       documents for its own gate hop.
    5. **Falsifier -> gate projection**: each order falsifier
       (`order["falsifiers"]`, e.g. `"urn:semantic-jira:falsifier:EXEC-1:f1"`)
       becomes a verify gate keyed by capabilityId. The pack carries the
       capability's FALSIFIED-STATE query at
       `projections/<capability_id>.unbound.rq` (a query binding rows
       exactly when the falsified condition holds, projecting the
       `subject`/`missing_property` contract `GateVerify.verify_unbound/2`
       consumes); the projection writes it once per falsifier into
       `verify/<capability>-falsifier-<n>.unbound.rq` -- in a STAGING COPY of
       the pack, never into the digest-pinned original (writing into the
       pinned pack would invalidate the very digest the receipt commits to).
       A capability with falsifiers but no falsified-state query refuses
       `{:falsifier_gates_missing, id}`.
    6. **Reconcile receipt**: `%{"order_id" => .., "capability_id" => ..,
       "pack_digest" => .., "render_digest" => .., "gate_results" => ..}` --
       `pack_digest` is the real `PackLock.digest_checked/1` hex of the pack
       at `opts[:pack_dir]`, `render_digest` is
       `GgenIgniter.SemanticJira.digest_exact/1` over the exact bytes
       written. `GgenIgniter.SemanticJira.Execute` places this map inside the
       synthesized sealed export under `"projection"`, so the ledger append
       advances standing against it.
    7. **Idempotency**: re-running an already-projected capability is a
       no-op unless the pack digest changed: the rendered bytes are
       deterministic given (pack digest, capability id), so a re-render is
       byte-identical and `write_file!/3` returns `:unchanged`; a changed
       pack renders different bytes and returns `:written`.

  Rendering runs against a staging copy of the pack (real `File.cp_r/2`) so
  the projected falsifier gates ride the same `verify_unbound` census as the
  pack's own; the pack digest in the receipt is always computed over the
  ORIGINAL `opts[:pack_dir]`, never the staging copy. Manufactured `.ex`
  artifacts are `Code.format_string!/1`-formatted before the render digest is
  computed (the `Execute` local backend's disclosed pre-digest formatting,
  mirrored here so both actuation paths commit to formatted bytes; extracting
  a shared helper would touch files this lane does not own).

  Zero `mix` shell-outs: every hop is a function call into `PackLock`,
  `Reconcile`, `Actuate`, `GateVerify` and `SemanticJira.digest_exact/1`.
  """

  alias GgenIgniter.{Actuate, GateVerify, Pack, PackLock, Reconcile}
  alias GgenIgniter.SemanticJira

  @typedoc "Idempotent-write outcome, per `GgenIgniter.Actuate.write_file!/3`."
  @type outcome :: :written | :unchanged | :skipped_exists

  @typedoc """
  Refusal reasons: `{:pack_lock_failed, PackLock reason}`, `{:capability_unknown,
  id}`, `{:falsifier_gates_missing, id}`, `{:bad_output_path, message}`,
  `{:verification_failed, message}`, `{:sync_failed, message}`.
  """
  @type refusal ::
          {:pack_lock_failed, term()}
          | {:capability_unknown, String.t()}
          | {:falsifier_gates_missing, String.t()}
          | {:bad_output_path, String.t()}
          | {:verification_failed, String.t()}
          | {:sync_failed, String.t()}
          | {:target_pack_mismatch, String.t(), String.t()}

  @doc """
  Renders the capability's row(s) through the real pipeline and writes the
  guarded artifact at `sj:targetPath`, returning
  `{:ok, outcome(), receipt}` or `{:error, refusal()}`.

  Required opts: `:pack_dir`, `:target_dir`, `:lock_path`. Required order
  fields: `"capability_id"` (`sj:capabilityId`), `"target_path"`
  (`sj:targetPath`). Optional opts: `:capability_id` / `:target_path`
  (override the order fields), `:falsifiers` (list of falsifier URNs;
  default: the order's `"falsifiers"`), `:unless_exists` (default `false`),
  `:template` (explicit template for multi-template packs, the `--template`
  convention), `:ontology` (resolved absolute ontology path, the Execute
  `order_ontology/2` product; default: the pack's `ontology.ttl`).
  """
  @spec project(map(), keyword()) :: {:ok, outcome(), map()} | {:error, refusal()}
  def project(order, opts) when is_map(order) and is_list(opts) do
    pack_dir = Keyword.fetch!(opts, :pack_dir)
    target_dir = Keyword.fetch!(opts, :target_dir)
    lock_path = Keyword.fetch!(opts, :lock_path)

    with {:ok, capability_id} <- order_field(order, opts, :capability_id),
         {:ok, target_path} <- order_field(order, opts, :target_path),
         :ok <- check_pack_name(order["target_pack"], pack_dir),
         :ok <- lock_check(pack_dir, lock_path),
         {:ok, pack_digest} <- PackLock.digest_checked(pack_dir) do
      staged_project(
        order,
        capability_id,
        target_path,
        pack_dir,
        target_dir,
        pack_digest,
        opts
      )
    end
  end

  # ── staged body (runs inside try/after over the staging copy) ──────────────

  defp staged_project(order, capability_id, target_path, pack_dir, target_dir, pack_digest, opts) do
    staging = staging_dir(pack_dir)
    falsifiers = falsifiers(order, opts)

    try do
      with {:ok, scope_query_path} <- scope_query(staging, capability_id),
           :ok <- falsifier_gates(staging, capability_id, falsifiers),
           {:ok, rendered} <- render(staging, scope_query_path, opts),
           content = maybe_format_elixir(target_path, rendered),
           render_digest = SemanticJira.digest_exact(content),
           {:ok, abs_target} <- scoped_path(target_path, target_dir),
           {:ok, outcome} <- write(abs_target, content, opts),
           {:ok, gate_results} <- gates(staging, ontology_path(staging, opts)) do
        {:ok, outcome,
         %{
           "order_id" => order["identity"],
           "capability_id" => capability_id,
           "pack_digest" => pack_digest,
           "render_digest" => render_digest,
           "write_outcome" => Atom.to_string(outcome),
           "gate_results" => gate_results,
           "target_path" => target_path
         }}
      end
    after
      File.rm_rf!(staging)
    end
  end

  # -- steps -------------------------------------------------------------------

  # The `sj:targetPack` WORLD check, same law and precedence as `Execute`'s
  # own `check_target_pack/2`: nil imposes no constraint; otherwise the pack
  # must resolve to the same name (`pack.toml` `[pack].name` via
  # `GgenIgniter.Pack.parse_manifest/1` when present, else the directory's
  # basename).
  defp check_pack_name(nil, _pack_dir), do: :ok

  defp check_pack_name(expected, pack_dir) do
    resolved = resolve_pack_name(pack_dir)

    if resolved == expected do
      :ok
    else
      {:error, {:target_pack_mismatch, expected, resolved}}
    end
  end

  defp resolve_pack_name(pack_dir) do
    case Pack.parse_manifest(pack_dir) do
      {:ok, %Pack.Manifest{name: name}} -> name
      _ -> pack_dir |> Path.expand() |> Path.basename()
    end
  end

  defp lock_check(pack_dir, lock_path) do
    case PackLock.check(pack_dir, lock_path) do
      :ok -> :ok
      {:error, reason} -> {:error, {:pack_lock_failed, reason}}
    end
  end

  # One row/template by capabilityId: the scope query must exist at
  # `projections/<capability_id>.rq` in the staging copy.
  defp scope_query(staging, capability_id) do
    path = Path.join([staging, "projections", capability_id <> ".rq"])

    if File.regular?(path) do
      {:ok, path}
    else
      {:error, {:capability_unknown, capability_id}}
    end
  end

  # Falsifier -> gate projection: copy the capability's falsified-state query
  # into `verify/<capability>-falsifier-<n>.unbound.rq`, once per falsifier,
  # each header-annotated with its falsifier URN. Only capabilities WITH
  # falsifiers need the gate; a capability with falsifiers but no
  # `projections/<id>.unbound.rq` refuses (`admission_vacuous` at the execute
  # hop: a falsifier with no gate is a court that cannot fire).
  defp falsifier_gates(_staging, _capability_id, []), do: :ok

  defp falsifier_gates(staging, capability_id, falsifiers) do
    source = Path.join([staging, "projections", capability_id <> ".unbound.rq"])

    with {:ok, body} <- read_falsified_state(source, capability_id) do
      verify_dir = Path.join(staging, "verify")
      File.mkdir_p!(verify_dir)

      falsifiers
      |> Enum.with_index(1)
      |> Enum.each(fn {falsifier, n} ->
        gate_path =
          Path.join(verify_dir, "#{capability_id}-falsifier-#{n}.unbound.rq")

        File.write!(gate_path, falsifier_gate_body(falsifier, body))
      end)

      :ok
    end
  end

  defp read_falsified_state(source, capability_id) do
    case File.read(source) do
      {:ok, body} ->
        {:ok, body}

      {:error, _} ->
        {:error, {:falsifier_gates_missing, capability_id}}
    end
  end

  defp falsifier_gate_body(falsifier, body) do
    "# projected falsifier gate (<urn> below) -- GENERATED by " <>
      "GgenIgniter.SemanticJira.Projection; the pack's falsified-state query " <>
      "for this capability, copied per falsifier.\n# falsifier: #{falsifier}\n" <>
      body
  end

  # The real pipeline, scoped: pack_dir = staging (pack queries + the
  # projected falsifier gates), the capability scope query as the explicit
  # named binding `capability`. Rendered to a temp out path -- the ACTUATION
  # decision belongs to `write/3`, not to the pipeline's own guarded write.
  defp render(staging, scope_query_path, opts) do
    out_path = Path.join(staging, ".projection-render-out")

    query_opt = "capability=" <> scope_query_path

    opt_template =
      case opts[:template] do
        nil -> []
        "" -> []
        path -> [template: path]
      end

    render_opts =
      [pack_dir: staging, out: out_path]
      |> Keyword.merge(opt_template)
      |> Keyword.put(:query, query_opt)

    try do
      with {:ok, _result} <- Reconcile.run(render_opts) do
        {:ok, File.read!(out_path)}
      end
    rescue
      error -> {:error, {:sync_failed, "Reconcile.run/1 raised: " <> Exception.message(error)}}
    end
  end

  # `Execute`'s disclosed pre-digest formatting, mirrored (see moduledoc):
  # only a `.ex`-suffix target attempts formatting; a syntax error leaves the
  # rendered bytes untouched (formatting never invents content).
  defp maybe_format_elixir(target_path, content) do
    if String.ends_with?(target_path, ".ex") do
      try do
        content |> Code.format_string!(line_length: 100) |> IO.iodata_to_binary()
      rescue
        _ -> content
      end
    else
      content
    end
  end

  # Path-scope law, same shape as `Execute`'s: `sj:targetPath` resolves
  # against the target root; `..` escaping it is a typed refusal before any
  # byte is written.
  defp scoped_path(path, target_dir) do
    abs = if Path.type(path) == :absolute, do: path, else: Path.join(target_dir, path)
    expanded = Path.expand(abs)

    if String.starts_with?(expanded, Path.expand(target_dir) <> "/") do
      {:ok, expanded}
    else
      {:error,
       {:bad_output_path,
        "target path #{inspect(path)} escapes target root #{inspect(target_dir)}"}}
    end
  end

  # The guarded write IS the idempotency surface (`Actuate.write_file!/3`'s
  # documented decision order). `unless_exists` defaults to false: a
  # byte-identical re-run is `:unchanged`; changed pack bytes re-write.
  defp write(abs_target, content, opts) do
    case Actuate.write_file!(abs_target, content, unless_exists: opts[:unless_exists] == true) do
      {:ok, outcome} -> {:ok, outcome}
      other -> {:error, {:sync_failed, "Actuate.write_file!/3 returned: " <> inspect(other)}}
    end
  end

  # The fail-closed court over the staging copy: every `gates/*.rq` (>= 1 row)
  # and every `verify/*.unbound.rq` -- INCLUDING the projected falsifier
  # gates -- must pass, or standing never advances.
  defp gates(staging, ontology_path) do
    with {:ok, results} <- GateVerify.run(staging, ontology_path),
         {:ok, []} <- GateVerify.verify_unbound(staging, ontology_path) do
      {:ok,
       %{
         "status" => "pass",
         "steps" => Enum.map(results, fn {name, :pass} -> %{"id" => name, "status" => "pass"} end)
       }}
    else
      {:error, reason} -> {:error, {:verification_failed, inspect(reason)}}
    end
  end

  # Order-carried authority graph (Execute's `order_ontology/2` product,
  # passed through as an already-resolved absolute path) or the pack default.
  defp ontology_path(staging, opts) do
    case opts[:ontology] do
      path when is_binary(path) and path != "" -> path
      _ -> Pack.default_ontology(staging)
    end
  end

  # ── invocation helpers ─────────────────────────────────────────────────────

  # :capability_id reads order["capability_id"] unless overridden in opts;
  # :target_path likewise (the Execute hop passes the order fields straight
  # through; the overrides exist for direct callers and tests).
  defp order_field(order, opts, key) do
    field = key_string(key)

    with value when is_binary(value) and value != "" <-
           Keyword.get(opts, key) || Map.get(order, field) do
      {:ok, value}
    else
      _ -> {:error, missing_reason(key)}
    end
  end

  defp key_string(:capability_id), do: "capability_id"
  defp key_string(:target_path), do: "target_path"

  defp missing_reason(:capability_id), do: {:capability_unknown, ""}
  defp missing_reason(:target_path), do: {:bad_output_path, "order field `target_path` missing"}

  defp falsifiers(order, opts) do
    case Keyword.get(opts, :falsifiers) do
      list when is_list(list) -> list
      _ -> order |> Map.get("falsifiers", []) |> List.wrap()
    end
  end

  defp staging_dir(pack_dir) do
    Path.join(
      System.tmp_dir!(),
      "ggen_igniter_projection_staging_#{System.unique_integer([:positive])}"
    )
    |> tap(&File.cp_r!(pack_dir, &1))
  end
end
