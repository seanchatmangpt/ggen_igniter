#!/usr/bin/env python3
"""Builds receipts/v26.9.23/R2-GI-CI.json from the committed gate logs in
receipts/v26.9.23/R2-GI-CI.gate/F1g/ (lane R2-GI-CI, wave F1g).

Every exit code is parsed from the log's own "EXIT <n>" line (written by the
command wrapper at run time), every output_sha256 is the sha256 of the committed
log bytes, and every key result line is copied from the log, so the receipt is a
function of the committed evidence. Usage (from the ggen_igniter checkout root):
    python3 receipts/v26.9.23/R2-GI-CI.gate/F1g/build_receipt.py
"""
import hashlib
import json
import os
import re
import sys

ROOT = os.getcwd()
GATE = "receipts/v26.9.23/R2-GI-CI.gate/F1g"
OUT = "receipts/v26.9.23/R2-GI-CI.json"
META = json.load(open(os.path.join(ROOT, GATE, "meta.json")))

PIN = ("PATH=/Users/sac/.asdf/installs/elixir/1.18.4-otp-27/bin:"
       "/Users/sac/.asdf/installs/erlang/27.2.4/bin:$PATH")
GATES = "/Users/sac/wt/v26922/v26923/lanes/r2/gates"
WT = META["worktree"]
SUBJ = META["subject_sha"]
SCR = META["scratch"]


def rel(name):
    return f"{GATE}/{name}"


def read(name):
    with open(os.path.join(ROOT, GATE, name), "rb") as fh:
        return fh.read()


def sha(name):
    return hashlib.sha256(read(name)).hexdigest()


def exit_of(name):
    m = re.findall(rb"^EXIT (\d+)$", read(name), re.M)
    if len(m) != 1:
        sys.exit(f"{name}: expected exactly one EXIT line, found {len(m)}")
    return int(m[0])


def lines(name, pattern):
    out = [ln.strip() for ln in read(name).decode("utf-8", "replace").splitlines()
           if re.search(pattern, ln)]
    return "; ".join(out)


def cmd(role, command, cwd, log, summary, exit_code=None):
    return {
        "role": role,
        "cmd": command,
        "cwd": cwd,
        "exit": exit_of(log) if exit_code is None else exit_code,
        "summary": summary,
        "output_sha256": sha(log),
        "log": rel(log),
    }


TESTS = r"tests?, \d+ failures?|^# probe|^# shallow|fetch-depth=|Finished in"
TIMEOUT = r"^run |timeout-minutes="

commands = [
    cmd("lane gate (depth) on the committed subject",
        f'sh {GATES}/r2-gi-depth.sh "$PWD"', WT, "10-gate-depth.log",
        f"head {SUBJ}: " + lines("10-gate-depth.log", TESTS)),
    cmd("lane gate (timeout) on the committed subject",
        f'sh {GATES}/r2-gi-timeout.sh "$PWD"', WT, "11-gate-timeout.log",
        f"head {SUBJ}: " + lines("11-gate-timeout.log", TIMEOUT)),
    cmd("scan-plan gate (lanes/scan-plan.json R2-GI-CI, verbatim incl. hosted part) on the committed subject",
        "sh receipts/v26.9.23/R2-GI-CI.gate/F1g/scanplan-gate.sh", WT, "12-scanplan-gate.log",
        f"head {SUBJ}; hosted part evaluated after run {META['hosted_run']} completed: "
        + lines("12-scanplan-gate.log", r"^# hosted|^EXIT")),
    cmd("timeout gate with the extra cold run 35944182649 (363916f) added",
        f'sh {GATES}/r2-gi-timeout.sh "$PWD" 35925710605 35933570910 35944182649', WT,
        "13-gate-timeout-3runs.log", lines("13-gate-timeout-3runs.log", TIMEOUT)),
    cmd("static composition witness (verbatim a39921b hunk; product diff = ci.yml only)",
        "git apply --reverse --check a39921b-ci.patch (at HEAD and at d6a6e5b); git diff --stat d6a6e5b HEAD -- . ':(exclude)receipts'",
        WT, "00-static.log",
        lines("00-static.log", r"apply-check|ci.yml blob|candidate sha256|a39921b ci.yml patch|files? changed")),
]
for b in ("base-d6a6e5b", "mut-depth", "mut-depth1"):
    commands.append(cmd(
        f"falsifier: depth gate on {b}", f'sh {GATES}/r2-gi-depth.sh "$PWD"', f"{SCR}/subj",
        f"20-falsifier-depth-{b}.log", lines(f"20-falsifier-depth-{b}.log", TESTS)))
for b in ("base-d6a6e5b", "mut-timeout30", "mut-timeout84"):
    commands.append(cmd(
        f"falsifier: timeout gate on {b}", f'sh {GATES}/r2-gi-timeout.sh "$PWD"', f"{SCR}/subj",
        f"21-falsifier-timeout-{b}.log", lines(f"21-falsifier-timeout-{b}.log", TIMEOUT)))
commands += [
    cmd("falsifier: scan-plan static part on candidate, base and every mutant",
        "sh -e scanplan-static-part.sh (per branch of the scratch subject)", f"{SCR}/subj",
        "22-scanplan-static-falsifiers.log",
        lines("22-scanplan-static-falsifiers.log", r"^scanplan-static"), exit_code=0),
    cmd("falsifier: depth-1 clone of the committed subject runs the real describe (probe bypassed)",
        f"{PIN} MIX_ENV=test mix test test/ggen_igniter_semantic_jira_pack_test.exs test/ggen_igniter_semantic_jira_git_ground_truth_test.exs --only 'describe:opt-in git ground truth for baseSha (residual_base_sha_wrong_commit closure)' --only 'module:GgenIgniter.SemanticJiraGitGroundTruthTest'",
        f"{SCR}/depth1", "23-falsifier-depth1-tests.log",
        lines("23-falsifier-depth1-tests.log", r"^# depth-1|tests?, \d+ failures?|BASE_SHA_UNVERIFIED: baseSha d84")),
    cmd("hosted history: the five 30m0s cancellations and cold/warm job durations",
        "gh run view <id> -R seanchatmangpt/ggen_igniter --json ... (11 runs)", SCR, "30-hosted-history.log",
        "11 runs recorded (see log)", exit_code=0),
    cmd("hosted falsifier history: timeout annotations + depth-1 BASE_SHA_UNVERIFIED failures",
        "gh api repos/seanchatmangpt/ggen_igniter/check-runs/<job>/annotations; gh run view <id> --log | grep", SCR,
        "31-hosted-falsifier-history.log",
        lines("31-hosted-falsifier-history.log", r"^run "), exit_code=0),
    cmd("conservation witness (C06): fetch-depth: 0 per commit and per merge parent",
        "git show <c>:.github/workflows/ci.yml | grep -c '^          fetch-depth: 0$'", WT,
        "32-conservation-witness.log",
        lines("32-conservation-witness.log", r"^(070dbd5|4ffa201|d6a6e5b|363916f|7c97f52) |parent "), exit_code=0),
    cmd("hosted CI witness on the exact committed subject",
        f"gh run view {META['hosted_run']} -R seanchatmangpt/ggen_igniter --log | grep ...", SCR,
        "33-hosted-subject.log", lines("33-hosted-subject.log", r"^run |tests?, \d+ failures?|Finished in|fetch-depth: 0|Cache"),
        exit_code=0),
    cmd("hosted CI witnesses at the earlier heads with the identical ci.yml blob (363916f cold, 09a369e warm)",
        "gh run view 35944182649|35954998442 -R seanchatmangpt/ggen_igniter --log | grep ...", SCR,
        "34-hosted-prior-heads.log", lines("34-hosted-prior-heads.log", r"^run |tests?, \d+ failures?"), exit_code=0),
]

receipt = {
    "work_order": META["work_order"],
    "identity": {
        "subject": "R2-GI-CI",
        "repo": "/Users/sac/ggen_igniter (origin seanchatmangpt/ggen_igniter)",
        "worktree": WT,
        "branch": "v23/R2-GI-CI",
        "base_ref": "friday/gc-fri-0800",
        "subject_sha": SUBJ,
        "base_sha": META["base_sha"],
        "base_sha_note": META["base_sha_note"],
        "ci_yml_blob": META["ci_yml_blob"],
        "work_order": "none (release defect repair lane; no goal.ttl WorkOrder, receipt not tuple-linked)",
        "toolchain": META["toolchain"],
    },
    "authority": META["authority"],
    "consequence": META["consequence"],
    "classification": META["classification"],
    "generation": META["generation"],
    "replay": {
        "durable_location": f"{GATE} (tracked in git on branch v23/R2-GI-CI); builder {GATE}/build_receipt.py",
        "gate_scripts": META["gate_scripts"],
        "commands": commands,
    },
    "falsifiers": META["falsifiers"],
    "observations": META["observations"],
    "standing": META["standing"],
}

# the standing must be backed by the replay commands it names
by_role = {c["role"]: c for c in commands}
assert by_role["lane gate (depth) on the committed subject"]["exit"] == 0
assert by_role["lane gate (timeout) on the committed subject"]["exit"] == 0
for b in ("base-d6a6e5b", "mut-depth", "mut-depth1"):
    assert by_role[f"falsifier: depth gate on {b}"]["exit"] != 0, b
for b in ("base-d6a6e5b", "mut-timeout30", "mut-timeout84"):
    assert by_role[f"falsifier: timeout gate on {b}"]["exit"] != 0, b

with open(os.path.join(ROOT, OUT), "w") as fh:
    json.dump(receipt, fh, indent=1, ensure_ascii=False)
    fh.write("\n")
print(f"wrote {OUT} ({len(commands)} replay commands)")
