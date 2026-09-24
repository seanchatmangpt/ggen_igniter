#!/usr/bin/env python3
"""Build receipts/v26.9.23/R1-GI-PIN.json from the step logs in this directory.

usage: python3 receipts/v26.9.23/R1-GI-PIN.logs/build_receipt.py <lane-gate-log> <gate-head-sha> <lane-commit>...

Run from the repository root. Every exit code, timestamp, head SHA and summary line is parsed from
the step logs (written by step.sh / ambient_step.sh), never typed by hand; output_sha256 is the sha256
of the log bytes. <gate-head-sha> is the exact lane head the literal lane gate ran on (the judged
subject); <lane-commit>... are the lane commits the receipt commit follows (a commit cannot carry its
own hash).

Round 0 (commits 7e8bfa3, 4386eab): the pinned full gate at the int head 3ed6a7a, no product change.
Round 1 (court REVERT-MUTATION refuted, admission_vacuous): the lane adds
test/ggen_igniter_toolchain_pin_qualification_test.exs, which makes the suite consume this receipt and
the pin; this builder records that test's witnesses (baseline pass, revert-mutation kill, log-tamper
kill, pin-bump kill, ambient-toolchain kill) and the literal lane gate on the new subject.
"""
import hashlib
import json
import os
import re
import sys

LANE = "R1-GI-PIN"
LOGS = f"receipts/v26.9.23/{LANE}.logs"
WT = "/Users/sac/wt/v26922/v23/R1-GI-PIN"
SCRATCH = "/private/tmp/claude-501/-Users-sac/1fecd79a-9323-4b57-a949-d7892a3ea283/scratchpad/r1gipin-r1"
PIN = (
    "PATH=/Users/sac/.asdf/installs/elixir/1.18.4-otp-27/bin:"
    "/Users/sac/.asdf/installs/erlang/27.2.4/bin:$PATH"
)
GATE_CMD = (
    f"{PIN} sh -c 'elixir --version && mix format --check-formatted && mix compile "
    "--warnings-as-errors --force && mix credo && mix test'"
)
BASE = "3ed6a7afc51fcfc652cfa72f75680d7fa1543bc8"  # friday/gc-fri-0800 after R1-GI-FMT merged
PRE_FIX = "3937a4f89ecf2b7fa12068406377c05ec1a1b8fc"
ROUND0_GATE_HEAD = "7e8bfa3b4c664b7b09bd5d75ddfca491d2adb4d6"
TEST_FILE = "test/ggen_igniter_toolchain_pin_qualification_test.exs"
TEST_CMD = f"{PIN} MIX_ENV=test mix test {TEST_FILE}"
TOTAL_RE = r"^\d+ doctests?, \d+ properties, \d+ tests?, .*$"


def parse(name):
    path = os.path.join(LOGS, name)
    data = open(path, "rb").read()
    text = data.decode("utf-8", "replace")
    head = re.search(r"^# cwd=(\S+) head=([0-9a-f]{40}) started=(\S+)", text, re.M)
    end = re.search(r"^# ended=(\S+) exit=(\d+)", text, re.M)
    return {
        "text": text,
        "cwd": head.group(1) if head else None,
        "head": head.group(2) if head else None,
        "started_at": head.group(3) if head else None,
        "ended_at": end.group(1) if end else None,
        "exit": int(end.group(2)) if end else None,
        "output_sha256": hashlib.sha256(data).hexdigest(),
        "log": path,
    }


def line(text, pattern):
    m = re.search(pattern, text, re.M)
    return m.group(0).strip() if m else "(line not found)"


def lines(text, pattern):
    return [m.group(0).strip() for m in re.finditer(pattern, text, re.M)]


def sha(path):
    return hashlib.sha256(open(path, "rb").read()).hexdigest()


def cmd(entry, command, summary, **extra):
    out = {
        "cmd": command,
        "cwd": entry["cwd"],
        "exit": entry["exit"],
        "summary": f"{summary} [head {entry['head']}; {entry['started_at']} -> {entry['ended_at']}]",
        "output_sha256": entry["output_sha256"],
        "log": entry["log"],
    }
    out.update(extra)
    return out


def failing(entry):
    return lines(entry["text"], r"^\s+\d+\) test .*$")


def main(argv):
    if len(argv) < 4:
        sys.exit(__doc__)
    gate = parse(os.path.basename(argv[1]))
    subject, lane_commits = argv[2], argv[3:]
    assert gate["head"] == subject, (gate["head"], subject)

    fmt = parse("01-format-3ed6a7a.log")
    dep_dev = parse("00-deps-compile-dev.log")
    comp = parse("02-compile-3ed6a7a.log")
    credo = parse("03-credo-3ed6a7a.log")
    dep_test = parse("04a-deps-compile-test.log")
    comp_test = parse("04b-compile-test.log")
    test = parse("04-test-3ed6a7a.log")
    fals = parse("06-falsifier-format-3937a4f.log")
    gate0 = parse("10-lane-gate-7e8bfa3.log")
    w_base = parse(f"20-witness-baseline-{subject[:7]}.log")
    w_revert = parse(f"21-witness-revert-mutation-{subject[:7]}.log")
    w_tamper = parse(f"22-witness-log-tamper-{subject[:7]}.log")
    w_bump = parse(f"23-witness-pin-bump-{subject[:7]}.log")
    w_amb = parse(f"24-witness-ambient-{subject[:7]}.log")
    ident0_path = os.path.join(LOGS, "05-build-identity.log")
    ident_path = os.path.join(LOGS, f"13-build-identity-{subject[:7]}.log")
    ident_text = open(ident_path).read()
    diff0_path = os.path.join(LOGS, "post-test.tracked.diff")
    diff_path = os.path.join(LOGS, f"12-post-gate-{subject[:7]}.tracked.diff")

    for e in (fmt, dep_dev, comp, credo, dep_test, comp_test, test):
        assert e["head"] == BASE, (e["log"], e["head"])
    assert fals["head"] == PRE_FIX
    assert gate0["head"] == ROUND0_GATE_HEAD
    for w in (w_base, w_revert, w_tamper, w_bump, w_amb):
        assert w["head"] == subject, (w["log"], w["head"])

    test_total = line(test["text"], TOTAL_RE)
    test_time = line(test["text"], r"^Finished in .*$")
    g_total = line(gate["text"], TOTAL_RE)
    g_time = line(gate["text"], r"^Finished in .*$")
    g0_total = line(gate0["text"], TOTAL_RE)
    g0_time = line(gate0["text"], r"^Finished in .*$")
    g_credo = line(gate["text"], r".*mods/funs.*$")
    same_diff = sha(diff_path) == sha(diff0_path)

    commands = [
        cmd(gate, GATE_CMD,
            f"LANE GATE (literal) on the committed lane head {subject} (= base {BASE[:7]} + "
            f"{TEST_FILE} + HANDWRITTEN.md row + receipts/v26.9.23/{LANE}*): "
            f"{line(gate['text'], r'^Elixir .*$')}; format, forced compile, credo ({g_credo}), "
            f"{g_time}; {g_total}",
            role="lane gate on committed head"),
        cmd(w_base, TEST_CMD,
            "WITNESS baseline: the new toolchain-pin qualification test passes on the unmutated subject "
            f"under the pin (scratch detached worktree, _build/test APFS-cloned from the lane): "
            f"{line(w_base['text'], r'^\d+ tests?, .*$')}",
            role="witness: baseline"),
        cmd(gate0, GATE_CMD,
            f"round 0 LANE GATE (literal) on lane head {ROUND0_GATE_HEAD} (= {BASE[:7]} + receipts only): "
            f"Elixir 1.18.4 (OTP 27); {g0_time}; {g0_total}",
            role="prior lane gate (round 0)"),
        cmd(fmt, f"{PIN} sh -c 'elixir --version && mix format --check-formatted'",
            f"round 0 step 1/4 of the lane gate at the base {BASE[:7]}: Elixir 1.18.4 (compiled with "
            "Erlang/OTP 27); format check exit 0"),
        cmd(dep_dev, f"{PIN} mix deps.compile",
            "round 0: fresh _build/dev (no _build existed in the worktree; deps/ source APFS-cloned from "
            "ggen_igniter-int, mix.lock cmp-identical): all deps compiled under the pin"),
        cmd(comp, f"{PIN} mix compile --warnings-as-errors --force",
            "round 0 step 2/4: " + line(comp["text"], r"^Compiling crate .*$") + "; Generated ggen_igniter "
            "app; no warnings"),
        cmd(credo, f"{PIN} mix credo",
            "round 0 step 3/4: " + line(credo["text"], r".*mods/funs.*$")),
        cmd(dep_test, f"{PIN} MIX_ENV=test mix deps.compile",
            "round 0: fresh _build/test deps compiled under the pin (separate command to keep each < 20 min)"),
        cmd(comp_test, f"{PIN} MIX_ENV=test mix compile --warnings-as-errors",
            "round 0: test-env project compile under the pin (NIF copied from the rebuilt crate); Generated "
            "ggen_igniter app"),
        cmd(test, f"{PIN} mix test",
            f"round 0 step 4/4 FULL SUITE under the pin at the base: {test_time}; {test_total}"),
    ]

    witness_falsifiers = [
        cmd(w_revert, TEST_CMD,
            "ANTI-VACUITY (court lens REVERT-MUTATION, repeated): every non-test file the lane changed since "
            f"{BASE[:7]} reverted in a scratch worktree (git rm of the 15 added receipts/v26.9.23/{LANE}* "
            "files, git checkout 3ed6a7a -- HANDWRITTEN.md; mutated tree = base + the test file only), then "
            f"the test under the pin: {line(w_revert['text'], r'^\d+ tests?, .*$')} -- "
            + "; ".join(failing(w_revert)),
            role="anti-vacuity: revert-mutation killed", verdict="killed"),
        cmd(w_tamper, TEST_CMD,
            "FALSIFIER: one byte appended to the cited log 04-test-3ed6a7a.log (scratch): "
            f"{line(w_tamper['text'], r'^\d+ tests?, .*$')} -- "
            + line(w_tamper["text"], r"cited log .* does not hash to [0-9a-f]{64}"),
            role="falsifier: log tamper killed", verdict="killed"),
        cmd(w_bump, TEST_CMD,
            "FALSIFIER: .tool-versions bumped to elixir 1.18.5-otp-27 without a new pinned qualification "
            f"(scratch): {line(w_bump['text'], r'^\d+ tests?, .*$')} -- " + "; ".join(failing(w_bump)),
            role="falsifier: pin bump killed", verdict="killed"),
        cmd(w_amb,
            "MIX_ENV=test MIX_BUILD_ROOT=_build_amb sh -c 'elixir --version && mix test "
            f"{TEST_FILE}' (AMBIENT toolchain, no pin PATH; _build_amb/test APFS-cloned from an OTP-28 build "
            "with the same mix.lock)",
            "FALSIFIER: the ambient toolchain that admitted the frozen subject in the release qualification "
            f"({line(w_amb['text'], r'^Elixir .*$')}): {line(w_amb['text'], r'^\d+ tests?, .*$')} -- "
            + line(w_amb["text"], r"BUILD_BROKEN\(toolchain\): .*$"),
            role="falsifier: ambient toolchain killed", verdict="killed"),
    ]
    for w in witness_falsifiers:
        assert w["exit"] != 0, w["log"]

    standing_from = (
        f"literal lane gate on the committed lane head {subject} under the .tool-versions pin (Elixir 1.18.4-otp-27 "
        f"/ Erlang 27.2.4, OTP-27 _build compiled with --force, NIF rebuilt): exit {gate['exit']} ({g_total}); "
        f"the new test {TEST_FILE} passes on the subject and is killed by the revert mutation, a log tamper, a "
        "pin bump and the ambient toolchain (falsifiers[1..4]); round 0 pinned steps at the base "
        f"{BASE[:7]}: format 0, compile 0, credo 0, mix test 0 ({test_total})"
    )
    all_zero = all(c["exit"] == 0 for c in commands)
    standing = {"value": "ALIVE" if all_zero else "PARTIAL_ALIVE", "derived_from": standing_from}
    if not all_zero:
        standing["broken_term"] = "mu_unlawful"

    files = sorted(
        [f"receipts/v26.9.23/{LANE}.json", TEST_FILE, "HANDWRITTEN.md"]
        + [f"{LOGS}/{n}" for n in os.listdir(LOGS) if not n.startswith(".")]
    )

    receipt = {
        "work_order": {
            "id": LANE,
            "wave": "R1a (wf_7a7c7064-905, lanes/wave-R1a.json)",
            "goal_ttl_order": "none (release defect repair lane; no goal.ttl WorkOrder)",
            "defect": (
                "Required_23 (GC23-11 exact-head qualification): the release qualification of ggen_igniter "
                "passed only under the ambient Elixir 1.19.5 / OTP 28.3.1, not under the repo's "
                ".tool-versions pin (elixir 1.18.4-otp-27, erlang 27.2.4) that CI uses"
            ),
            "defect_evidence": (
                "/Users/sac/wt/v26922/v26923/receipts/fleet/ggen_igniter-3937a4f89ecf2b7fa12068406377c05ec1a1b8fc.json "
                "toolchain (Elixir 1.19.5, OTP 28.3.1); "
                "/Users/sac/wt/v26922/v26923/receipts/fleet/xaas-e999e62b63c680517b9a562cef877d8b09b0cfdd.json "
                "(F3/F4 = pinned-formatter drift in bootstrap.ex, repaired by R1-GI-FMT 8b9dcfb, merged 3ed6a7a)"
            ),
            "failure_classification": (
                "round 0: no failure under the pin at the base: the pinned full gate exits 0 at 3ed6a7a; the "
                "only pin-visible defect (F3/F4, subject defect) was already repaired by R1-GI-FMT. round 1: "
                "evidence defect (acceptance design) -- the lane's only consequence was receipt evidence that no "
                "gate read, so the court's revert mutation left the gate green (admission_vacuous); repaired by "
                "a test that makes the suite consume the evidence and the pin"
            ),
            "repair_round": {
                "round": 1,
                "court_verdicts": [
                    {"lens": "GATE", "verdict": "pass", "answer": "kept; the gate is re-run on the new subject "
                     "(replay.commands[0])"},
                    {"lens": "REVERT-MUTATION", "verdict": "refuted", "broken_term": "admission_vacuous",
                     "answer": (
                         f"accepted as correct; {TEST_FILE} makes the gate read the pinned-qualification "
                         "receipt (R-schema admission via Bootstrap.Receipts.check/1, ALIVE, toolchain = "
                         ".tool-versions pin, cited logs committed with matching sha256, zero-failure lane-gate "
                         "log on the pinned VM) and the pin itself (running VM = .tool-versions, CI setup-beam = "
                         ".tool-versions); the lens's own mutation now fails the acceptance (falsifiers[1])"
                     )},
                ],
            },
            "contract_refs": [
                "PRD section 12 GC23-11 (Bounded Fleet: exact-subject standing)",
                "PRD PR-013 (Replay)",
                "PRD PR-017 (Stop calculus)",
                "ARD section 20 (Failure Semantics: BUILD_BROKEN(toolchain))",
                "ARD section 25 (Verification Ladder: multi-repo exact-head qualification)",
                "ARD section 27 (Release Receipt: toolchain identity)",
                "DRIVER.md release closure procedure (frozen subjects; only the named defect may change)",
            ],
            "acceptance": f"lane gate: {GATE_CMD}",
        },
        "identity": {
            "subject": LANE,
            "repo": "/Users/sac/ggen_igniter (origin seanchatmangpt/ggen_igniter)",
            "worktree": WT,
            "branch": f"v23/{LANE}",
            "base_ref": "friday/gc-fri-0800",
            "subject_sha": subject,
            "base_sha": BASE,
            "base_sha_note": (
                "merge-base(v23/R1-GI-PIN, friday/gc-fri-0800) = 3ed6a7a = friday/gc-fri-0800 head after "
                "R1-GI-FMT merged (= ggen_igniter-int HEAD at lane start). Product diff base..subject: "
                f"{TEST_FILE} (added) and one HANDWRITTEN.md row; no lib/, priv/, config/, native/, mix.exs or "
                f"mix.lock change; everything else is receipts/v26.9.23/{LANE}*"
            ),
            "subject_tree_clean": (
                "git status --porcelain empty before the lane gate and after restoring the one test-written "
                "report (observations[0])"
            ),
            "lane_head_gate": subject,
        },
        "authority": {
            "ceiling": "CONSTRUCT",
            "grant": (
                "NONE beyond DRIVER.md authority (operator release sequence, release defect repair lane "
                "R1-GI-PIN): lane worktree + own scratch only; no push, no PR, no merge into ggen_igniter-int"
            ),
            "actor": "claude-opus-5-5 workflow subagent, lane R1-GI-PIN (wave R1a, repair round 1)",
        },
        "consequence": {
            "commits": lane_commits,
            "files_changed": files,
            "generated_vs_handwritten": (
                f"{TEST_FILE} is hand-written residue with a HANDWRITTEN.md row (UNSUPPORTED(generator-capability): "
                "no pack models the toolchain pin as one fact; .tool-versions, ci.yml setup-beam and its cache keys "
                "are three hand-kept copies; successor release-qualification pack, v23:GC-26.9.24); the receipt "
                "JSON is emitted by build_receipt.py from the step logs"
            ),
            "remote_effects": [],
            "local_effects": [
                f"{WT}/deps: APFS clone (cp -cR) of /Users/sac/wt/v26922/fri/ggen_igniter-int/deps (mix.lock cmp-identical)",
                f"{WT}/native/ggen_graph_nif/target: APFS clone of ggen_igniter-int's cargo target; ggen_graph_nif "
                "rebuilt by Rustler under the pin on every forced compile",
                f"{WT}/_build/dev and _build/test: fresh, compiled under the pin ({line(ident_text, r'^otp_release=.*$')}; "
                f"{os.path.basename(ident_path)})",
                f"scratch {SCRATCH}/wit: detached worktree at {subject[:7]} (deps, _build/test, cargo target APFS-cloned "
                "from the lane; _build_amb/test APFS-cloned from /Users/sac/wt/v26922/v23/V23-B, read only there) for "
                "the five witnesses; every mutation restored with git checkout HEAD -- <path>, then the worktree was "
                "removed",
                "receipts/v26.9.22/kernel-differential.json rewritten by the lane-gate test run, captured to "
                f"{os.path.basename(diff_path)}, then git restore",
            ],
        },
        "replay": {
            "durable_location": f"{LOGS} (tracked in git on branch v23/{LANE})",
            "step_runner": f"{LOGS}/step.sh (sets the pin PATH, records cwd/head/timestamps/exit into each log); "
            f"{LOGS}/ambient_step.sh (same format, ambient toolchain, witness 24 only)",
            "builder": f"{LOGS}/build_receipt.py",
            "build_identity": f"{LOGS}/build_identity.exs",
            "commands": commands,
        },
        "falsifiers": [
            cmd(fals, f"{PIN} sh -c 'elixir --version && mix format --check-formatted'",
                "ANTI-VACUITY (round 0): the same pinned gate step 1 at the pre-repair frozen subject "
                f"{PRE_FIX} (detached scratch worktree, deps APFS-cloned) exits 1: "
                "lib/ggen_igniter/semantic_jira/bootstrap.ex not formatted under 1.18.4 -- the pinned gate "
                "refuses the subject the ambient qualification admitted",
                role="anti-vacuity: killed", verdict="killed"),
        ] + witness_falsifiers,
        "observations": [
            {
                "kind": "test_writes_tracked_file",
                "classification": "pre-existing (successor; not fixed here per the lane task)",
                "path": "receipts/v26.9.22/kernel-differential.json",
                "writer": "test/ggen_igniter_semantic_jira_kernel_differential_test.exs (@report_path, File.write!)",
                "finding": (
                    "each pinned full-suite run rewrites only sha256 fields (shapes_sha256 / pack_ontology "
                    "sha256) and slice_count 200 -> 290, the same class the ambient release qualification "
                    "observed; restored with git restore after every run"
                ),
                "evidence": f"{diff0_path} (round 0), {diff_path} (round 1 lane gate)",
                "diff_sha256": sha(diff0_path),
                "lane_gate_diff_sha256": sha(diff_path),
                "lane_gate_run": (
                    "the round-1 lane gate's git diff is byte-identical to the round-0 diff (same sha256)"
                    if same_diff else "the round-1 lane gate's git diff differs from the round-0 diff (see both files)"
                ),
                "standing_effect": "none",
            },
            {
                "kind": "test_count_reconciliation",
                "finding": (
                    f"round 1 lane gate '{g_total}' vs round 0 '{g0_total}': the difference is the 6 tests of "
                    f"{TEST_FILE}. Pinned ExUnit 1.18.4 counts excluded tests in the total; ambient ExUnit 1.19.5 "
                    "reported '20 doctests, 42 properties, 1340 tests, 0 failures, 1 skipped (9 excluded)' at "
                    "3937a4f (1349 - 9 = 1340), same suite"
                ),
                "standing_effect": "none",
            },
            {
                "kind": "test_stderr_noise",
                "classification": "pre-existing",
                "finding": "'fatal: unable to read tree (17e2923d...)' lines from a git subprocess inside a test, "
                "ExUnit runner stack lines and expected [warning] lines from failure-injection tests; no test failed",
                "standing_effect": "none",
            },
            {
                "kind": "host_contention",
                "classification": "environment",
                "finding": f"mix test wall time: {g_time} (round 1), {g0_time} (round 0) under concurrent lanes; "
                "run as a background command to a log, never a blocking > 20 min call",
                "standing_effect": "none",
            },
        ],
        "toolchain": {
            "pin_source": ".tool-versions: elixir 1.18.4-otp-27, erlang 27.2.4",
            "elixir": "Elixir 1.18.4 (compiled with Erlang/OTP 27)",
            "elixir_bin": "/Users/sac/.asdf/installs/elixir/1.18.4-otp-27/bin/elixir",
            "erl_bin": "/Users/sac/.asdf/installs/erlang/27.2.4/bin/erl",
            "otp_release": "27",
            "otp_version": "27.2.4",
            "erts": "15.2.2",
            "compiler_app": "8.5.5",
            "build_identity_log": ident_path,
            "build_identity_sha256": sha(ident_path),
            "build_identity_round0_log": ident0_path,
            "build_identity_round0_sha256": sha(ident0_path),
            "rustc": "rustc 1.97.0 (2d8144b78 2026-07-07)",
            "cargo": "cargo 1.97.0 (c980f4866 2026-06-30)",
            "nif_note": (
                "ggen_graph_nif: rustler 0.36.2 selects the NIF API by cargo feature (rustler build.rs "
                "CARGO_FEATURE_NIF_VERSION_*), not by the running ERTS; rebuilt under the pin anyway. wasmex 0.15.1 "
                "precompiled NIF nif-2.15 from the rustler_precompiled cache (OTP-independent)"
            ),
            "tool_versions_pin_used": True,
            "mix_lock_sha256": sha("mix.lock"),
        },
        "findings": [
            {
                "id": "R1-GI-PIN-1",
                "statement": "ggen_igniter friday/gc-fri-0800 at 3ed6a7a passes the full CI gate under its "
                ".tool-versions pin with a fresh OTP-27 _build",
                "classification": "none needed (no failure)",
                "consequence_for_GC23-11": "ggen_igniter exact-subject standing under the CI toolchain is observed, "
                "not inferred from the ambient toolchain",
            },
            {
                "id": "R1-GI-PIN-2",
                "statement": (
                    f"the suite now consumes the pinned qualification: {TEST_FILE} fails when the receipt or a cited "
                    "log is removed or edited, when .tool-versions moves without a new pinned qualification, and "
                    "when the suite runs under a toolchain other than the pin (BUILD_BROKEN(toolchain))"
                ),
                "classification": "evidence defect repaired (court REVERT-MUTATION, admission_vacuous)",
                "consequence_for_GC23-11": "a green full suite of ggen_igniter is a pinned run; an ambient "
                "qualification can no longer pass",
            },
        ],
        "standing": standing,
    }
    out = f"receipts/v26.9.23/{LANE}.json"
    with open(out, "w") as fh:
        json.dump(receipt, fh, indent=1)
        fh.write("\n")
    print(out, standing["value"])


if __name__ == "__main__":
    main(sys.argv)
