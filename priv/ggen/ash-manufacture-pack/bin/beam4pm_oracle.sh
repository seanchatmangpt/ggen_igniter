#!/usr/bin/env bash
# A THIRD-PARTY process oracle over the manufactured OCEL evidence.
#
# Why this exists: the only third-party touch in the qualification ladder was
# `import_ocel_json` asserting that a handle came back, over run 1 only. A
# handle proves the document parses; it computes nothing. Every semantic claim
# was therefore checked by the pack's own conformance.py -- which shares an
# author with the emitter and with the amp: ontology -- so OCEL_PROCESS_ALIVE
# was a closed authorial loop. This script breaks that loop: the numbers below
# are computed inside beam4pm's rust4pm wasm module (the `process_mining` crate),
# by code with no knowledge of the ontology, the pack, or the templates.
#
# It reimplements NO process mining. It frames requests, reads the crate's
# answers, and compares them to values that were measured -- not invented --
# from the four real logs on disk.
#
# Usage:
#   bash beam4pm_oracle.sh <qualification-output-dir>
#
# <qualification-output-dir> is the directory qualify.sh writes, holding
# ocel-run1/, ocel-run2/ (and any later ocel-runN/).
#
# Environment:
#   BEAM4PM_DIR   beam4pm checkout (default: $HOME/beam4pm)
#
# Exit codes -- a missing oracle must never look like a passing one:
#   0   every assertion held
#   1   a deviation, a missing calibrated run, or an engine error
#   2   usage error (no argument, or the directory does not exist)
#   77  SKIP: beam4pm's wasm artifact is absent, so nothing was computed
#
# Output:
#   stdout  one JSON line per log: stats, mix_task variants, manufacture_run DFG
#   stderr  per-assertion verdicts, the engine's own compile/run noise, summary

set -euo pipefail

usage() {
  sed -n '2,33p' "$0" | sed 's/^# \{0,1\}//'
}

if [ "${1:-}" = "--help" ] || [ "${1:-}" = "-h" ]; then
  usage
  exit 0
fi

if [ $# -ne 1 ]; then
  echo "usage: beam4pm_oracle.sh <qualification-output-dir>" >&2
  exit 2
fi

OUT_ARG="$1"
if [ ! -d "$OUT_ARG" ]; then
  echo "beam4pm_oracle: not a directory: $OUT_ARG" >&2
  exit 2
fi
OUT="$(cd "$OUT_ARG" && pwd)"

BEAM4PM="${BEAM4PM_DIR:-$HOME/beam4pm}"
# Path of the built engine artifact, fixed by beam4pm itself
# (lib/beam4pm_rust4pm.ex:90, @wasm_rel) -- an upstream contract, not a choice
# this script gets to make. The engine behind it is the `process_mining` crate
# pinned at "=0.6.2" (lib/beam4pm_rust4pm.ex:6); the version is deliberately
# NOT copied into the emitted records, which would go stale on a bump.
WASM="$BEAM4PM/native/rust4pm-wasm/target/wasm32-wasip1/release/rust4pm_wasm.wasm"

if [ ! -f "$WASM" ]; then
  echo "beam4pm_oracle: SKIP -- no wasm artifact at $WASM" >&2
  echo "beam4pm_oracle: nothing was computed; this is exit 77 (SKIP), not 0." >&2
  exit 77
fi

# ---------------------------------------------------------------- inputs
# Iterate EVERY run directory present, not run 1 alone. The naming
# (ocel-run<N>/<app>.<task>.<phase>.ocel.json) is the contract between
# qualify.sh's copy step and ggen_igniter.ocel.seal's output path.
INPUTS=""
LOG_COUNT=0
for run_dir in "$OUT"/ocel-run*; do
  [ -d "$run_dir" ] || continue
  run_key="$(basename "$run_dir")"
  run_key="${run_key#ocel-}"
  for log in "$run_dir"/*.ocel.json; do
    [ -f "$log" ] || continue
    stem="$(basename "$log" .ocel.json)"
    phase="${stem##*.}"
    INPUTS="${INPUTS}${run_key}/${phase}	${log}
"
    LOG_COUNT=$((LOG_COUNT + 1))
  done
done

if [ "$LOG_COUNT" -eq 0 ]; then
  echo "beam4pm_oracle: FAIL -- no ocel-run*/*.ocel.json under $OUT" >&2
  echo "beam4pm_oracle: an oracle with no evidence to read is a failure, not a pass." >&2
  exit 1
fi

WORK="$(mktemp -d "${TMPDIR:-/tmp}/beam4pm-oracle.XXXXXX")"
trap 'rm -rf "$WORK"' EXIT
SCRIPT="$WORK/oracle.exs"
JSONL="$WORK/oracle.jsonl"
RUNLOG="$WORK/run.log"

cat > "$SCRIPT" <<'ELIXIR'
# Runs inside beam4pm via `mix run`. Every count, variant and DFG edge below is
# computed by the rust4pm wasm module; this file only frames the requests and
# compares the answers.
alias BeamPM.Rust4PM

jsonl_path = System.fetch_env!("ORACLE_JSONL")

inputs =
  System.fetch_env!("ORACLE_INPUTS")
  |> String.split("\n", trim: true)
  |> Enum.map(fn line ->
    [key, path] = String.split(line, "\t", parts: 2)
    {key, path}
  end)

# Event/object type names are the emitter's wire vocabulary -- upstream
# contracts this oracle consumes, so they are literals by necessity.
refused_event_type = "capability_refused"
mix_task_object_type = "mix_task"
run_object_type = "manufacture_run"

# CALIBRATION, not test data. Each number below is a value the third-party
# crate actually returned for the real logs in test/fixtures/.qualification,
# measured first and then frozen. Faker is inapplicable: a generated value
# cannot be an invariant of evidence that already exists on disk.
#
# capability_refused == 5 holds in every log of every run: five capabilities in
# the manufacturing envelope are refused structurally, independent of run
# number or phase. The crate confirms it without ever reading the amp:
# ontology, which makes it the strongest independent assertion available here.
expected_refused_count = 5

# mix_task variant multisets. The rise run1 -> run2 (base 2 -> 3, core 3 -> 4)
# is the idempotency guard flip restated by a third party: on the second
# actuation, tasks that composed the first time are refused admission instead.
expected_variants = %{
  "run1/base" => [
    {["capability_refused"], 5},
    {["task_composed"], 3}
  ],
  "run1/core" => [
    {["capability_refused"], 5},
    {["task_composed"], 4},
    {["task_composed", "task_composed"], 2}
  ],
  "run2/base" => [
    {["capability_refused"], 5},
    {["task_admission_refused"], 2},
    {["task_composed"], 1}
  ],
  "run2/core" => [
    {["capability_refused"], 5},
    {["task_admission_refused"], 3},
    {["task_composed", "task_composed"], 2},
    {["task_composed"], 1}
  ]
}

# num_variants per phase, run1 -> run2. Implied by the multisets above, asserted
# separately because it is the headline claim: a third party sees the flip.
expected_variant_rise = [{"base", 2, 3}, {"core", 3, 4}]

say = fn msg -> IO.puts(:stderr, msg) end

# Order-insensitive comparison: the crate sorts by count desc then trace, but
# the CLAIM is about the multiset, not about the crate's presentation order.
normalize = fn variants ->
  variants
  |> Enum.map(fn %{"activities" => acts, "count" => count} -> {acts, count} end)
  |> Enum.sort()
end

{:ok, _} = Rust4PM.start()

{records, failures} =
  Enum.reduce(inputs, {[], []}, fn {key, path}, {recs, fails} ->
    outcome =
      with {:ok, %{"ocel_handle" => h}} <- Rust4PM.import_ocel_json(File.read!(path)),
           {:ok, stats} <- Rust4PM.ocel_stats(h),
           {:ok, variants} <- Rust4PM.ocel_variants_of_object_type(h, mix_task_object_type),
           {:ok, dfg} <- Rust4PM.ocel_dfg_of_object_type(h, run_object_type) do
        _ = Rust4PM.free_ocel(h)
        {:ok, stats, variants, dfg}
      end

    case outcome do
      {:ok, stats, variants, dfg} ->
        observed_refused = get_in(stats, ["events_per_type", refused_event_type])
        observed_variants = normalize.(variants["variants"])
        num_variants = variants["num_variants"]

        refused_fails =
          if observed_refused == expected_refused_count do
            say.("OK   #{key} events_per_type.#{refused_event_type} == #{expected_refused_count}")
            []
          else
            say.(
              "FAIL #{key} events_per_type.#{refused_event_type} == " <>
                "#{inspect(observed_refused)}, expected #{expected_refused_count}"
            )

            [
              "#{key}: #{refused_event_type} #{inspect(observed_refused)} vs " <>
                "#{expected_refused_count} (log #{path})"
            ]
          end

        variant_fails =
          case Map.fetch(expected_variants, key) do
            {:ok, expected} ->
              sorted = Enum.sort(expected)

              if observed_variants == sorted do
                say.(
                  "OK   #{key} #{mix_task_object_type} variants match " <>
                    "(num_variants=#{num_variants})"
                )

                []
              else
                say.("FAIL #{key} #{mix_task_object_type} variants #{inspect(observed_variants)}")
                say.("     expected #{inspect(sorted)}")

                [
                  "#{key}: #{mix_task_object_type} variants #{inspect(observed_variants)} vs " <>
                    "#{inspect(sorted)} (log #{path})"
                ]
              end

            :error ->
              # A run with no calibrated expectation (e.g. a later ocel-run3).
              # UNKNOWN means NOT EXERCISED: recorded, never quietly passed.
              say.(
                "REC  #{key} #{mix_task_object_type} variants recorded, no calibration " <>
                  "(num_variants=#{num_variants})"
              )

              []
          end

        # The manufacture_run DFG is COMPUTED AND RECORDED BUT NOT ASSERTED.
        # Event timestamps in these logs are tied (2 distinct times across 9
        # events in the base log), so any timestamp-ordered result is currently
        # ordered by an internal index detail no one controls. Asserting edge
        # order would assert something this pipeline does not yet determine.
        # Restore the assertion once the emitter writes distinct timestamps.
        say.("REC  #{key} #{run_object_type} DFG num_edges=#{dfg["num_edges"]} (not asserted)")

        record = %{
          "key" => key,
          "log" => path,
          "engine" => "beam4pm rust4pm wasm (process_mining crate)",
          "stats" => stats,
          "mix_task_variants" => variants,
          "manufacture_run_dfg" => dfg,
          "dfg_asserted" => false,
          "deviations" => refused_fails ++ variant_fails
        }

        {[record | recs], fails ++ refused_fails ++ variant_fails}

      other ->
        say.("FAIL #{key} engine error: #{inspect(other)}")

        record = %{
          "key" => key,
          "log" => path,
          "engine" => "beam4pm rust4pm wasm (process_mining crate)",
          "engine_error" => inspect(other),
          "deviations" => ["#{key}: engine error #{inspect(other)}"]
        }

        {[record | recs], fails ++ ["#{key}: engine error #{inspect(other)} (log #{path})"]}
    end
  end)

records = Enum.reverse(records)

# Every calibrated log must have been present. An oracle that silently checks
# three of four logs is the same defect as one that checks none.
seen = MapSet.new(records, & &1["key"])

missing_fails =
  expected_variants
  |> Map.keys()
  |> Enum.sort()
  |> Enum.reject(&MapSet.member?(seen, &1))
  |> Enum.map(fn key ->
    say.("FAIL #{key} calibrated log absent from the evidence directory")
    "#{key}: calibrated log absent"
  end)

num_variants_by_key =
  records
  |> Enum.filter(&Map.has_key?(&1, "mix_task_variants"))
  |> Map.new(fn r -> {r["key"], r["mix_task_variants"]["num_variants"]} end)

rise_fails =
  Enum.flat_map(expected_variant_rise, fn {phase, want1, want2} ->
    got1 = Map.get(num_variants_by_key, "run1/#{phase}")
    got2 = Map.get(num_variants_by_key, "run2/#{phase}")

    if got1 == want1 and got2 == want2 and got2 > got1 do
      say.("OK   #{phase} mix_task num_variants run1 -> run2 == #{want1} -> #{want2}")
      []
    else
      say.(
        "FAIL #{phase} mix_task num_variants run1 -> run2 == " <>
          "#{inspect(got1)} -> #{inspect(got2)}, expected #{want1} -> #{want2}"
      )

      ["#{phase}: num_variants #{inspect(got1)} -> #{inspect(got2)} vs #{want1} -> #{want2}"]
    end
  end)

File.write!(jsonl_path, Enum.map_join(records, "", &(Jason.encode!(&1) <> "\n")))

all_failures = failures ++ missing_fails ++ rise_fails

if all_failures == [] do
  say.("beam4pm_oracle: PASS -- #{length(records)} logs, all assertions held (third-party engine)")
  System.halt(0)
else
  say.("beam4pm_oracle: FAIL -- #{length(all_failures)} deviation(s):")
  Enum.each(all_failures, fn f -> say.("  - #{f}") end)
  System.halt(1)
end
ELIXIR

# ------------------------------------------------------------ run the engine
# stdout is reserved for the JSONL record stream, so the engine's own compile
# and runtime noise goes to stderr with the verdicts.
rc=0
(
  cd "$BEAM4PM" && \
  ORACLE_JSONL="$JSONL" ORACLE_INPUTS="$INPUTS" mix run "$SCRIPT"
) > "$RUNLOG" 2>&1 || rc=$?

cat "$RUNLOG" >&2
if [ -f "$JSONL" ]; then
  cat "$JSONL"
fi

if [ "$rc" -ne 0 ] && [ ! -s "$JSONL" ]; then
  echo "beam4pm_oracle: engine run failed before any log was analysed (exit $rc)" >&2
fi

exit "$rc"
