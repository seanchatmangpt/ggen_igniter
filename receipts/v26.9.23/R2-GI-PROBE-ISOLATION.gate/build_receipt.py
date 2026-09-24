#!/usr/bin/env python3
"""Emit receipts/v26.9.23/R2-GI-PROBE-ISOLATION.json from the committed gate-dir logs.

usage: build_receipt.py <worktree> <full_suite_exit> <full_suite_summary> <hosted_json> [<hosted_json_head>]
hosted_json: JSON object {run_id, head_sha, status, conclusion, summary} for the product commit's push run;
hosted_json_head: the same shape for the push run on the continuation gate head (F1g), when present.

F1g continuation (2026-09-23, after the usage-limit halt): friday/gc-fri-0800 did not move (d6a6e5b is
still the merge-base), so no merge-forward; the lane gate was re-run on the committed head HEAD_GATE and
the receipt now binds that head (the product commit SUBJ is its ancestor; SUBJ..HEAD_GATE adds only this
gate dir, the receipt JSON and one HANDWRITTEN.md row, none of which a test, lib/ module or court reads).
"""
import hashlib
import json
import sys
from pathlib import Path

wt = Path(sys.argv[1])
full_exit = int(sys.argv[2])
full_summary = sys.argv[3]
hosted = json.loads(sys.argv[4])
hosted_head = json.loads(sys.argv[5]) if len(sys.argv) > 5 else None

LANE = "R2-GI-PROBE-ISOLATION"
G = f"receipts/v26.9.23/{LANE}.gate"
PIN = ("PATH=/Users/sac/.asdf/installs/elixir/1.18.4-otp-27/bin:"
       "/Users/sac/.asdf/installs/erlang/27.2.4/bin:$PATH")
BASE = "d6a6e5bd8de1da426ddc26130edfa45bbaf24f61"
SUBJ = "0fd8095c96e2ec6fe30a6b62f2b12b1772098b1b"
HEAD_GATE = "6c335f0da3c2a1d9e7d57729b9a667973bf3f1b0"
WT = str(wt)
GATE = "sh /Users/sac/wt/v26922/v26923/lanes/r2/gates/r2-gi-probe-isolation.sh \"$PWD\""


def sha(rel):
    return hashlib.sha256((wt / rel).read_bytes()).hexdigest()


def cmd(c, exit_, summary, log, role, cwd=WT):
    d = {"cmd": c, "cwd": cwd, "exit": exit_, "summary": summary, "log": log, "role": role}
    if log:
        d["output_sha256"] = sha(log)
    return d


gate_sha = sha(f"{G}/r2-gi-probe-isolation.sh")
assert gate_sha == "04b87f58eea52792270be4592b9deecdcf76e29d08ca1f3adb4dd1b555312946", gate_sha
cand_sha = sha(f"{G}/candidate-r2-gi-probe-isolation.patch")
assert cand_sha == "6e61bfd4d92e812f3eba224bd922067d744ce7afb5f9bd24913ec935870e9513", cand_sha

commands = [
    cmd(GATE, 0,
        "F1g CONTINUATION LANE GATE on committed lane head 6c335f0 (gate script sha256 " + gate_sha + "; "
        "friday/gc-fri-0800 = origin/friday/gc-fri-0800 = d6a6e5b = merge-base, so no merge-forward): "
        "Elixir 1.18.4 (compiled with Erlang/OTP 27); format ok; credo 1 mods/funs, found no issues; "
        "seeds 0/648358/1/2 each '10 tests, 0 failures' (24.4s/24.3s/91.0s/38.6s); lib/ porcelain empty; "
        "PROBE_ISOLATION_GATE OK; GATE_EXIT=0",
        f"{G}/12-gate-head-6c335f0.log", "lane gate on committed head (F1g continuation)"),
    cmd(PIN + " sh -c 'git merge-base --is-ancestor friday/gc-fri-0800 HEAD; ls _build/dev/lib/ggen_igniter/ebin "
        "| grep -c Ex4pm; mix ggen_igniter.plan --help | head -1; git status --porcelain; git diff --name-only "
        "0fd8095 HEAD; grep -rn HANDWRITTEN test lib config mix.exs'", 0,
        "POST-GATE STATE WITNESS at 6c335f0: friday/gc-fri-0800 (d6a6e5b) is an ancestor of HEAD; orphan_ex4pm_beams=0; "
        "first stdout line of the next dev-env child is the task's own 'mix ggen_igniter.plan -- read-only admission "
        "preview (no filesystem mutation)'; porcelain empty; 0fd8095..HEAD outside this lane's receipt paths = "
        "HANDWRITTEN.md only; its only textual mentions under test/ lib/ config/ mix.exs are two titles in "
        "test/fixtures/kernel_differential/v26.9.22/orders.json and 0 File reads of HANDWRITTEN.md",
        f"{G}/32-state-witness-head-6c335f0.log", "witness: state at continuation head"),
    cmd(GATE, 0,
        "LANE GATE on committed lane head 0fd8095 (gate script sha256 " + gate_sha + "): "
        "Elixir 1.18.4 (compiled with Erlang/OTP 27); format ok; credo 1 mods/funs, found no issues; "
        "seeds 0/648358/1/2 each '10 tests, 0 failures'; lib/ porcelain empty; PROBE_ISOLATION_GATE OK",
        f"{G}/11-gate-head-0fd8095.log", "lane gate on committed head"),
    cmd(PIN + " sh -c 'mix test test/ggen_igniter_base_mix_task_end_user_test.exs --seed 0; "
        "ls _build/dev/lib/ggen_igniter/ebin | grep -c Ex4pm; mix ggen_igniter.plan --help | head -1; "
        "git status --porcelain -- lib'", 0,
        "STATE WITNESS at 0fd8095: probe test '1 test, 0 failures'; orphan_beams=0 in "
        "_build/dev/lib/ggen_igniter/ebin; next dev-env child's first stdout line is the task's own "
        "'mix ggen_igniter.plan -- read-only admission preview ...'; lib porcelain empty",
        f"{G}/30-state-witness-head-0fd8095.log", "witness: state at head"),
    cmd(PIN + " sh -c '<same as above>' with the test file content of d6a6e5b written over HEAD's", 0,
        "STATE WITNESS revert mutation: probe test '1 test, 0 failures' but orphan_beams=1 "
        "(Elixir.Ex4pm.Runtime.Application.beam left in _build/dev) and the next dev-env child's first "
        "stdout line is 'Generated ggen_igniter app' (the defect mechanism); file restored from HEAD",
        f"{G}/31-state-witness-revert-mutation.log", "witness: mechanism under revert"),
    cmd(PIN + " mix compile && " + PIN + " mix test --seed 648358", full_exit,
        "FULL SUITE at lane head 0fd8095 under the pin, CI seed 648358: " + full_summary,
        f"{G}/40-full-suite-648358-0fd8095.log", "full suite at lane head (seed of CI 35925710605)"),
    cmd(PIN + " mix compile", 0,
        "fresh _build/dev under the pin at base d6a6e5b (deps/ APFS-cloned from ggen_igniter-int, "
        "mix.lock cmp-identical; cargo target APFS-cloned; ggen_graph_nif rebuilt): Generated ggen_igniter app",
        f"{G}/00-compile-dev.log", "provisioning"),
    cmd(PIN + " MIX_ENV=test mix compile", 0,
        "fresh _build/test under the pin at base d6a6e5b: Generated ggen_igniter app",
        f"{G}/01-compile-test.log", "provisioning"),
    cmd("git apply lanes/r2/candidates/r2-gi-probe-isolation.patch (sha256 " + cand_sha + " verified with shasum -c) "
        "&& mix format --check-formatted && git commit -F <msg>", 0,
        "candidate O applied (+13/-1, one file), format check exit 0, committed 0fd8095 under the lane identity",
        f"{G}/candidate-r2-gi-probe-isolation.patch", "construct"),
    {"cmd": "git push origin v23/R2-GI-PROBE-ISOLATION:refs/heads/v23/R2-GI-PROBE-ISOLATION", "cwd": WT, "exit": 0,
     "summary": "new branch at 0fd8095 (no force, no PR); triggers ggen_igniter CI on push", "role": "remote effect"},
]

falsifiers = [
    cmd(GATE, 2,
        "WITNESS base (revert of the fix = d6a6e5b, friday/gc-fri-0800): seed 0 '10 tests, 1 failure' -- "
        "PlanTaskTest plan --json (test/ggen_igniter_plan_task_test.exs:25) Jason.DecodeError "
        "'unexpected byte at position 0: 0x47 (\"G\")'; gate exits 2 before PROBE_ISOLATION_GATE OK",
        f"{G}/10-gate-base-d6a6e5b.log", "witness: base fails (revert mutation)"),
    cmd(GATE, 2,
        "MUTANT M1 (on_exit re-syncs the WRONG build: env MIX_ENV=test; diff "
        f"{G}/20-mutant-M1-wrong-env.diff, mix-formatted so the gate reaches the tests): seed 0 "
        "'10 tests, 1 failure', same Jason.DecodeError 0x47 ('G'); killed. Working file restored "
        "from HEAD afterwards (git show HEAD:<path> > <path>; porcelain empty)",
        f"{G}/21-gate-mutant-M1.log", "witness: mutant killed"),
]
for f in falsifiers:
    f["verdict"] = "killed"

hosted["log"] = f"{G}/50-hosted-ci-35945312173.log"
hosted["output_sha256"] = sha(hosted["log"])
hosted_history = [hosted]
if hosted_head is not None:
    hosted_head["log"] = f"{G}/51-hosted-ci-{hosted_head['run_id']}.log"
    hosted_head["output_sha256"] = sha(hosted_head["log"])
    hosted_head["run_json"] = f"{G}/51-hosted-ci-{hosted_head['run_id']}.json"
    hosted_head["run_json_sha256"] = sha(hosted_head["run_json"])
    hosted_history.append(hosted_head)
latest_hosted = hosted_history[-1]

full_ok = full_exit == 0
hosted_ok = latest_hosted.get("conclusion") == "success" and latest_hosted.get("head_sha") in (SUBJ, HEAD_GATE)
standing = "ALIVE" if full_ok else "PARTIAL_ALIVE"

receipt = {
    "work_order": {
        "id": LANE,
        "wave": "R2g (R2 pre-freeze CI repair); continued in F1g (after the 2026-09-23 usage-limit halt)",
        "goal_ttl_order": "none (release defect repair lane; no goal.ttl WorkOrder; receipt not tuple-linked)",
        "defect_key": "ggen_igniter-test-orphan-dev-beam",
        "defect": "CI 35925710605 @aa07ee7 (seed 648358): 1349 tests, 1 failure -- "
                  "test/ggen_igniter_plan_task_test.exs:91 '--help / -h byte-identical' got output starting with "
                  "'Generated ggen_igniter app'",
        "cause": "test/ggen_igniter_base_mix_task_end_user_test.exs writes lib/tmp_ex4pm_probe_N/application.ex into the "
                 "shared checkout and runs a dev-env child that compiles it into _build/dev/lib/ggen_igniter/ebin; "
                 "on_exit removed only the source, so the next dev-env mix child purges the orphan beam and Mix "
                 "compile.app prints 'Generated ggen_igniter app' into that child's stdout. Latent since 4aa5f36.",
        "failure_classification": "subject defect (test isolation; hand-authored test, not generator-owned)",
        "source": "swarm wf_2755fdff-28e (swarm-only defect); candidate lanes/r2/candidates/r2-gi-probe-isolation.patch",
        "contract_refs": [
            "PRD section 13 (Release Stop Condition: green exact-head qualification of the frozen subject)",
            "ARD section 25 (Verification Ladder: multi-repo exact-head qualification)",
            "ARD section 20 (Failure Semantics: classify before repair)",
            "PRD PR-013 (Replay: seed-independent reconstruction of standing)",
            "DRIVER.md release closure procedure (R2 pre-freeze CI repair; tests only, no product lib/ code)",
        ],
        "acceptance": GATE,
        "falsifier": "any exact-stdout dev-env child test (plan --help/-h, the --json single-document tests, doctor "
                     "--json) fails with leading Mix compile chatter at the lane head under any seed, or "
                     "`git status --porcelain -- lib` is non-empty after the suite",
        "candidates": {
            "retained": "on_exit re-sync of the shared dev build (`{_out, 0} = System.cmd(\"mix\", [\"compile\"], "
                        "cd: repo_root, stderr_to_stdout: true)`) -- fixes the source of the staleness, assertions unchanged",
            "preserved_unbuilt": "run the probe in a temp Mix project with path/symlink-shared deps so lib/ and "
                                 "_build/dev are never touched (non-dominated: stronger isolation, larger diff; "
                                 "successor option, not built)",
            "rejected": "weakening the byte-identity or single-JSON-document assertions (victims, not the source)",
        },
    },
    "identity": {
        "subject": LANE,
        "repo": "/Users/sac/ggen_igniter (origin seanchatmangpt/ggen_igniter)",
        "worktree": WT,
        "branch": "v23/R2-GI-PROBE-ISOLATION",
        "base_ref": "friday/gc-fri-0800",
        "subject_sha": HEAD_GATE,
        "product_commit": SUBJ,
        "subject_sha_note": "subject_sha = the committed lane head the F1g continuation gate ran on (6c335f0); the product "
                            "commit 0fd8095 (the only test/ change) is its parent; 0fd8095..6c335f0 adds only this lane's "
                            "receipt JSON, its gate dir and one HANDWRITTEN.md ledger row. The receipt commit that carries "
                            "this file is a child of 6c335f0 touching only this lane's receipt paths (a commit cannot "
                            "contain its own hash).",
        "base_sha": BASE,
        "base_sha_note": "merge-base(v23/R2-GI-PROBE-ISOLATION, friday/gc-fri-0800) = d6a6e5b (= ggen_igniter-int HEAD "
                         "at lane start and still at the F1g continuation; origin/friday/gc-fri-0800 = d6a6e5b after "
                         "git fetch --no-prune). Product diff base..subject: test/ggen_igniter_base_mix_task_end_user_test.exs "
                         "+13/-1 only; no lib/, priv/, config/, native/, mix.exs, mix.lock, CI or goal.ttl change",
        "toolchain": "Elixir 1.18.4 (compiled with Erlang/OTP 27), erlang 27.2.4 (.tool-versions pin; "
                     "/Users/sac/.asdf/installs/elixir/1.18.4-otp-27, /Users/sac/.asdf/installs/erlang/27.2.4); "
                     "fresh _build/dev and _build/test compiled under the pin",
    },
    "authority": {
        "ceiling": "CONSTRUCT",
        "grant": "DRIVER.md release closure procedure, wave R2 (lane R2-GI-PROBE-ISOLATION): lane worktree + own scratch; "
                 "push of the lane branch (no force, no PR); no merge into ggen_igniter-int",
        "actor": "claude-opus-5-5 workflow subagent, lane R2-GI-PROBE-ISOLATION (wave R2g; F1g continuation)",
    },
    "consequence": {
        "commits": [SUBJ, HEAD_GATE],
        "files_changed": [
            "test/ggen_igniter_base_mix_task_end_user_test.exs",
            "HANDWRITTEN.md",
            f"receipts/v26.9.23/{LANE}.json",
            *sorted(f"{G}/{p.name}" for p in (wt / G).iterdir()),
        ],
        "generated_vs_handwritten": "hand-written residue (not generator-owned: no admitted generator manufactures ExUnit "
                                    "subprocess-test lifecycles); ledger row appended to HANDWRITTEN.md in the receipt commit "
                                    "(UNSUPPORTED(generator-capability), paydown = the preserved temp-Mix-project alternative or a "
                                    "test-harness generator); no test or court reads HANDWRITTEN.md (grep over test/ lib/ priv/ggen), "
                                    "so the subject's gate verdict is unchanged by it; the receipt JSON is emitted by "
                                    f"{G}/build_receipt.py",
        "remote_effects": [
            "origin refs/heads/v23/R2-GI-PROBE-ISOLATION created at " + SUBJ + " (no force)",
            *(f"hosted CI run {h['run_id']} (ggen_igniter CI, push event) on {h.get('head_sha')}: "
              f"{h.get('conclusion')}" for h in hosted_history),
            "origin refs/heads/v23/R2-GI-PROBE-ISOLATION advanced 0fd8095 -> " + HEAD_GATE + " (no force, prior session)",
            "F1g: origin refs/heads/v23/R2-GI-PROBE-ISOLATION fast-forwarded to the receipt commit that carries this "
            "file (child of " + HEAD_GATE + "; no force, no PR); its push run is owed a hosted verdict only after "
            "R2-GI-CI's job budget merges",
        ],
        "local_effects": [
            f"{WT}/deps: APFS clone of /Users/sac/wt/v26922/fri/ggen_igniter-int/deps (mix.lock cmp-identical)",
            f"{WT}/native/ggen_graph_nif/target: APFS clone of ggen_igniter-int's cargo target; crate rebuilt under the pin",
            f"{WT}/_build/dev and _build/test: fresh, under the pin",
            "mutant M1 and the revert-mutation state witness edited the test file in the working tree only; each was "
            "restored from HEAD (git show HEAD:<path> > <path>), porcelain empty afterwards",
            "receipts/v26.9.22/kernel-differential.json rewritten by the full-suite run (pre-existing test behaviour, "
            f"not this lane's); captured to {G}/41-post-suite-tracked.diff, then restored from HEAD",
        ],
    },
    "replay": {
        "durable_location": f"{G} (tracked in git on branch v23/R2-GI-PROBE-ISOLATION)",
        "gate_script": {"path": f"{G}/r2-gi-probe-isolation.sh", "sha256": gate_sha,
                        "source": "/Users/sac/wt/v26922/v26923/lanes/r2/gates/r2-gi-probe-isolation.sh"},
        "builder": f"{G}/build_receipt.py",
        "commands": commands,
    },
    "falsifiers": falsifiers,
    "hosted_ci": latest_hosted,
    "hosted_ci_history": hosted_history,
    "standing": {
        "value": standing,
        "derived_from": "replay.commands[0] (F1g lane gate exit 0 on the committed lane head " + HEAD_GATE + ") and "
                        "replay.commands[1] (post-gate state at that head: 0 orphan beams, lib clean, only receipt paths + "
                        "HANDWRITTEN.md since the product commit); replay.commands[2] (lane gate exit 0 on the product "
                        "commit " + SUBJ + "), state witnesses "
                        "replay.commands[3]/[4] (0 orphan beams at head; 1 orphan beam + leading 'Generated ggen_igniter app' "
                        "under the revert), full suite replay.commands[5] (exit " + str(full_exit) + ", seed 648358, at " + SUBJ
                        + "; test/lib/config/priv trees identical at " + HEAD_GATE + "); "
                        "anti-vacuity falsifiers[0] (revert = base d6a6e5b: gate exit 2) and falsifiers[1] (mutant M1: gate exit 2), both killed"
                        + ("" if hosted_ok else "; hosted CI witness not yet success on the subject (receipt field only)"),
    },
}
if not full_ok:
    receipt["standing"]["broken_term"] = "mu_on_O"

out = wt / f"receipts/v26.9.23/{LANE}.json"
out.write_text(json.dumps(receipt, indent=1, ensure_ascii=False) + "\n")
print(out)
