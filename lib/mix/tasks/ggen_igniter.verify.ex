defmodule Mix.Tasks.GgenIgniter.Verify do
  @shortdoc "Fails a pack CLOSED: inverted verify queries plus per-gate cardinality contracts."

  @moduledoc """
  Runs a pack's fail-CLOSED checks against its ontology: the inverted
  companion queries in `<pack>/verify/*.unbound.rq` and the per-gate
  cardinality contract in `<pack>/verify/cardinality.json`.

  ## Why this exists

  `mix ggen_igniter.sync` and `GgenIgniter.GateVerify.run/2` score a gate on
  the pack corpus's documented rule: at least one row is a pass. Every gate in
  `test/fixtures/ash_manufacture_pack/gates/` is a conjunctive `SELECT`, so
  that rule FAILS OPEN -- one missing triple silently drops an individual from
  the plan instead of failing the run.

  Measured, not argued. Deleting `amp:primaryKeyKind` from `amp:BookResource`
  drops `gates/030_resources.rq` from 2 rows to 1 while
  `gates/040_attributes.rq` still returns all 9 rows, so Book's 5 attributes
  are projected onto a resource that is never generated -- and the gate scores
  `:pass`. Deleting one `amp:evidence` triple drops the `ash.install`
  capability from `gates/080_capabilities.rq` (21 rows to 20), and because the
  manufacture template gates the install step on that capability's admission,
  the Ash installation silently does not happen. Deleting an `amp:refusalReason`
  from an inadmissible capability drops `gates/085_refusals.rq` from 9 rows to
  8, turning a VISIBLE typed refusal into a silent skip.

  This task refuses all three.

  ## The two checks are complementary, so both always run

  Even when the gate/cardinality pass reports a failure, the inverted-query
  census still runs and is still printed. That pairing is the point: the
  contract says *"gate `resources` emitted 1 row, the graph holds 2
  amp:Resource individuals"*, and the census says *which* subject lost *which*
  predicate. Reporting only the first would discard half the diagnosis.

  ## Why `verify/` and not `gates/`

  `GgenIgniter.Pack.discover_queries/1` globs `gates/*.rq` only
  (`lib/ggen_igniter/pack.ex:87`), and five call sites consume that namespace.
  An inverted query placed under `gates/` would be doubly wrong: it would score
  `:pass` exactly when the ontology is BROKEN, and `mix ggen_igniter.sync`
  flattens a one-row query's columns into top-level template bindings,
  injecting `subject`/`missing_property` into the template namespace. A sibling
  `verify/` directory is invisible to all five call sites.

  ## Usage

      mix ggen_igniter.verify --pack test/fixtures/ash_manufacture_pack
      mix ggen_igniter.verify --pack PACK --ontology path/to/other.ttl
      mix ggen_igniter.verify --pack PACK --json

  ## Flags

    * `--pack PATH` (required) -- the pack directory holding `gates/` and
      `verify/`.
    * `--ontology PATH` -- defaults to `<pack>/ontology.ttl`.
    * `--cardinality PATH` -- defaults to `<pack>/verify/cardinality.json`. A
      pack with no such file is verified WITHOUT contracts (see below) rather
      than refused.
    * `--json` -- one JSON document on stdout instead of human-readable lines.
    * `--help`, `-h` -- this usage text.

  ## Contracts are additive

  A missing `verify/cardinality.json`, or a gate stem absent from it, keeps
  `GgenIgniter.GateVerify`'s documented `>= 1 row` behaviour. Other packs in
  this repo were authored against that rule and ship no contract file at all,
  so a missing file is reported as a fact and is not itself a failure.

  Exits 0 when both checks pass, 1 otherwise.
  """

  use Mix.Task

  @impl Mix.Task
  def run(argv) do
    {opts, _positional, invalid} =
      OptionParser.parse(argv,
        strict: [
          pack: :string,
          ontology: :string,
          cardinality: :string,
          json: :boolean,
          help: :boolean
        ],
        aliases: [p: :pack, o: :ontology, h: :help]
      )

    cond do
      opts[:help] -> print_help()
      invalid != [] -> Mix.raise("unknown flag(s): #{inspect(Enum.map(invalid, &elem(&1, 0)))}")
      is_nil(opts[:pack]) -> Mix.raise(usage("--pack is required"))
      true -> verify(opts)
    end
  end

  defp verify(opts) do
    pack_dir = opts[:pack]
    ontology_path = opts[:ontology] || GgenIgniter.Pack.default_ontology(pack_dir)

    cardinality_path =
      opts[:cardinality] || GgenIgniter.GateVerify.default_cardinality_path(pack_dir)

    unless File.dir?(pack_dir), do: Mix.raise("no pack directory at #{pack_dir}")
    unless File.exists?(ontology_path), do: Mix.raise("no ontology at #{ontology_path}")

    {contracts, contract_note} = load_contracts(cardinality_path)

    gate_result = GgenIgniter.GateVerify.run(pack_dir, ontology_path, cardinality: contracts)
    unbound_result = GgenIgniter.GateVerify.verify_unbound(pack_dir, ontology_path)

    if opts[:json] do
      report_json(gate_result, unbound_result, contracts, contract_note)
    else
      report_human(gate_result, unbound_result, contracts, contract_note, pack_dir)
    end

    if failed?(gate_result) or failed?(unbound_result) do
      # Mix.raise gives the nonzero exit a CI gate needs. Both results are
      # already printed above, so the message names the outcome rather than
      # repeating the detail.
      Mix.raise("ggen_igniter.verify: pack did not verify (see findings above)")
    end
  end

  defp failed?({:error, _}), do: true
  defp failed?({:ok, _}), do: false

  defp load_contracts(path) do
    case GgenIgniter.GateVerify.load_cardinality(path) do
      {:ok, contracts} ->
        {contracts, "loaded #{map_size(contracts)} gate contract(s) from #{path}"}

      {:error, {:enoent, _}} ->
        # Not a failure: a pack without contracts keeps the documented
        # >= 1-row default. Reported so the weaker check is never invisible.
        {%{}, "no #{path} -- gates verified WITHOUT cardinality contracts"}

      {:error, {:invalid_contract, stem, reason}} ->
        Mix.raise("invalid cardinality contract for gate #{inspect(stem)}: #{inspect(reason)}")
    end
  end

  defp report_human(gate_result, unbound_result, contracts, contract_note, pack_dir) do
    shell = Mix.shell()
    shell.info("ggen_igniter.verify: #{pack_dir}")
    shell.info("  cardinality: #{contract_note}")

    case gate_result do
      {:ok, results} ->
        shell.info("  gates: #{length(results)} passed, #{map_size(contracts)} under contract")

      {:error, {:gate_failed, name}} ->
        shell.error("  gates: FAILED -- gate #{inspect(name)} returned zero rows")

      {:error, {:gate_cardinality, name, expected, actual}} ->
        shell.error(
          "  gates: FAILED -- gate #{inspect(name)} emitted #{actual} row(s), " <>
            "contract expects #{expected} (a conjunct dropped an individual)"
        )
    end

    case unbound_result do
      {:ok, []} ->
        shell.info("  verify: 0 unbound facts")

      {:error, {:unbound_facts, findings}} ->
        shell.error("  verify: #{length(findings)} unbound fact(s)")

        Enum.each(findings, fn f ->
          shell.error("    [#{f.gate}] #{f.subject} is missing #{f.missing_property}")
        end)
    end
  end

  defp report_json(gate_result, unbound_result, contracts, contract_note) do
    Mix.shell().info(
      Jason.encode!(
        %{
          "cardinality" => %{
            "note" => contract_note,
            "gates_under_contract" => contracts |> Map.keys() |> Enum.sort()
          },
          "gates" => gate_json(gate_result),
          "verify" => unbound_json(unbound_result),
          "ok" => not (failed?(gate_result) or failed?(unbound_result))
        },
        pretty: true
      )
    )
  end

  defp gate_json({:ok, results}) do
    %{"status" => "pass", "passed" => Enum.map(results, fn {name, :pass} -> name end)}
  end

  defp gate_json({:error, {:gate_failed, name}}) do
    %{"status" => "gate_failed", "gate" => name}
  end

  defp gate_json({:error, {:gate_cardinality, name, expected, actual}}) do
    %{"status" => "gate_cardinality", "gate" => name, "expected" => expected, "actual" => actual}
  end

  defp unbound_json({:ok, []}), do: %{"status" => "pass", "findings" => []}

  defp unbound_json({:error, {:unbound_facts, findings}}) do
    %{
      "status" => "unbound_facts",
      "findings" =>
        Enum.map(findings, fn f ->
          %{"gate" => f.gate, "subject" => f.subject, "missing_property" => f.missing_property}
        end)
    }
  end

  defp print_help, do: Mix.shell().info(usage(nil))

  defp usage(prefix) do
    body = """
    USAGE

        mix ggen_igniter.verify --pack PACK_DIR [--ontology PATH]
                                [--cardinality PATH] [--json]

    Runs a pack's fail-CLOSED checks: every `<pack>/verify/*.unbound.rq`
    inverted companion query (zero rows is the pass condition) plus the
    per-gate cardinality contract in `<pack>/verify/cardinality.json`.

    FLAGS

        --pack, -p PATH         pack directory holding gates/ and verify/ (required)
        --ontology, -o PATH     ontology to verify (default: <pack>/ontology.ttl)
        --cardinality PATH      contract file (default: <pack>/verify/cardinality.json)
        --json                  one JSON document on stdout
        --help, -h              this text

    Exits 0 when both checks pass, 1 otherwise.
    """

    if prefix, do: prefix <> "\n\n" <> body, else: body
  end
end
