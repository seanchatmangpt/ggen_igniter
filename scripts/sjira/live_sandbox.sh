#!/usr/bin/env bash
# Hands-free sealed live sandbox for sjira-loop (no HITL, no real-repo mutate).
#
# Manufactures an ephemeral git target + pack stamp, admits one EXEC-SANDBOX
# work order whose base_sha matches the target HEAD, then runs
# scripts/sjira/autonomic_loop.sh --live with all required env set.
#
# Ceiling: local execute → PARTIAL_ALIVE (honest; ALIVE is xaas-fabric-only).
# Fail-closed: any hop ≠ 0 exits non-zero; never prompts; never non-loopback.
#
# Usage (from ggen_igniter root, or via `just sjira-loop-live-sandbox`):
#   scripts/sjira/live_sandbox.sh
#   SJIRA_OUT_DIR=/path scripts/sjira/live_sandbox.sh
set -euo pipefail

here=$(cd "$(dirname "$0")" && pwd)
gi=${GGEN_IGNITER_DIR:-$(cd "$here/../.." && pwd)}
cd "$gi"
[ -f mix.exs ] || { echo "INVALID: not ggen_igniter root: $gi" >&2; exit 2; }

pack_src=${SJIRA_SANDBOX_PACK:-"$gi/test/fixtures/semantic_jira/live_sandbox_pack"}
[ -d "$pack_src" ] || { echo "INVALID: missing sealed pack: $pack_src" >&2; exit 2; }
[ -f "$pack_src/gates/010_ci.rq" ] || {
  echo "INVALID: sealed pack missing gates/010_ci.rq" >&2
  exit 2
}

out_dir=${SJIRA_OUT_DIR:-$(mktemp -d "${TMPDIR:-/tmp}/sjira-live-sandbox.XXXXXX")}
mkdir -p "$out_dir"
sandbox_root="$out_dir/sandbox"
pack_dir="$sandbox_root/pack"
target_dir="$sandbox_root/target"
ledger="$out_dir/ledger.jsonl"
candidates="$out_dir/candidates.jsonl"

rm -rf "$sandbox_root"
mkdir -p "$pack_dir" "$target_dir"
# Copy sealed pack into sandbox (never mutate the fixture in-place).
cp -R "$pack_src"/. "$pack_dir"/
# Strip docs from runtime pack tree (digest must be manufacture inputs only).
rm -f "$pack_dir/README.md"

# Ephemeral git target at a known HEAD (base_sha pin).
git -C "$target_dir" init -q
git -C "$target_dir" config user.email "sjira-live-sandbox@example.invalid"
git -C "$target_dir" config user.name "sjira live sandbox"
git -C "$target_dir" config commit.gpgsign false
printf 'sjira live sandbox base\n' >"$target_dir/README"
git -C "$target_dir" add README
git -C "$target_dir" commit -q -m "base"
head=$(git -C "$target_dir" rev-parse HEAD)

# Stamp pack digest onto target (same law as execute OS court).
MIX_ENV="${MIX_ENV:-test}" mix run -e "
pack = \"$pack_dir\"
target = \"$target_dir\"
{:ok, digest} = GgenIgniter.PackLock.digest_checked(pack)
:ok = GgenIgniter.SemanticJira.TargetPack.write_stamp!(target, %{\"pack\" => digest})
IO.puts(\"stamp_ok digest=\" <> digest)
" >/dev/null

# One admitted-shape candidate: court stem matches gates/010_ci.rq → "ci".
python3 - "$candidates" "$head" <<'PY'
import json, sys
path, head = sys.argv[1], sys.argv[2]
order = {
    "identity": "EXEC-SANDBOX-1",
    "title": "Hands-free live sandbox execute (PARTIAL_ALIVE ceiling)",
    "description": "Sealed pack manufacture at the ephemeral target HEAD.",
    "subject": "sjira:live-sandbox:subject",
    "repository": "seanchatmangpt/ggen_igniter",
    "base_sha": head,
    "standing": "UNKNOWN",
    "evidence_ceiling": "repository-local",
    "promotion_rule": "Standing advances only from an exact-head fabric receipt.",
    "replay_identity": "sjira:live-sandbox:EXEC-SANDBOX-1",
    "required_courts": ["ci"],
    "required_evidence": ["verification"],
    "acceptance": ["urn:semantic-jira:acceptance:EXEC-SANDBOX-1:a1"],
    "falsifiers": ["urn:semantic-jira:falsifier:EXEC-SANDBOX-1:f1"],
    "projections": ["jira"],
    "origin_authority": "https://ggen-igniter.dev/ontology/semantic-jira#objective-code-work-authority",
    "dependencies": [],
    "target_pack": "pack",
    "path_scope": ["lib"],
}
with open(path, "w", encoding="utf-8") as f:
    f.write(json.dumps(order, separators=(",", ":")) + "\n")
print(f"candidate identity=EXEC-SANDBOX-1 base_sha={head}")
PY

export SJIRA_OUT_DIR="$out_dir"
export SJIRA_LEDGER="$ledger"
export SJIRA_CANDIDATES="$candidates"
export SJIRA_PACK_DIR="$pack_dir"
export SJIRA_TARGET_DIR="$target_dir"
export SJIRA_RECEIPTS_DIR="$out_dir/receipts"
export SJIRA_VERIFIER_SUITE="ci"
export SJIRA_ALIAS="seanchatmangpt/ggen_igniter=target"
export SJIRA_IDENTITY="EXEC-SANDBOX-1"
export GGEN_IGNITER_DIR="$gi"
# Twin cross-check on live is optional; enable when GGEN_BIN is healthy.
export SJIRA_HANDS_FREE_CROSSCHECK="${SJIRA_HANDS_FREE_CROSSCHECK:-0}"

mkdir -p "$SJIRA_RECEIPTS_DIR"
echo "== sjira-live-sandbox out=$out_dir pack=$pack_dir target=$target_dir head=$head"
exec bash "$here/autonomic_loop.sh" --live
