#!/usr/bin/env python3
"""Emit the machine-readable qualification receipt (acceptance rung J).

Everything in the receipt is READ BACK from artifacts a real run produced --
step exit codes, tree hashes, OCEL logs, resolved dependency versions, the
live database name. Nothing is asserted from intent. If an artifact is
missing, the corresponding field is null and `standing` degrades, rather
than the field being filled in from what the run was supposed to do.

Usage: receipt.py <fixture> <qualification-out-dir> > receipt.json
"""

import hashlib
import json
import os
import re
import subprocess
import sys


def sh(cmd, cwd=None):
    try:
        return subprocess.run(
            cmd, cwd=cwd, capture_output=True, text=True, shell=True, timeout=60
        ).stdout.strip()
    except Exception as exc:  # pragma: no cover - diagnostic path
        return "UNAVAILABLE: %s" % exc


def digest(path):
    if not os.path.exists(path):
        return None
    h = hashlib.sha256()
    with open(path, "rb") as fh:
        for chunk in iter(lambda: fh.read(65536), b""):
            h.update(chunk)
    return h.hexdigest()


def same(a, b):
    """True iff both files exist AND have identical content.

    The naive `digest(a) == digest(b)` is a live trap: digest() returns None
    for a missing file, so `None == None` is True and a comparison in which
    NEITHER artifact was ever produced reads as `identical`. That is the
    failure mode where an oracle that never ran certifies the standing it
    was supposed to test. Requiring digest(a) to be non-None makes a missing
    artifact read as NOT identical, which is the honest answer.
    """
    da = digest(a)
    return da is not None and da == digest(b)


def compare_state(a, b):
    """Classify a two-artifact comparison as identical / differs / absent.

    `same()` collapses "these differ" and "these were never captured" into
    one False, but a receipt must not report the first when it observed the
    second: "re-running ash.setup changed the schema" is a claim about an
    execution, and asserting it because a file is missing would be inventing
    a cause the run never showed. UNKNOWN means NOT EXERCISED.
    """
    da, db_ = digest(a), digest(b)
    if da is None or db_ is None:
        missing = [
            os.path.basename(p) for p, d in ((a, da), (b, db_)) if d is None
        ]
        return "absent:" + ",".join(missing)
    return "identical" if da == db_ else "differs"


def manifest_paths(path):
    """Parse a `shasum -a 256` manifest into {relative_path: hash}.

    Used to derive file provenance from the tree snapshots the harness took
    at day zero and after the final run, rather than guessing from a listing
    of the finished tree.
    """
    out = {}
    if not os.path.exists(path):
        return out
    for line in open(path):
        line = line.rstrip("\n")
        if not line.strip():
            continue
        h, _, rel = line.partition("  ")
        if rel.strip():
            out[rel.strip()] = h.strip()
    return out


def read_json(path):
    if not os.path.exists(path):
        return None
    with open(path) as fh:
        return json.load(fh)


def lock_versions(fixture):
    path = os.path.join(fixture, "mix.lock")
    if not os.path.exists(path):
        return {}
    text = open(path).read()
    out = {}
    for name, ver in re.findall(r'"([a-z_0-9]+)": \{:hex, :[a-z_0-9]+, "([^"]+)"', text):
        out[name] = ver
    return out


def main():
    fixture, out_dir = os.path.abspath(sys.argv[1]), os.path.abspath(sys.argv[2])
    pack = os.path.abspath(os.path.join(os.path.dirname(__file__), ".."))
    repo = os.path.abspath(os.path.join(pack, "..", "..", ".."))

    steps = []
    steps_path = os.path.join(out_dir, "steps.jsonl")
    if os.path.exists(steps_path):
        steps = [json.loads(line) for line in open(steps_path) if line.strip()]

    failed = [s for s in steps if s["exit"] != s["expected"]]
    conformance = read_json(os.path.join(out_dir, "conformance.json"))
    drift = read_json(os.path.join(out_dir, "drift.json"))
    guard_steps = {
        s["label"]: s["exit"] for s in steps if s["label"].startswith("guard-")
    }
    guard_alive = bool(guard_steps) and all(
        s["exit"] == s["expected"] for s in steps if s["label"].startswith("guard-")
    )

    t0 = os.path.join(out_dir, "T0-day-zero.sha256")
    t1 = os.path.join(out_dir, "T1-run1.sha256")
    t2 = os.path.join(out_dir, "T2-run2.sha256")
    t3 = os.path.join(out_dir, "T3-run3.sha256")
    d1 = os.path.join(out_dir, "D1-run1.txt")
    d2 = os.path.join(out_dir, "D2-run2.txt")
    d3 = os.path.join(out_dir, "D3-run3.txt")

    # FILESYSTEM oracle. T1 == T2 alone cannot tell a fixpoint from a
    # period-2 cycle, so the standing consumes the three-run form.
    tree_identical = same(t1, t2)
    tree_fixpoint = same(t1, t2) and same(t2, t3)

    # DATABASE oracle. `same` (not `==`) matters most here: before run 3
    # existed these files did not exist at all, and a bare digest comparison
    # would have reported the database "identical" on the strength of two
    # missing artifacts.
    db_pairs_identical = same(d1, d2) and same(d2, d3)

    # ...but two IDENTICAL captures are only evidence if the captures are
    # real. A psql connection failure writes the same error text to every
    # D-file, so all three compare equal and the oracle passes vacuously.
    # qualify.sh's db-nondegenerate step asserts D1 is a real schema; the
    # standing must therefore consume that step, not just the digests.
    nondegenerate_steps = [s for s in steps if s["label"] == "db-nondegenerate"]
    db_nondegenerate = bool(nondegenerate_steps) and all(
        s["exit"] == s["expected"] for s in nondegenerate_steps
    )
    db_identical = db_pairs_identical and db_nondegenerate

    check_steps = {
        s["label"]: s["exit"]
        for s in steps
        if s["label"].startswith("idempotency-check")
    }
    checks_clean = bool(check_steps) and all(v == 0 for v in check_steps.values())

    # A red standing must name WHICH oracle failed. "IDEMPOTENCY_ALIVE:
    # false" on its own sends a reader back to re-derive the cause from
    # steps.jsonl by hand.
    # Each entry states what was OBSERVED (differs / never captured), never
    # a cause inferred from a missing file.
    oracle_states = {
        "tree_T1_T2": compare_state(t1, t2),
        "tree_T2_T3": compare_state(t2, t3),
        "db_D1_D2": compare_state(d1, d2),
        "db_D2_D3": compare_state(d2, d3),
    }
    meaning = {
        "tree_T1_T2": "run 2 did not reproduce run 1's tree",
        "tree_T2_T3": "run 3 did not reproduce run 2's tree, so the "
        "manufacturing path has no demonstrated fixpoint",
        "db_D1_D2": "re-running `mix ash.setup` changed the schema",
        "db_D2_D3": "`mix ash.migrate` on run 3 changed the schema",
    }

    failed_oracles = []
    if not checks_clean:
        failed_oracles.append(
            "igniter_check: not every --check step exited 0 (see igniter_check_exits)"
        )
    for name, state in sorted(oracle_states.items()):
        if state == "identical":
            continue
        if state.startswith("absent:"):
            failed_oracles.append(
                "%s: UNKNOWN -- not exercised (missing %s)"
                % (name, state.split(":", 1)[1])
            )
        else:
            failed_oracles.append("%s: %s" % (name, meaning[name]))
    if not db_nondegenerate:
        failed_oracles.append(
            "db_nondegenerate: %s -- D1 was not shown to be a real schema "
            "capture, so every D-file comparison above is vacuous"
            % ("step did not run" if not nondegenerate_steps else "step failed")
        )

    ocel_docs = {}
    for run in ("run1", "run2", "run3"):
        d = os.path.join(out_dir, "ocel-" + run)
        if os.path.isdir(d):
            for name in sorted(os.listdir(d)):
                doc = read_json(os.path.join(d, name))
                if doc:
                    ocel_docs["%s/%s" % (run, name)] = {
                        "eventTypes": len(doc.get("eventTypes", [])),
                        "objectTypes": len(doc.get("objectTypes", [])),
                        "events": len(doc.get("events", [])),
                        "objects": len(doc.get("objects", [])),
                        "sha256": digest(os.path.join(d, name)),
                    }

    # Generated vs handwritten, decided by PROVENANCE.
    #
    # The previous implementation claimed provenance while actually running
    # `find` over the finished tree and subtracting one path by name. That
    # consults no provenance at all, and it shipped a receipt in which
    # config/config.exs, config/dev.exs, config/prod.exs and config/test.exs
    # appeared in `handwritten_day_zero` AND in `generated` simultaneously --
    # a self-contradiction inside a document whose whole purpose is to be
    # trusted about what happened.
    #
    # Real provenance is already on disk: T0 is the tree hashed immediately
    # after day_zero.sh and BEFORE any generator ran, and T3 (or T2) is the
    # tree after the last run. So:
    #   present in T0                      -> handwritten at day zero
    #   present in T0, hash changed by T3  -> handwritten, then a generator
    #                                         edited it in place
    #   absent from T0, present in T3      -> generated
    # The three sets are disjoint by construction, so the contradiction
    # above cannot recur.
    day_zero_tree = manifest_paths(t0)
    final_manifest = t3 if os.path.exists(t3) else t2
    final_tree = manifest_paths(final_manifest)

    handwritten_unchanged = sorted(
        p for p, h in day_zero_tree.items() if final_tree.get(p) == h
    )
    handwritten_modified = sorted(
        p
        for p, h in day_zero_tree.items()
        if p in final_tree and final_tree[p] != h
    )
    handwritten_removed = sorted(p for p in day_zero_tree if p not in final_tree)
    generated = sorted(p for p in final_tree if p not in day_zero_tree)

    caps = {}
    ttl = open(os.path.join(pack, "ontology.ttl")).read()
    for block in re.findall(r"amp:\w+ a amp:GeneratorCapability ;(.*?)\.\n", ttl, re.S):
        t = re.search(r'amp:mixTask "([^"]+)"', block)
        st = re.search(r'amp:standing "([^"]+)"', block)
        ad = re.search(r"amp:admitted (true|false)", block)
        ph = re.search(r'amp:phase "([^"]+)"', block)
        rr = re.search(r'amp:refusalReason "((?:[^"\\]|\\.)*)"', block, re.S)
        if t:
            caps[t.group(1)] = {
                "standing": st.group(1) if st else "UNKNOWN",
                "admitted": ad.group(1) == "true" if ad else None,
                "phase": ph.group(1) if ph else None,
                "refusal_reason": rr.group(1) if rr else None,
            }

    db_name = None
    p = os.path.join(out_dir, "db-name.txt")
    if os.path.exists(p):
        db_name = open(p).read().strip()

    standing = {
        "ONTOLOGY_ALIVE": any(s["label"] == "ggen-sync" and s["exit"] == 0 for s in steps),
        "ASH_MANUFACTURE_ALIVE": all(
            any(s["label"] == lbl and s["exit"] == 0 for s in steps)
            for lbl in (
                "manufacture-base-run1",
                "manufacture-core-run1",
                "compile-after-core",
                "ash-setup",
            )
        ),
        # Three conjuncts, because the claim has three parts: Igniter's own
        # semantic check is clean, the TREE reaches a fixpoint over three
        # runs, and the DATABASE is unchanged by re-entering the lifecycle.
        # The previous form (checks_clean and tree_identical) asserted
        # idempotency while no oracle had ever looked at Postgres.
        "IDEMPOTENCY_ALIVE": checks_clean and tree_fixpoint and db_identical,
        "OCEL_PROCESS_ALIVE": bool(ocel_docs)
        and bool(conformance)
        and conformance.get("conformant") is True,
        "AGENT_HANDWRITE_REFUSAL_ALIVE": guard_alive,
        # Distinct from ASH_MANUFACTURE_ALIVE on purpose. That one says the
        # generators ran and the output compiles; this one says a manufactured
        # Ash action was actually CALLED against a real database and returned
        # real state. Everything before rung M was consistent with a system
        # that generates perfect files and cannot execute a single action.
        "ASH_RUNTIME_ALIVE": all(
            any(s["label"] == lbl and s["exit"] == 0 for s in steps)
            for lbl in ("ash-setup-test-env", "manufactured-resources-execute")
        ),
    }

    receipt = {
        "schema": "ggen_igniter.qualification.receipt/1",
        "subject": {
            "repo": repo,
            "repo_head": sh("git rev-parse HEAD", cwd=repo),
            "repo_branch": sh("git rev-parse --abbrev-ref HEAD", cwd=repo),
            "repo_dirty": bool(sh("git status --porcelain", cwd=repo)),
            "fixture": os.path.relpath(fixture, repo),
            "pack": os.path.relpath(pack, repo),
        },
        "ontology": {
            "path": os.path.relpath(os.path.join(pack, "ontology.ttl"), repo),
            "sha256": digest(os.path.join(pack, "ontology.ttl")),
            "gates": {
                name: digest(os.path.join(pack, "gates", name))
                for name in sorted(os.listdir(os.path.join(pack, "gates")))
            },
            "template_sha256": digest(
                os.path.join(pack, "templates", "manufacture.ex.eex")
            ),
        },
        "toolchain": {
            "elixir": sh("elixir --version | tail -1"),
            "erlang": sh(
                "erl -noshell -eval 'io:format(\"~s\", "
                "[erlang:system_info(otp_release)]), halt().'"
            ),
            "postgres": sh("postgres -V"),
            "deps": lock_versions(fixture),
        },
        "capability_matrix": caps,
        "commands": steps,
        "failures": failed,
        "database_isolation": {
            "database": db_name,
            "evidence": (
                open(os.path.join(out_dir, "db-isolation.txt")).read().strip()
                if os.path.exists(os.path.join(out_dir, "db-isolation.txt"))
                else None
            ),
            "note": "The manufactured repo config was rewritten to a run-scoped "
            "database before any DB-touching lifecycle step, so a "
            "filesystem-disposable copy does not silently address the "
            "original database.",
        },
        "idempotency": {
            "igniter_check_exits": check_steps,
            "semantic_oracle": "mix book_library.manufacture --phase <p> --check "
            "-- Igniter halt_if_fails_check!/3 halts non-zero on any change, "
            "warning, issue, queued task, move or removal. Exit code alone from "
            "a normal run is NOT an oracle: issues return :issues without "
            "halting (igniter.ex:1279-1281).",
            "tree_T1_sha256": digest(t1),
            "tree_T2_sha256": digest(t2),
            "tree_T3_sha256": digest(t3),
            "tree_identical": tree_identical,
            "tree_fixpoint_T1_T2_T3": tree_fixpoint,
            "fixpoint_rationale": "T1 == T2 is consistent with a period-2 "
            "cycle as well as with a fixpoint. A third actuation is what "
            "separates them: only T2 == T3 makes 'the manufacturing path "
            "has a fixpoint' a tested claim.",
            "db_D1_sha256": digest(d1),
            "db_D2_sha256": digest(d2),
            "db_D3_sha256": digest(d3),
            "db_identical": db_identical,
            "db_nondegenerate": db_nondegenerate,
            "db_oracle": "bin/db_fingerprint.sql projects columns, "
            "constraints, indexes and applied migration versions. D1 is "
            "captured after run 1's `mix ash.setup`, D2 after a SECOND "
            "`mix ash.setup` in run 2, D3 after `mix ash.migrate` in run 3.",
            "db_oracle_scope": "D-files are comparable only WITHIN one "
            "qualification run's database. Index and constraint names are "
            "database-local -- Postgres names NOT NULL check constraints "
            "after the table OID (observed: `2200_69000_1_not_null`) -- so "
            "D-files from two different runs are EXPECTED to differ and a "
            "diff across runs would mean nothing. The oracle is 'this "
            "database did not change between lifecycle steps', never 'two "
            "runs produced the same database'.",
            "oracle_states": oracle_states,
            "failed_oracles": failed_oracles,
        },
        "ocel": ocel_docs,
        "conformance": conformance,
        "drift_check": drift,
        "agent_handwrite_refusal": {
            "hook": ".claude/hooks/refuse-handwritten-ash.sh",
            "wired_as": "PreToolUse Edit|Write in .claude/settings.json",
            "cases": guard_steps,
            "limit": "A content pattern-match, not a proof. It catches the "
            "observed failure mode (an agent writing `use Ash.Resource` "
            "directly) and will not catch every conceivable route to the "
            "same outcome.",
        },
        "files": {
            "provenance_basis": (
                "Derived from the tree manifests, not from a listing of the "
                "finished tree: %s (before any generator ran) vs %s (after "
                "the last run). The three lists are disjoint by construction."
                % (
                    os.path.basename(t0),
                    os.path.basename(final_manifest),
                )
            ),
            "handwritten_day_zero": handwritten_unchanged,
            "handwritten_then_generator_modified": handwritten_modified,
            "handwritten_removed_by_generators": handwritten_removed,
            "generated": generated,
        },
        # One command, not two. qualify.sh now runs receipt.py itself as rung
        # J, so the receipt is an artifact OF the run rather than a separate
        # hand-invoked account of it -- the previous two-step replay is what
        # let a receipt be written minutes after the run it described.
        "replay": "bash test/fixtures/ash_manufacture_pack/bin/qualify.sh",
        "standing": standing,
        "scope": "Scoped to THIS exact subject only: the book_library fixture at "
        "the dependency versions listed under toolchain.deps, on this machine, "
        "with a live local PostgreSQL. It is not a claim about other Ash "
        "projects, other dependency versions, or the Tier-1 tasks whose "
        "standing above is not ALIVE.",
    }

    json.dump(receipt, sys.stdout, indent=2, sort_keys=True)
    sys.stdout.write("\n")
    return 0 if not failed else 1


if __name__ == "__main__":
    sys.exit(main())
