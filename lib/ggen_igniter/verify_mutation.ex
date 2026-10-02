defmodule GgenIgniter.VerifyMutation do
  @moduledoc """
  A mutation-court catalog over the fail-closed verify surface
  (`GgenIgniter.GateVerify` + `mix ggen_igniter.verify`'s in-process core):
  every mutant is a textual transform of a COPY of a real verify asset
  (`test/fixtures/ash_manufacture_pack/verify/*.unbound.rq`,
  `verify/cardinality.json`) materialized into a real tmp pack, and the court
  is the REAL verify run over the mutated pack. A mutant is `:killed` iff the
  real verify REFUSES the mutated pack; a mutant that still verifies clean is
  a way to silently defeat the fail-closed surface, i.e. a VACUOUS GATE, and
  the catalog fails.

  SHAPE ONLY is ported from `ash_a2a`'s
  `lib/ash_a2a/chicago/mutation/catalog.ex` (id / description / target /
  transform / named killer, append-only ids, nothing silently skipped). There
  is no dependency on ash_a2a and no BEAM hot-patching: ggen's courts are
  data files (`gates/*.rq`, `verify/*.unbound.rq`, `verify/cardinality.json`),
  not modules, so a textual mutant is the honest form here -- the same reason
  `GateVerify`'s own docs measure on file-level ontology mutations rather than
  function-level ones.

  ## The catalog (append-only; ids never change meaning)

  | id                            | target                                   | transform                                                                 | killer (the refusal that must fire) |
  |-------------------------------|------------------------------------------|---------------------------------------------------------------------------|-------------------------------------|
  | `unbound_filter_dropped`      | `verify/030_resources.unbound.rq`        | drop the `FILTER (!BOUND(?p_resource_module))` line                        | `{:unbound_facts, _}` -- the branch emits one spurious finding per amp:Resource |
  | `cardinality_anchor_relaxed`  | `verify/cardinality.json`                | repoint `attributes`' ROWS anchor off `amp:attributeName` to `amp:relationshipName` | `{:gate_cardinality, "attributes", 1, 9}` -- contract count no longer matches the gate |
  | `refutation_branch_required`  | `verify/035_default_actions.unbound.rq`  | neutralize the refutation: `OPTIONAL{...} + FILTER(!BOUND(...))` becomes a required triple pattern | `{:unbound_facts, _}` -- the branch emits one spurious finding per default action |
  | `census_projection_emptied`   | `verify/080_capabilities.unbound.rq`     | drop the `!BOUND` filter of the `mixTask` branch AND empty the projection to `SELECT ?subject` | `{:unbound_facts, _}` with `missing_property: nil` -- the census refuses on row count, not column completeness |
  | `cardinality_json_corrupted`  | `verify/cardinality.json`                | replace the file body with a truncated, unparseable JSON fragment          | `{:invalid_contract, _, :malformed_json}` -- typed refusal, never a crash |

  The last column is the load-bearing design point: on an otherwise PRISTINE
  ontology, the only verify-asset mutations that produce a refusal are ones
  that create spurious census findings, break a contract's agreement with its
  gate, or corrupt the contract boundary itself. A mutation that merely
  removes checking power (dropping a UNION branch, deleting a contract entry)
  verifies clean -- it is a real survival, and it is what
  `weakened_for_test: true` demonstrates wholesale.

  ## What `weakened_for_test` honestly is

  `run/1`'s `:weakened_for_test` option materializes each tmp pack WITHOUT the
  `verify/` directory -- the state of a Verify that loads no fail-closed
  assets at all (the pre-GGEN-1806 world: gates score `:pass` on `>= 1 row`
  and there is no census and no contracts). Every catalog mutant targets a
  `verify/` asset, so under the weakened verify every mutant's target is
  absent, the mutation is vacuous, and the mutants survive. That survival is
  the anti-vacuity inversion: it proves the court's kills come from the real
  verify's fail-closed checks, not from the harness asserting its own model.
  It is a TEST-ONLY probe; nothing in the runtime path reads that option.

  ## Run shape

  `run/1` first proves the control: the PRISTINE pack (with `verify/` when not
  weakened) must verify clean through the same `run_pack_verify/2` used for
  mutants. A control that refuses means the harness would score kills against
  a pre-broken pack, so it raises instead of measuring. Then, per mutant:
  materialize a fresh tmp pack (unique dir under `System.tmp_dir!()`), apply
  the transform (a missing target file is left untouched -- the mutant then
  survives, which is the honest verdict for a mutation that cannot land), run
  the real verify, record `:killed` / `:survived`, and delete the tmp dir
  before the next mutant. Deterministic: no clock, no RNG, no process
  dictionary, no hot-patch.

  The in-process verify core mirrors `Mix.Tasks.GgenIgniter.verify`'s private
  `verify/1` exactly where it is portable: same `GgenIgniter.GateVerify.load_cardinality/1`
  -> `GateVerify.run/3` -> `GateVerify.verify_unbound/2` order, enoent
  contracts degrade to the documented contractless default, and the task's
  `Mix.raise` on an invalid contract becomes a typed
  `{:refused, {:invalid_contract, stem, reason}}` here -- the same boundary in
  its non-crashing form, which is the form mutant `cardinality_json_corrupted`'s
  killer requires ("refuse, not crash").
  """

  alias GgenIgniter.GateVerify

  defmodule ControlRefused do
    defexception [:message]
  end

  @typedoc "A textual transform over a verify asset's file body."
  @type transform :: (String.t() -> String.t())

  @typedoc """
  One catalog mutant. `target_file` is pack-root-relative; `killer` documents
  the refusal that must fire (documentation, not executed logic).
  """
  @type mutant :: %{
          required(:id) => String.t(),
          required(:description) => String.t(),
          required(:target_file) => String.t(),
          required(:transform) => transform(),
          required(:killer) => String.t()
        }

  @typedoc "Verdict per mutant id, as returned by `run/1`."
  @type verdict :: :killed | :survived

  @source_pack Path.join(__DIR__, "../../test/fixtures/ash_manufacture_pack")

  @doc """
  The catalog, in append-only order. `run/1` runs every entry; ids are stable
  so a verdict map stays comparable across runs.
  """
  @spec catalog() :: [mutant()]
  def catalog do
    [
      %{
        id: "unbound_filter_dropped",
        description:
          "Drop the `FILTER (!BOUND(?p_resource_module))` line from the first branch of " <>
            "verify/030_resources.unbound.rq. The branch stops refuting and starts asserting: " <>
            "every amp:Resource becomes a (spurious) unbound-fact finding.",
        target_file: "verify/030_resources.unbound.rq",
        transform: fn body ->
          String.replace(body, "    FILTER (!BOUND(?p_resource_module))\n", "")
        end,
        killer:
          "GateVerify.verify_unbound/2 -> {:error, {:unbound_facts, findings}}: the mutated " <>
            "branch emits one finding per Resource on the pristine ontology, so the census " <>
            "refuses a pack that used to verify clean"
      },
      %{
        id: "cardinality_anchor_relaxed",
        description:
          "Repoint verify/cardinality.json's `attributes` ROWS contract off its required " <>
            "amp:attributeName anchor to amp:relationshipName. The contract no longer " <>
            "counts what gate `attributes` emits, so the agreement the fail-closed pair " <>
            "depends on is broken.",
        target_file: "verify/cardinality.json",
        transform: fn body ->
          String.replace(
            body,
            "http://seanchatmangpt.github.io/packs/ash-manufacture-pack#attributeName",
            "http://seanchatmangpt.github.io/packs/ash-manufacture-pack#relationshipName"
          )
        end,
        killer:
          "GateVerify.run/3 -> {:error, {:gate_cardinality, \"attributes\", 1, 9}}: the " <>
            "repointed anchor derives 1 subject from the graph while the gate emits 9 rows"
      },
      %{
        id: "refutation_branch_required",
        description:
          "Neutralize the refutation in verify/035_default_actions.unbound.rq's " <>
            "amp:defaultAction branch: `OPTIONAL {..} + FILTER (!BOUND(..))` becomes a " <>
            "required triple pattern. The branch still emits -- one row per default action " <>
            "-- but as an assertion, not a refutation.",
        target_file: "verify/035_default_actions.unbound.rq",
        transform: fn body ->
          String.replace(
            body,
            "OPTIONAL { ?subject amp:defaultAction ?p_default_action }\n" <>
              "    FILTER (!BOUND(?p_default_action))",
            "?subject amp:defaultAction ?p_default_action ."
          )
        end,
        killer:
          "GateVerify.verify_unbound/2 -> {:error, {:unbound_facts, findings}}: the " <>
            "required-pattern branch emits one spurious finding per (resource, action) " <>
            "pair on the pristine ontology"
      },
      %{
        id: "census_projection_emptied",
        description:
          "In verify/080_capabilities.unbound.rq, drop the `!BOUND` filter of the mixTask " <>
            "branch and empty the projection to `SELECT ?subject`. The census then emits " <>
            "one nameless finding per capability: the diagnostic column is gone, the rows " <>
            "are not.",
        target_file: "verify/080_capabilities.unbound.rq",
        transform: fn body ->
          body
          |> String.replace("SELECT ?subject ?missing_property", "SELECT ?subject")
          |> String.replace("    FILTER (!BOUND(?p_mix_task))\n", "")
        end,
        killer:
          "GateVerify.verify_unbound/2 -> {:error, {:unbound_facts, findings}} where every " <>
            "finding carries `missing_property: nil`: the census refuses on row count even " <>
            "when its result variable is emptied"
      },
      %{
        id: "cardinality_json_corrupted",
        description:
          "Replace verify/cardinality.json's body with a truncated, unparseable JSON " <>
            "fragment. The contract boundary must refuse this, not crash.",
        target_file: "verify/cardinality.json",
        transform: fn _body -> ~s({"gates": {"project":) end,
        killer:
          "GateVerify.load_cardinality/1 -> {:error, {:invalid_contract, path, :malformed_json}}: " <>
            "a typed refusal at the boundary (the mix task Mix.raises here; the in-process " <>
            "core returns the tuple), never a Jason crash"
      }
    ]
  end

  @doc "Catalog ids, append-only."
  @spec ids() :: [String.t()]
  def ids, do: Enum.map(catalog(), & &1.id)

  @doc """
  Runs every catalog mutant against the real verify core and returns
  `%{id => :killed | :survived}`.

  Options:

    * `:source_pack` -- the fixture pack to mutate copies of (default:
      `test/fixtures/ash_manufacture_pack`).
    * `:weakened_for_test` -- materialize packs WITHOUT `verify/` (see the
      moduledoc's honesty section). Default `false`.

  Raises `ControlRefused` if the pristine control pack does not verify clean.
  """
  @spec run(keyword()) :: %{optional(String.t()) => verdict()}
  def run(opts \\ []) when is_list(opts) do
    source_pack = Keyword.get(opts, :source_pack, @source_pack)
    weakened? = Keyword.get(opts, :weakened_for_test, false)

    control_dir = materialize(source_pack, weakened?)

    verdicts =
      try do
        case run_pack_verify(control_dir) do
          :pass ->
            :ok

          {:refused, reason} ->
            raise ControlRefused,
              message:
                "the pristine control pack refused (#{inspect(reason)}); the catalog " <>
                  "would score kills against a pre-broken pack"
        end

        Enum.into(catalog(), %{}, fn mutant ->
          {mutant.id, run_mutant(mutant, source_pack, weakened?)}
        end)
      after
        File.rm_rf!(control_dir)
      end

    verdicts
  end

  defp run_mutant(mutant, source_pack, weakened?) do
    pack_dir = materialize(source_pack, weakened?)
    apply_mutation(pack_dir, mutant)

    verdict =
      case run_pack_verify(pack_dir) do
        :pass -> :survived
        {:refused, _reason} -> :killed
      end

    File.rm_rf!(pack_dir)
    verdict
  end

  # The real verify core, in `Mix.Tasks.GgenIgniter.verify`'s own order:
  # contracts first (enoent degrades to the contractless default; an invalid
  # contract is a typed refusal here where the task Mix.raises), then gates
  # under contract, then the unbound census. Both must come back {:ok, _} for
  # the pack to score :pass.
  @spec run_pack_verify(String.t()) :: :pass | {:refused, term()}
  defp run_pack_verify(pack_dir) do
    ontology_path = Path.join(pack_dir, "ontology.ttl")
    cardinality_path = GateVerify.default_cardinality_path(pack_dir)

    with {:ok, contracts} <- load_contracts(cardinality_path),
         {:ok, _gates} <- GateVerify.run(pack_dir, ontology_path, cardinality: contracts),
         {:ok, []} <- GateVerify.verify_unbound(pack_dir, ontology_path) do
      :pass
    else
      {:refused, _} = refused -> refused
      {:error, reason} -> {:refused, reason}
    end
  end

  # `Mix.Tasks.GgenIgniter.verify`'s `load_contracts/1` in its non-crashing
  # form: enoent keeps the documented contractless default; an invalid
  # contract Mix.raises there and is a typed refusal here.
  defp load_contracts(path) do
    case GateVerify.load_cardinality(path) do
      {:ok, contracts} -> {:ok, contracts}
      {:error, {:enoent, _}} -> {:ok, %{}}
      {:error, {:invalid_contract, stem, reason}} -> {:refused, {:invalid_contract, stem, reason}}
    end
  end

  # Copies ontology.ttl + gates/ (+ verify/ unless weakened) into a unique
  # tmp dir -- exactly the inputs the verify core reads, nothing else.
  defp materialize(source_pack, weakened?) do
    tmp_root = System.tmp_dir!()

    dir =
      Path.join(tmp_root, "ggen_igniter_verify_mutation-#{System.unique_integer([:positive])}")

    File.mkdir_p!(dir)

    File.cp_r!(Path.join(source_pack, "ontology.ttl"), Path.join(dir, "ontology.ttl"))

    if File.dir?(Path.join(source_pack, "gates")) do
      File.cp_r!(Path.join(source_pack, "gates"), Path.join(dir, "gates"))
    end

    if not weakened? and File.dir?(Path.join(source_pack, "verify")) do
      File.cp_r!(Path.join(source_pack, "verify"), Path.join(dir, "verify"))
    end

    dir
  end

  # A missing target file is left untouched: the mutation cannot land, so the
  # mutant survives -- the honest verdict under `weakened_for_test`, where
  # every catalog target is deliberately absent.
  defp apply_mutation(pack_dir, mutant) do
    target = Path.join(pack_dir, mutant.target_file)

    with {:ok, body} <- File.read(target) do
      File.write!(target, mutant.transform.(body))
    end

    :ok
  end
end
