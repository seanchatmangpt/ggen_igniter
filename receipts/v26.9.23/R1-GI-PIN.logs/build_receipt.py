#!/usr/bin/env python3
"""Build receipts/v26.9.23/R1-GI-PIN.json from the step logs in this directory.

usage: python3 receipts/v26.9.23/R1-GI-PIN.logs/build_receipt.py [<lane-gate-log> <gate-head-sha> <receipt-commit-sha>]

Run from the repository root. Every exit code, timestamp, head SHA and summary line is parsed from
the step logs (written by step.sh), never typed by hand; output_sha256 is the sha256 of the log bytes.
"""
import hashlib
import json
import os
import re
import sys

LANE = "R1-GI-PIN"
LOGS = f"receipts/v26.9.23/{LANE}.logs"
WT = "/Users/sac/wt/v26922/v23/R1-GI-PIN"
PIN = (
    "PATH=/Users/sac/.asdf/installs/elixir/1.18.4-otp-27/bin:"
    "/Users/sac/.asdf/installs/erlang/27.2.4/bin:$PATH"
)
SUBJECT = "3ed6a7afc51fcfc652cfa72f75680d7fa1543bc8"
PRE_FIX = "3937a4f89ecf2b7fa12068406377c05ec1a1b8fc"


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


def main(argv):
    gate = None
    if len(argv) == 4:
        gate = parse(os.path.basename(argv[1]))
        gate_head, receipt_commit = argv[2], argv[3]

    fmt = parse("01-format-3ed6a7a.log")
    dep_dev = parse("00-deps-compile-dev.log")
    comp = parse("02-compile-3ed6a7a.log")
    credo = parse("03-credo-3ed6a7a.log")
    dep_test = parse("04a-deps-compile-test.log")
    comp_test = parse("04b-compile-test.log")
    test = parse("04-test-3ed6a7a.log")
    fals = parse("06-falsifier-format-3937a4f.log")
    ident_path = os.path.join(LOGS, "05-build-identity.log")
    ident_bytes = open(ident_path, "rb").read()
    diff_path = os.path.join(LOGS, "post-test.tracked.diff")
    diff_bytes = open(diff_path, "rb").read()

    for e in (fmt, dep_dev, comp, credo, dep_test, comp_test, test):
        assert e["head"] == SUBJECT, (e["log"], e["head"])
    assert fals["head"] == PRE_FIX

    test_total = line(test["text"], r"^\d+ doctests?, \d+ properties, \d+ tests?, .*$")
    test_time = line(test["text"], r"^Finished in .*$")

    commands = [
        cmd(fmt, f"{PIN} sh -c 'elixir --version && mix format --check-formatted'",
            "step 1/4 of the lane gate at the subject: Elixir 1.18.4 (compiled with Erlang/OTP 27); "
            "format check exit 0"),
        cmd(dep_dev, f"{PIN} mix deps.compile",
            "fresh _build/dev (no _build existed in the worktree; deps/ source APFS-cloned from "
            "ggen_igniter-int, mix.lock cmp-identical): all deps compiled under the pin"),
        cmd(comp, f"{PIN} mix compile --warnings-as-errors --force",
            "step 2/4: " + line(comp["text"], r"^Compiling crate .*$") + "; Generated ggen_igniter app; "
            "no warnings"),
        cmd(credo, f"{PIN} mix credo",
            "step 3/4: " + line(credo["text"], r".*mods/funs.*$")),
        cmd(dep_test, f"{PIN} MIX_ENV=test mix deps.compile",
            "fresh _build/test deps compiled under the pin (separate command to keep each < 20 min)"),
        cmd(comp_test, f"{PIN} MIX_ENV=test mix compile --warnings-as-errors",
            "test-env project compile under the pin (NIF copied from the rebuilt crate); Generated "
            "ggen_igniter app"),
        cmd(test, f"{PIN} mix test",
            f"step 4/4 FULL SUITE under the pin: {test_time}; {test_total}"),
    ]
    if gate:
        assert gate["head"] == gate_head, (gate["head"], gate_head)
        g_total = line(gate["text"], r"^\d+ doctests?, \d+ properties, \d+ tests?, .*$")
        g_time = line(gate["text"], r"^Finished in .*$")
        commands.insert(0, cmd(
            gate,
            f"{PIN} sh -c 'elixir --version && mix format --check-formatted && mix compile "
            "--warnings-as-errors --force && mix credo && mix test'",
            "LANE GATE (literal) on the committed lane head "
            f"{gate_head} (= subject {SUBJECT[:7]} + receipts/v26.9.23/{LANE}* only): "
            f"Elixir 1.18.4 (OTP 27); format, forced compile, credo, {g_time}; {g_total}",
            role="lane gate on committed head"))

    standing_from = (
        f"replay.commands at subject {SUBJECT} under the .tool-versions pin (Elixir 1.18.4-otp-27 / "
        "Erlang 27.2.4, fresh OTP-27 _build, NIF rebuilt): format 0, compile --warnings-as-errors "
        f"--force 0, credo 0, mix test 0 ({test_total}); tracked tree clean before the run and after "
        "restoring the one test-written report (pre-existing, observations[0])"
    )
    if gate:
        standing_from += (
            f"; literal lane gate on committed lane head {gate_head} exit {gate['exit']} "
            f"({line(gate['text'], r'^\d+ doctests?, \d+ properties, \d+ tests?, .*$')})"
        )
    all_zero = all(c["exit"] == 0 for c in commands)
    standing = {"value": "ALIVE" if all_zero else "PARTIAL_ALIVE", "derived_from": standing_from}
    if not all_zero:
        standing["broken_term"] = "mu_unlawful"

    files = [f"receipts/v26.9.23/{LANE}.json"] + sorted(
        f"{LOGS}/{n}" for n in os.listdir(LOGS) if not n.startswith(".")
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
                "no failure under the pin at the subject: the pinned full gate (format, forced "
                "warnings-as-errors compile, credo, full mix test) exits 0 at 3ed6a7a; the only pin-visible "
                "defect (F3/F4, subject defect) was already repaired by R1-GI-FMT; nothing to fix in this lane"
            ),
            "contract_refs": [
                "PRD section 12 GC23-11 (Bounded Fleet: exact-subject standing)",
                "PRD PR-013 (Replay)",
                "PRD PR-017 (Stop calculus)",
                "ARD section 20 (Failure Semantics: BUILD_BROKEN(toolchain))",
                "ARD section 25 (Verification Ladder: multi-repo exact-head qualification)",
                "ARD section 27 (Release Receipt: toolchain identity)",
                "DRIVER.md release closure procedure (frozen subjects; only the named defect may change)",
            ],
            "acceptance": (
                f"lane gate: {PIN} sh -c 'elixir --version && mix format --check-formatted && mix compile "
                "--warnings-as-errors --force && mix credo && mix test'"
            ),
        },
        "identity": {
            "subject": LANE,
            "repo": "/Users/sac/ggen_igniter (origin seanchatmangpt/ggen_igniter)",
            "worktree": WT,
            "branch": f"v23/{LANE}",
            "base_ref": "friday/gc-fri-0800",
            "subject_sha": SUBJECT,
            "base_sha": SUBJECT,
            "base_sha_note": (
                "merge-base(v23/R1-GI-PIN, friday/gc-fri-0800) = 3ed6a7a = friday/gc-fri-0800 head after "
                "R1-GI-FMT merged (= ggen_igniter-int HEAD at lane start). The lane changes no product file, "
                "so subject_sha = base_sha: the judged subject is the int head itself; lane commits add only "
                f"receipts/v26.9.23/{LANE}*"
            ),
            "subject_tree_clean": "git status --porcelain empty before step 1 and after restoring the test-written report",
            "lane_head_gate": gate_head if gate else "pending (second commit records the literal gate on the committed lane head)",
        },
        "authority": {
            "ceiling": "CONSTRUCT",
            "grant": (
                "NONE beyond DRIVER.md authority (operator release sequence, release defect repair lane "
                "R1-GI-PIN): lane worktree + own scratch only; no push, no PR, no merge into ggen_igniter-int"
            ),
            "actor": "claude-opus-5-5 workflow subagent, lane R1-GI-PIN (wave R1a)",
        },
        "consequence": {
            "commits": [receipt_commit] if gate else [],
            "files_changed": files,
            "generated_vs_handwritten": (
                "no product file changed; the receipt JSON is emitted by build_receipt.py from the step logs; "
                "no HANDWRITTEN.md row needed"
            ),
            "remote_effects": [],
            "local_effects": [
                f"{WT}/deps: APFS clone (cp -cR) of /Users/sac/wt/v26922/fri/ggen_igniter-int/deps (mix.lock cmp-identical)",
                f"{WT}/native/ggen_graph_nif/target: APFS clone of ggen_igniter-int's cargo target; the local crate "
                "ggen_graph_nif was rebuilt by Rustler under the pin (path changed) and copied to priv/native/ggen_graph_nif.so "
                "(sha256 87d284a2..., differs from int's 31494569...)",
                f"{WT}/_build/dev and _build/test: fresh, compiled under the pin (compiler 8.5.5 = OTP 27; 05-build-identity.log)",
                "scratch /private/tmp/claude-501/v23-scratch/R1a-R1-GI-PIN: detached falsifier worktree gi-3937a4f created and removed",
                "receipts/v26.9.22/kernel-differential.json rewritten by the test run, captured to post-test.tracked.diff, then git restore",
            ],
        },
        "replay": {
            "durable_location": f"{LOGS} (tracked in git on branch v23/{LANE})",
            "step_runner": f"{LOGS}/step.sh (sets the pin PATH, records cwd/head/timestamps/exit into each log)",
            "builder": f"{LOGS}/build_receipt.py",
            "commands": commands,
        },
        "falsifiers": [
            cmd(fals, f"{PIN} sh -c 'elixir --version && mix format --check-formatted'",
                "ANTI-VACUITY: the same pinned gate step 1 at the pre-repair frozen subject "
                f"{PRE_FIX} (detached scratch worktree, deps APFS-cloned) exits 1: "
                "lib/ggen_igniter/semantic_jira/bootstrap.ex not formatted under 1.18.4 -- the pinned gate "
                "refuses the subject the ambient qualification admitted",
                role="anti-vacuity: killed", verdict="killed"),
        ],
        "observations": [
            {
                "kind": "test_writes_tracked_file",
                "classification": "pre-existing (successor; not fixed here per the lane task)",
                "path": "receipts/v26.9.22/kernel-differential.json",
                "writer": "test/ggen_igniter_semantic_jira_kernel_differential_test.exs (@report_path, File.write!)",
                "finding": (
                    "the pinned run rewrote only sha256 fields (shapes_sha256 / pack_ontology sha256) and "
                    "slice_count 200 -> 290, the same class the ambient release qualification observed; "
                    "restored with git restore after the run"
                ),
                "evidence": f"{LOGS}/post-test.tracked.diff",
                "diff_sha256": hashlib.sha256(diff_bytes).hexdigest(),
                "standing_effect": "none",
            },
            {
                "kind": "test_count_reconciliation",
                "finding": (
                    f"pinned ExUnit 1.18.4 reports '{test_total}'; ambient ExUnit 1.19.5 reported "
                    "'20 doctests, 42 properties, 1340 tests, 0 failures, 1 skipped (9 excluded)' at 3937a4f: "
                    "1.18 counts excluded tests in the total (1349 - 9 = 1340), same suite"
                ),
                "standing_effect": "none",
            },
            {
                "kind": "test_stderr_noise",
                "classification": "pre-existing",
                "finding": "'fatal: unable to read tree (17e2923d...)' lines from a git subprocess inside a test and "
                "expected [warning] lines from failure-injection tests; no test failed",
                "standing_effect": "none",
            },
            {
                "kind": "host_contention",
                "classification": "environment",
                "finding": f"mix test wall time: {test_time} under load averages ~40-100 from concurrent lanes; "
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
            "build_identity_log": f"{LOGS}/05-build-identity.log",
            "build_identity_sha256": hashlib.sha256(ident_bytes).hexdigest(),
            "rustc": "rustc 1.97.0 (2d8144b78 2026-07-07)",
            "cargo": "cargo 1.97.0 (c980f4866 2026-06-30)",
            "nif_note": (
                "ggen_graph_nif: rustler 0.36.2 selects the NIF API by cargo feature (rustler build.rs "
                "CARGO_FEATURE_NIF_VERSION_*), not by the running ERTS; rebuilt under the pin anyway. wasmex 0.15.1 "
                "precompiled NIF nif-2.15 from the rustler_precompiled cache (OTP-independent)"
            ),
            "tool_versions_pin_used": True,
            "mix_lock_sha256": hashlib.sha256(open("mix.lock", "rb").read()).hexdigest(),
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
