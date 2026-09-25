#!/usr/bin/env bash
# G1 origin-guard mutation court (v26.9.25 post-tag hardening).
#
# Usage: scripts/sjira/origin_mutants.sh [REPO_DIR] [REV] [WORK_DIR]
#   REPO_DIR  git repository holding the subject (default: this checkout)
#   REV       exact subject revision (default: HEAD)
#   WORK_DIR  scratch directory (default: mktemp -d); never the checkout
#
# For each [[mutant]] of test/mutants/origin_guard.toml (read from REV, not
# from the working tree) the court:
#   1. re-extracts `git archive REV` over WORK_DIR/tree (a fresh archive:
#      every tracked file restored to the subject bytes);
#   2. replaces `search` (which must occur exactly once in `file`) with
#      `replace` -- otherwise REFUSED(MUTANT_NOT_APPLICABLE);
#   3. runs `mix test <test>` under MIX_ENV=test with MIX_BUILD_ROOT inside
#      WORK_DIR, and records KILLED when the test run exits non-zero.
# The unmutated subject is run first: a failing baseline is
# BLOCKED(BASELINE_RED) and no mutant is judged (admission would be vacuous).
#
# Writes WORK_DIR/origin_mutants.json and prints it. Exit 0 iff every mutant
# is KILLED; 1 on any SURVIVED/REFUSED/BLOCKED; 2 on invalid invocation.
# Never touches REPO_DIR's working tree, index or HEAD. Requires git, tar,
# mix and python3 (stdlib tomllib, Python >= 3.11).
set -euo pipefail

repo="${1:-$(git rev-parse --show-toplevel)}"
rev="${2:-HEAD}"
work="${3:-$(mktemp -d)}"
catalog="test/mutants/origin_guard.toml"

sha="$(git -C "$repo" rev-parse --verify "${rev}^{commit}")" || {
  echo "invalid revision: $rev" >&2
  exit 2
}

mkdir -p "$work/tree" "$work/logs"
export MIX_ENV=test
export MIX_BUILD_ROOT="$work/_build-mutants"

fresh() {
  git -C "$repo" archive "$sha" | tar -x -C "$work/tree"
}

fresh
[ -f "$work/tree/$catalog" ] || {
  echo "catalog $catalog absent at $sha" >&2
  exit 2
}

(cd "$work/tree" && mix deps.get >"$work/logs/deps.log" 2>&1)

ids="$(python3 - "$work/tree/$catalog" <<'PY'
import sys, tomllib
with open(sys.argv[1], "rb") as f:
    for m in tomllib.load(f)["mutant"]:
        print(m["id"])
PY
)"

baseline_test="$(python3 - "$work/tree/$catalog" <<'PY'
import sys, tomllib
with open(sys.argv[1], "rb") as f:
    print(sorted({m["test"] for m in tomllib.load(f)["mutant"]})[0])
PY
)"

results="$work/results.tsv"
: >"$results"

if (cd "$work/tree" && mix test "$baseline_test" >"$work/logs/baseline.log" 2>&1); then
  baseline="GREEN"
else
  baseline="RED"
fi

for id in $ids; do
  fresh
  if python3 - "$work/tree" "$catalog" "$id" <<'PY'
import sys, tomllib, os
root, catalog, wanted = sys.argv[1:4]
with open(os.path.join(root, catalog), "rb") as f:
    mutant = next(m for m in tomllib.load(f)["mutant"] if m["id"] == wanted)
path = os.path.join(root, mutant["file"])
with open(path, encoding="utf-8") as f:
    src = f.read()
if src.count(mutant["search"]) != 1:
    sys.exit(3)
with open(path, "w", encoding="utf-8") as f:
    f.write(src.replace(mutant["search"], mutant["replace"], 1))
PY
  then
    test_file="$(python3 - "$work/tree/$catalog" "$id" <<'PY'
import sys, tomllib
with open(sys.argv[1], "rb") as f:
    print(next(m["test"] for m in tomllib.load(f)["mutant"] if m["id"] == sys.argv[2]))
PY
)"
    if [ "$baseline" = "RED" ]; then
      verdict="BLOCKED(BASELINE_RED)"
    elif (cd "$work/tree" && mix test "$test_file" >"$work/logs/$id.log" 2>&1); then
      verdict="SURVIVED"
    else
      verdict="KILLED"
    fi
  else
    verdict="REFUSED(MUTANT_NOT_APPLICABLE)"
  fi
  printf '%s\t%s\n' "$id" "$verdict" >>"$results"
done

fresh

python3 - "$results" "$sha" "$baseline" "$work/origin_mutants.json" <<'PY'
import json, sys
results, sha, baseline, out = sys.argv[1:5]
rows = [line.rstrip("\n").split("\t") for line in open(results) if line.strip()]
killed = sum(1 for _, v in rows if v == "KILLED")
doc = {
    "schema": "ggen_igniter.origin_mutants/v1",
    "subject_sha": sha,
    "catalog": "test/mutants/origin_guard.toml",
    "baseline": baseline,
    "mutants": [{"id": i, "verdict": v} for i, v in rows],
    "killed": killed,
    "total": len(rows),
    "standing": "ALIVE" if rows and killed == len(rows) and baseline == "GREEN" else "REFUSED",
}
with open(out, "w") as f:
    json.dump(doc, f, indent=2, sort_keys=True)
    f.write("\n")
print(json.dumps(doc, indent=2, sort_keys=True))
sys.exit(0 if doc["standing"] == "ALIVE" else 1)
PY
