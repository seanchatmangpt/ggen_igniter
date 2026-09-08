#!/usr/bin/env bash
# Full qualification run for the ontology -> ggen_igniter -> Igniter/Ash
# manufacturing path, against the book_library fixture.
#
# Acceptance ladder (A..L) -- every rung is an OBSERVED execution, never a
# source inspection or a dry run:
#
#   A  toolchain/deps resolve
#   B  day-zero fixture compiles
#   C  ggen_igniter consumes the ontology and renders the manufacture task
#   D  the real upstream Igniter/Ash tasks are actually invoked (phase base)
#   E  manufactured surfaces compile
#   F  Book + Loan manufactured through the real path (phase core)
#   G  run 2 is semantically idempotent (Igniter --check) AND byte-identical
#   H  OCEL v2 log contains the expected execution path
#   I  conformance: execution followed the admitted process
#   J  machine-readable receipt
#   L  run 3 reaches the SAME state as run 2, on disk AND in the database
#
# WHY RUN 3 EXISTS (rung L)
# Two runs cannot distinguish a fixpoint from a period-2 cycle: a generator
# that alternates between state X and state Y produces T1 != T2 and would be
# caught, but one that alternates a file's CONTENT while leaving run 2 equal
# to run 1 by coincidence would not. T2 == T3 is what makes "fixpoint" a
# claim rather than a hope. Rung L also runs `--check` against the state run
# 3 actually left, and rung G now checks the state run 2 actually left --
# checking only the run-1 state says nothing about where a later run landed.
#
# WHY THE DATABASE IS A SEPARATE ORACLE
# The tree hashes compare FILES. `mix ash.setup` / `mix ash.migrate` mutate
# POSTGRES, and a schema divergence there leaves the tree byte-identical.
# D1/D2/D3 (see bin/db_fingerprint.sql) are the second oracle; without them
# "idempotent" would be a claim about half the manufactured state.
#
# Usage: bash qualify.sh [<fixture-path>]
set -uo pipefail

PACK_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
FIXTURE="${1:-$(cd "$PACK_DIR/../book_library" && pwd)}"
# Evidence lives OUTSIDE the fixture: day_zero.sh removes .ggen_igniter/,
# so a receipt written there would delete itself on the next replay.
OUT="${QUALIFY_OUT:-$(cd "$FIXTURE/.." && pwd)/.qualification/book_library}"
# RUN-SCOPED database. day_zero.sh resets the FILESYSTEM to a known subject,
# but a leftover database from a previous qualification is state too: the
# second run generates migrations with fresh timestamps, `schema_migrations`
# still holds the old versions, and `ash.setup` fails with
# `relation "books" already exists`. Reproduced before this was fixed.
#
# Each run therefore addresses its own database rather than dropping anyone
# else's -- isolation by naming, not by a destructive operation. Old
# qualification databases are left on disk deliberately; drop them yourself
# if you want the space.
RUN_ID="${QUALIFY_RUN_ID:-$(date -u +%Y%m%d%H%M%S)}"
DB_NAME="${BOOK_LIBRARY_QUAL_DB:-book_library_qual_$RUN_ID}"
DB_DEV_NAME="${DB_NAME}_dev"

rm -rf "$OUT"
mkdir -p "$OUT"
: > "$OUT/commands.log"
: > "$OUT/steps.jsonl"

STEP_N=0
FAILED=0

# run <rung> <label> <expected-exit> <cmd...>
run() {
  local rung="$1" label="$2" expect="$3"; shift 3
  STEP_N=$((STEP_N + 1))
  local id
  id="$(printf '%02d' "$STEP_N")-$label"
  echo "=== [$rung] $label :: $* ===" | tee -a "$OUT/commands.log"
  ( cd "$FIXTURE" && "$@" ) > "$OUT/$id.log" 2>&1
  local code=$?
  echo "exit=$code (expected $expect)" | tee -a "$OUT/commands.log"
  printf '{"rung":"%s","label":"%s","command":"%s","exit":%d,"expected":%d,"log":"%s"}\n' \
    "$rung" "$label" "$(printf '%s ' "$@" | sed 's/"/\\"/g')" "$code" "$expect" "$id.log" \
    >> "$OUT/steps.jsonl"
  if [ "$code" -ne "$expect" ]; then
    echo "!! [$rung] $label FAILED (exit $code, expected $expect) -- see $OUT/$id.log"
    FAILED=1
  fi
  return $code
}

# Byte-level manifest of the MANUFACTURED tree.
#
# `test/support` is hashed because day_zero.sh:32 deletes it as a
# manufactured path -- `mix ash.gen.domain` regenerates data_case.ex -- so
# leaving it out meant a manufactured file was compared by no oracle at all.
# `test/support` specifically, NOT all of `test`: hand-written fixture tests
# live under test/book_library/ and are SOURCE, not output. Hashing them
# would turn every edit to a test into a false idempotency failure.
#
# Deliberately excluded, each for a reason that is not "it was inconvenient":
#   mix.lock       -- resolved dependency versions, an INPUT to manufacture.
#                     Recorded instead under toolchain.deps in the receipt.
#   _build/        -- compiler output, not manufactured source; contains
#                     absolute paths and beam timestamps.
#   .ggen_igniter/ -- evidence, not product: an append-only receipts jsonl
#                     that grows by one row every run, OCEL logs stamped with
#                     fresh wall-clock times, and a manifest.json carrying
#                     absolute paths and an updated_at. Hashing it would make
#                     T1 != T2 by construction and destroy the oracle.
tree_hash() {
  ( cd "$FIXTURE" && \
    find lib priv config test/support mix.exs .formatter.exs -type f 2>/dev/null \
      | LC_ALL=C sort \
      | xargs shasum -a 256 ) > "$1"
}

# Structural fingerprint of the run-scoped database. See bin/db_fingerprint.sql
# for what is projected and why. Records its own exit code as a step so a
# capture failure is a visible FAILURE rather than a silently short file.
# The D-file itself is the step's log, so no numbered NN-*.log is written and
# STEP_N is deliberately not advanced -- a phantom number with no file behind
# it would break the correspondence between step numbers and $OUT contents.
db_fingerprint() { # <rung> <label> <out-file>
  PGPASSWORD="${QUALIFY_PGPASSWORD:-postgres}" \
    psql -q -h "${QUALIFY_PGHOST:-localhost}" -U "${QUALIFY_PGUSER:-postgres}" \
         -d "$DB_DEV_NAME" -f "$PACK_DIR/bin/db_fingerprint.sql" > "$3" 2>&1
  local code=$?
  echo "=== [$1] $2 :: exit=$code (expected 0) -> $(basename "$3") ===" | tee -a "$OUT/commands.log"
  printf '{"rung":"%s","label":"%s","command":"psql -f db_fingerprint.sql %s","exit":%d,"expected":0,"log":"%s"}\n' \
    "$1" "$2" "$DB_DEV_NAME" "$code" "$(basename "$3")" >> "$OUT/steps.jsonl"
  [ "$code" -eq 0 ] || { echo "!! [$1] $2 FAILED -- see $3"; FAILED=1; }
}

# Diff two database fingerprints. Separate from the capture so a diff that
# passes because BOTH captures failed is still preceded by two failed steps.
db_diff() { # <rung> <label> <a> <b> <out-diff>
  if diff -u "$3" "$4" > "$5"; then
    echo "=== [$1] $2 :: identical ===" | tee -a "$OUT/commands.log"
    printf '{"rung":"%s","label":"%s","command":"diff %s %s","exit":0,"expected":0,"log":"%s"}\n' \
      "$1" "$2" "$(basename "$3")" "$(basename "$4")" "$(basename "$5")" >> "$OUT/steps.jsonl"
  else
    echo "!! [$1] $2 DIFFERS -- see $5"
    printf '{"rung":"%s","label":"%s","command":"diff %s %s","exit":1,"expected":0,"log":"%s"}\n' \
      "$1" "$2" "$(basename "$3")" "$(basename "$4")" "$(basename "$5")" >> "$OUT/steps.jsonl"
    FAILED=1
  fi
}

# NON-DEGENERACY. Without this, the database oracle is worthless: a psql
# connection failure writes the SAME error text to every D-file, so
# `diff D1 D2` reports no difference and every later comparison passes
# vacuously. Reproduced against a nonexistent database before this check was
# written -- two captures exit 2 and are byte-identical:
#   psql: error: connection to server at "localhost" (127.0.0.1), port 5432
#   failed: FATAL:  database "..." does not exist
#
# So assert that D1 has POSITIVE CONTENT of the expected shape: COLUMN rows
# for exactly the manufactured tables, and at least one applied migration.
# The table names are an upstream CONTRACT of this fixture's ontology (Book
# and Loan resources -> `books` and `loans`), not test data, so they are
# literals on purpose.
db_nondegenerate() { # <rung> <d1-file>
  STEP_N=$((STEP_N + 1))
  local id; id="$(printf '%02d' "$STEP_N")-db-nondegenerate"
  local tables migrations code=0
  local rung="$1"; shift
  tables="$(grep '^COLUMN|' "$1" 2>/dev/null | cut -d'|' -f2 | LC_ALL=C sort -u | paste -sd, -)"
  migrations="$(grep -c '^MIGRATION|' "$1" 2>/dev/null || true)"
  {
    echo "tables_with_columns=$tables"
    echo "migration_rows=$migrations"
  } > "$OUT/$id.log"
  [ "$tables" = "books,loans" ] || {
    echo "!! [$rung] db-nondegenerate: expected COLUMN rows for exactly books,loans -- got '$tables'"
    code=1
  }
  [ "${migrations:-0}" -ge 1 ] || {
    echo "!! [$rung] db-nondegenerate: no MIGRATION rows -- the capture is not a real schema"
    code=1
  }
  echo "=== [$rung] db-nondegenerate :: exit=$code (expected 0) tables=$tables migrations=$migrations ===" \
    | tee -a "$OUT/commands.log"
  printf '{"rung":"%s","label":"db-nondegenerate","command":"assert D1 has books,loans columns and >=1 migration","exit":%d,"expected":0,"log":"%s"}\n' \
    "$rung" "$code" "$id.log" >> "$OUT/steps.jsonl"
  [ "$code" -eq 0 ] || FAILED=1
}

# ---------------------------------------------------------------- A: day zero
echo "### resetting fixture to day zero"
bash "$PACK_DIR/bin/day_zero.sh" "$FIXTURE" > "$OUT/00-day-zero.log" 2>&1
run A deps-get 0 mix deps.get

# ------------------------------------------------------------- B: baseline
run B baseline-compile 0 mix compile
tree_hash "$OUT/T0-day-zero.sha256"

# ------------------------------------------- C: ontology -> manufacture task
run C ggen-sync 0 mix ggen_igniter.sync --pack-dir "$PACK_DIR"
run C compile-manufacture-task 0 mix compile

# C2 -- ontology <-> generated-invocation drift. Runs in BOTH directions, so
# a hand-edit of the rendered task is caught as loudly as a fact that stopped
# being projected. Falsified before being trusted: injecting an extra
# `--attribute` with no ontology fact behind it, and deleting a projected
# fact, each produce exit 1 with the specific item named.
run C drift-check 0 python3 "$PACK_DIR/bin/drift_check.py" "$PACK_DIR" \
  lib/mix/tasks/book_library.manufacture.ex

# C3 -- every amp:evidence citation in the ontology must resolve to a real
# file (and a real line range) in the resolved dependency source. An
# adversarial review found a dangling citation that nothing caught, because
# 080_capabilities.rq selects ?evidence without ever resolving it.
run C evidence-citations 0 python3 "$PACK_DIR/bin/evidence_check.py" "$PACK_DIR" "$FIXTURE"

# --------------------------------------------------- D: phase base (run 1)
run D manufacture-base-run1 0 mix book_library.manufacture --phase base --yes
run E compile-after-base 0 mix compile
# Capture the REAL compile exit. Sealing with a hardcoded zero made the seal
# a copy of the harness's intent rather than a second record of the outcome:
# it could not disagree with the run, so it could not falsify it.
BASE_COMPILE_EXIT=$?

# --------------------------------------------------- database isolation
# Blocker: a filesystem-disposable copy that still points at the ORIGINAL
# database is not isolated. Rewrite the manufactured repo config so every
# database-touching lifecycle step below addresses a run-scoped database,
# and prove the rewrite landed.
# Both Mix envs, not just dev: see bin/isolate_db.py for the two observed
# defects this closes. Run as a real rung so a failed isolation stops the
# qualification instead of quietly producing a run against a shared database.
run F isolate-databases 0 python3 "$PACK_DIR/bin/isolate_db.py" "$FIXTURE" "$DB_NAME"

grep -n 'database:' "$FIXTURE/config/dev.exs" "$FIXTURE/config/test.exs" \
  > "$OUT/db-isolation.txt" 2>&1
echo "$DB_NAME" > "$OUT/db-name.txt"
echo "$RUN_ID" > "$OUT/run-id.txt"

# --------------------------------------------------- F: phase core (run 1)
run F manufacture-core-run1 0 mix book_library.manufacture --phase core --yes
run F compile-after-core 0 mix compile
CORE_COMPILE_EXIT=$?

# The manufacture task emits its OCEL decisions from inside `igniter/1`,
# which runs BEFORE Igniter applies anything -- so an aborted run would
# otherwise leave a log asserting composition of files that never landed.
# Seal each log with the outcome the harness actually observed; conformance
# treats an unsealed log as non-conformant.
run F seal-ocel-base 0 mix ggen_igniter.ocel.seal \
  .ggen_igniter/ocel/book_library.manufacture.base.ocel.json --exit "$BASE_COMPILE_EXIT" \
  --observed "phase base applied; mix compile exit $BASE_COMPILE_EXIT"
run F seal-ocel-core 0 mix ggen_igniter.ocel.seal \
  .ggen_igniter/ocel/book_library.manufacture.core.ocel.json --exit "$CORE_COMPILE_EXIT" \
  --observed "phase core applied; mix compile exit $CORE_COMPILE_EXIT"

# --------------------------------------------------- lifecycle (real DB)
# NOTE: `--yes` is deliberately NOT passed. `mix ash.codegen` is a plain
# Mix.Task (ash.codegen.ex:36) that forwards its argv verbatim to each
# extension's codegen; AshPostgres routes to ash_postgres.generate_migrations,
# an Igniter task whose Info declares no `yes` switch, so strict validation
# rejects it with `--yes : Unknown option`. Reproduced in run 1 of this
# harness before the flag was removed.
run F ash-codegen 0 mix ash.codegen --name book_library_manufacture
run F ash-setup 0 mix ash.setup

# D1 -- the database as run 1 left it. Captured BEFORE any second lifecycle
# step, so D2/D3 have something to be compared against. Non-degeneracy runs
# immediately: every later db_diff is only meaningful if D1 is a real schema.
db_fingerprint F db-fingerprint-D1 "$OUT/D1-run1.txt"
db_nondegenerate F "$OUT/D1-run1.txt"

run F compile-after-lifecycle 0 mix compile

# ---------------------------------------------- M: RUN the manufactured code
# Every rung above this one proves that files are GENERATED, that they COMPILE,
# and that the schema matches the ontology. None of them proves the
# manufactured system WORKS -- no manufactured Ash action had ever been called,
# so no row had ever been written through one.
#
# These tests live in the fixture (test/book_library/**/*_exec.exs) and are
# hand-written on purpose: they are the falsifier for the manufactured code,
# not manufactured output themselves. day_zero.sh deliberately does not remove
# them; it removes test/support, which `mix ash_postgres.install` regenerates.
#
# The `_exec.exs` suffix is load-bearing. This fixture sits inside the parent
# repo's test/ tree, and named `*_test.exs` these files were collected by
# ggen_igniter's OWN suite -- where BookLibrary.DataCase does not exist -- and
# broke it with a CompileError. The fixture sets
# `test_load_filters: [&String.ends_with?(&1, "_exec.exs")]` so it finds them
# and the parent never does.
run M ash-setup-test-env 0 env MIX_ENV=test mix ash.setup
run M manufactured-resources-execute 0 mix test

tree_hash "$OUT/T1-run1.sha256"
rm -rf "$OUT/ocel-run1"
mkdir -p "$OUT/ocel-run1"
cp -R "$FIXTURE/.ggen_igniter/ocel/"* "$OUT/ocel-run1/" 2>/dev/null || true

# ------------------------------------------------ G: idempotency (run 2)
# G1 -- Igniter's OWN oracle. --check halts non-zero on ANY change, warning,
# issue, queued task, move or removal. Exit 0 is the semantic assertion;
# a bare exit code from a normal run would NOT be (issues exit 0).
run G idempotency-check-base 0 mix book_library.manufacture --phase base --check
run G idempotency-check-core 0 mix book_library.manufacture --phase core --check

# G2 -- a real second actuation, then a byte-level tree comparison.
run G manufacture-base-run2 0 mix book_library.manufacture --phase base --yes
run G manufacture-core-run2 0 mix book_library.manufacture --phase core --yes
run G ash-codegen-run2 0 mix ash.codegen --name book_library_manufacture
run G compile-after-run2 0 mix compile
RUN2_COMPILE_EXIT=$?

# G3 -- the DATABASE half of idempotency. `mix ash.setup` ran exactly once in
# run 1, so nothing had ever re-entered the lifecycle: DB idempotency was
# entirely unproven while the standing already claimed it. Re-running is safe
# by construction -- AshPostgres setup is create+migrate, and ecto.create's
# already-existing branch is an `info` message with no raise
# (deps/ecto/lib/mix/tasks/ecto.create.ex:79-82), so exit 0.
run G ash-setup-run2 0 mix ash.setup
db_fingerprint G db-fingerprint-D2 "$OUT/D2-run2.txt"
db_diff G db-diff-D1-D2 "$OUT/D1-run1.txt" "$OUT/D2-run2.txt" "$OUT/D1-vs-D2.diff"

run G seal-ocel-base-run2 0 mix ggen_igniter.ocel.seal \
  .ggen_igniter/ocel/book_library.manufacture.base.ocel.json --exit "$RUN2_COMPILE_EXIT" \
  --observed "phase base re-applied; mix compile exit $RUN2_COMPILE_EXIT"
run G seal-ocel-core-run2 0 mix ggen_igniter.ocel.seal \
  .ggen_igniter/ocel/book_library.manufacture.core.ocel.json --exit "$RUN2_COMPILE_EXIT" \
  --observed "phase core re-applied; mix compile exit $RUN2_COMPILE_EXIT"

tree_hash "$OUT/T2-run2.sha256"
if diff -u "$OUT/T1-run1.sha256" "$OUT/T2-run2.sha256" > "$OUT/T1-vs-T2.diff"; then
  echo "IDEMPOTENT: T1 == T2 (byte-identical tree)" | tee -a "$OUT/commands.log"
  echo '{"rung":"G","label":"tree-diff-T1-T2","command":"diff T1 T2","exit":0,"expected":0,"log":"T1-vs-T2.diff"}' >> "$OUT/steps.jsonl"
else
  echo "!! [G] T1 != T2 -- see $OUT/T1-vs-T2.diff"
  echo '{"rung":"G","label":"tree-diff-T1-T2","command":"diff T1 T2","exit":1,"expected":0,"log":"T1-vs-T2.diff"}' >> "$OUT/steps.jsonl"
  FAILED=1
fi

rm -rf "$OUT/ocel-run2"
mkdir -p "$OUT/ocel-run2"
cp -R "$FIXTURE/.ggen_igniter/ocel/"* "$OUT/ocel-run2/" 2>/dev/null || true
export OCEL_GLOB="$OUT/ocel-run1/*.ocel.json"

# G4 -- `--check` against the state run 2 ACTUALLY LEFT. The checks above ran
# at the T1 state; passing there says nothing about where run 2 landed. Safe
# to run here: run-2 OCEL is already copied to $OUT above, and `--check`
# writes no log at all (templates/manufacture.ex.eex:425-426 gates
# maybe_write_ocel on `!options[:check]`).
run G idempotency-check-base-at-T2 0 mix book_library.manufacture --phase base --check
run G idempotency-check-core-at-T2 0 mix book_library.manufacture --phase core --check

# ------------------------------------------------- L: fixpoint (run 3)
# A third actuation. T1 == T2 alone is consistent with a period-2 cycle;
# T2 == T3 is what makes "fixpoint" a claim rather than a hope. This block
# runs strictly AFTER ocel-run2 is copied, so run 3 cannot overwrite the
# evidence conformance.py reads (it consumes $OUT/ocel-run{1,2} only,
# conformance.py:104-105 -- never the fixture's live logs).
run L manufacture-base-run3 0 mix book_library.manufacture --phase base --yes
run L manufacture-core-run3 0 mix book_library.manufacture --phase core --yes
run L ash-codegen-run3 0 mix ash.codegen --name book_library_manufacture
run L compile-after-run3 0 mix compile
RUN3_COMPILE_EXIT=$?
run L seal-ocel-base-run3 0 mix ggen_igniter.ocel.seal \
  .ggen_igniter/ocel/book_library.manufacture.base.ocel.json --exit "$RUN3_COMPILE_EXIT" \
  --observed "phase base re-applied (run 3); mix compile exit $RUN3_COMPILE_EXIT"
run L seal-ocel-core-run3 0 mix ggen_igniter.ocel.seal \
  .ggen_igniter/ocel/book_library.manufacture.core.ocel.json --exit "$RUN3_COMPILE_EXIT" \
  --observed "phase core re-applied (run 3); mix compile exit $RUN3_COMPILE_EXIT"
rm -rf "$OUT/ocel-run3"
mkdir -p "$OUT/ocel-run3"
cp -R "$FIXTURE/.ggen_igniter/ocel/"* "$OUT/ocel-run3/" 2>/dev/null || true

# `ash.migrate` rather than `ash.setup` here: the database already exists, so
# this exercises the MIGRATE half on its own. If run-3 codegen emitted a
# migration for an unchanged resource, this applies it and D3 diverges from
# D2 -- the tree oracle would catch the new file, and this catches the
# schema change it caused.
run L ash-migrate-run3 0 mix ash.migrate
db_fingerprint L db-fingerprint-D3 "$OUT/D3-run3.txt"
db_diff L db-diff-D2-D3 "$OUT/D2-run2.txt" "$OUT/D3-run3.txt" "$OUT/D2-vs-D3.diff"

tree_hash "$OUT/T3-run3.sha256"
if diff -u "$OUT/T2-run2.sha256" "$OUT/T3-run3.sha256" > "$OUT/T2-vs-T3.diff"; then
  echo "FIXPOINT: T2 == T3 (byte-identical tree)" | tee -a "$OUT/commands.log"
  echo '{"rung":"L","label":"tree-diff-T2-T3","command":"diff T2 T3","exit":0,"expected":0,"log":"T2-vs-T3.diff"}' >> "$OUT/steps.jsonl"
else
  echo "!! [L] T2 != T3 -- see $OUT/T2-vs-T3.diff"
  echo '{"rung":"L","label":"tree-diff-T2-T3","command":"diff T2 T3","exit":1,"expected":0,"log":"T2-vs-T3.diff"}' >> "$OUT/steps.jsonl"
  FAILED=1
fi

run L idempotency-check-base-at-T3 0 mix book_library.manufacture --phase base --check
run L idempotency-check-core-at-T3 0 mix book_library.manufacture --phase core --check

# --------------------------------- guard: agent hand-write refusal is live
# The guard's standing must come from RUNNING it, not from reading it. Two
# block cases and two allow cases, each asserted on the real exit code.
GUARD="$(cd "$PACK_DIR/../../.." && pwd)/.claude/hooks/refuse-handwritten-ash.sh"
# Exercised through the REAL PreToolUse protocol: a JSON tool call on
# STDIN. An earlier revision of this harness drove the guard through
# CLAUDE_FILE_PATH/CLAUDE_TOOL_INPUT env vars only -- a code path the hook
# runner does not use -- so the guard FAILED OPEN in production while its
# qualification cases passed. Testing the wrong interface is worse than not
# testing at all, because it produces a standing.
guard_case() { # <label> <expected-exit> <path> <content>
  STEP_N=$((STEP_N + 1))
  local id; id="$(printf '%02d' "$STEP_N")-guard-$1"
  python3 -c 'import json,sys; print(json.dumps({"tool_name":"Write","tool_input":{"file_path":sys.argv[1],"content":sys.argv[2]}}))' \
    "$3" "$4" | bash "$GUARD" > "$OUT/$id.log" 2>&1
  local code=$?
  printf '{"rung":"K","label":"guard-%s","command":"refuse-handwritten-ash.sh %s","exit":%d,"expected":%d,"log":"%s"}\n' \
    "$1" "$3" "$code" "$2" "$id.log" >> "$OUT/steps.jsonl"
  echo "=== [K] guard-$1 :: exit=$code (expected $2) ===" | tee -a "$OUT/commands.log"
  [ "$code" -eq "$2" ] || { echo "!! [K] guard-$1 FAILED"; FAILED=1; }
}
guard_case blocks-ash-resource 2 "$FIXTURE/lib/book_library/catalog/handwritten.ex" \
  'defmodule BookLibrary.Catalog.Handwritten do
  use Ash.Resource, domain: BookLibrary.Catalog
end'
guard_case blocks-base-resource-header 2 "$FIXTURE/lib/book_library/catalog/handwritten.ex" \
  'use BookLibrary.Resource, otp_app: :book_library, domain: BookLibrary.Catalog'
guard_case allows-plain-elixir 0 "$FIXTURE/lib/book_library/plain.ex" \
  'defmodule BookLibrary.Plain do
  def hello, do: :world
end'
guard_case allows-manufactured-task 0 "$FIXTURE/lib/mix/tasks/book_library.manufacture.ex" \
  'use Ash.Resource'

# ------------------------------- H2: real OCEL import into beam4pm
# The compatibility claim is only worth anything if beam4pm's REAL importer
# accepts the document. Asserting it from the shape of a fixture the same
# author read is a closed loop. Skipped -- loudly, never silently -- when
# beam4pm or its wasm artifact is absent.
BEAM4PM="${BEAM4PM_DIR:-$HOME/beam4pm}"
WASM="$BEAM4PM/native/rust4pm-wasm/target/wasm32-wasip1/release/rust4pm_wasm.wasm"
if [ -f "$WASM" ]; then
  STEP_N=$((STEP_N + 1))
  id="$(printf '%02d' "$STEP_N")-beam4pm-import"
  ( cd "$BEAM4PM" && mix run -e '
    {:ok, _} = BeamPM.Rust4PM.start()
    Path.wildcard(System.get_env("OCEL_GLOB"))
    |> Enum.each(fn p ->
      {:ok, %{"ocel_handle" => h}} = BeamPM.Rust4PM.import_ocel_json(File.read!(p))
      IO.puts("IMPORTED #{Path.basename(p)} -> ocel_handle #{h}")
    end)
  ' ) > "$OUT/$id.log" 2>&1
  code=$?
  echo "=== [H] beam4pm-import :: exit=$code (expected 0) ===" | tee -a "$OUT/commands.log"
  printf '{"rung":"H","label":"beam4pm-import","command":"BeamPM.Rust4PM.import_ocel_json/2","exit":%d,"expected":0,"log":"%s"}\n' \
    "$code" "$id.log" >> "$OUT/steps.jsonl"
  [ "$code" -eq 0 ] || { echo "!! [H] beam4pm-import FAILED"; FAILED=1; }
else
  echo "SKIPPED beam4pm-import: no wasm artifact at $WASM" | tee -a "$OUT/commands.log"
  printf '{"rung":"H","label":"beam4pm-import","command":"SKIPPED","exit":null,"expected":0,"log":"none","skipped_reason":"wasm artifact absent at %s"}\n' \
    "$WASM" >> "$OUT/steps.jsonl"
fi

# ------------------------------------------------- H/I: OCEL + conformance
python3 "$PACK_DIR/bin/drift_check.py" "$PACK_DIR" \
  "$FIXTURE/lib/mix/tasks/book_library.manufacture.ex" > "$OUT/drift.json" 2>&1

python3 "$PACK_DIR/bin/conformance.py" "$FIXTURE" "$OUT" > "$OUT/conformance.json" 2>"$OUT/conformance.err"
CONF=$?
if [ $CONF -ne 0 ]; then
  echo "!! [I] conformance check failed -- see $OUT/conformance.err"
  FAILED=1
fi

# --------------------------------------------------------- J: receipt
# The ladder advertised rung J from the start but never ran it, so the
# shipped receipt.json was written by hand -- its mtime was a minute later
# than every other artifact in the directory, which is exactly what a
# hand-run leaves behind. A receipt produced by a separate manual step is
# not evidence OF the run; it is a second, unverified account of it.
#
# A nonzero exit from receipt.py is NOT an extra fault: it returns 1 exactly
# when the run it reports already contains failures, which $FAILED has
# already recorded. Only an unwritable receipt is a fault of its own.
#
# No steps.jsonl row is appended for this step, on purpose. steps.jsonl is
# the list the receipt SUMMARISES; a row for the receipt itself could never
# appear in the receipt that reports it, so re-running receipt.py by hand
# would yield a different `commands` list than the shipped one -- the exact
# drift this rung exists to remove.
python3 "$PACK_DIR/bin/receipt.py" "$FIXTURE" "$OUT" > "$OUT/receipt.json" 2>"$OUT/receipt.err"
RECEIPT_WRITE=$?
echo "=== [J] receipt :: exit=$RECEIPT_WRITE (echoes run status; 1 iff steps failed) ===" \
  | tee -a "$OUT/commands.log"
if [ ! -s "$OUT/receipt.json" ]; then
  echo "!! [J] receipt.py wrote no receipt (exit $RECEIPT_WRITE) -- see $OUT/receipt.err"
  FAILED=1
fi

echo
echo "=================================================================="
if [ $FAILED -eq 0 ]; then
  echo "QUALIFICATION: all rungs passed"
else
  echo "QUALIFICATION: FAILURES PRESENT (see $OUT/steps.jsonl)"
fi
echo "artifacts: $OUT"
exit $FAILED
