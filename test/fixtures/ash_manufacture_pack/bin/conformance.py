#!/usr/bin/env python3
"""Conformance check: did the observed execution follow the ADMITTED process?

Reads the OCEL 2.0 logs the manufacture task emitted, the rendered plan the
task actually carries, the harness ledger, and the ontology's own capability
envelope, and answers questions that prose cannot:

  1. COVERAGE      - does every admitted plan step appear as exactly one
                     decision event? A step with zero decisions vanished
                     between render and execution; a step with two or more
                     means the stream double-counts, so every count derived
                     from it is wrong. A decision event with no plan step is
                     an event the plan never authorised.
  2. ADMISSION     - did any event compose a mix task the ontology does not
                     admit? (a single such event is a hard conformance
                     failure: it means ggen_igniter actuated an
                     inadmissible morphism)
  3. REFUSAL       - is every inadmissible capability represented by a real
                     `capability_refused` event, rather than silently
                     skipped?
  4. ORDER         - did phase `base` events precede phase `core` events,
                     and did guarded steps flip from `task_composed` in run
                     1 to `task_admission_refused` in run 2?
  5. SUBJECT       - does every subject a `task_composed` event claims to
                     have manufactured exist as a real file on disk?
  6. STRUCTURE     - is each log a structurally sound OCEL 2.0 document:
                     unique event ids, every event/object type declared,
                     every referenced object declared, no relationship
                     tuple repeated inside one event?
  7. LEDGER        - does each sealed log's recorded exit code agree with
                     the exit the harness ledger recorded for the same
                     manufacture step, and does the seal's own activity
                     follow from its own exit code?

Two honest limits, stated rather than hidden:

  * Check 5 reads the FINAL tree, because that is the only tree that
    exists when this runs. For run 1 it is therefore a POST-HOC check: it
    proves the file exists now, not that run 1 is what put it there. It
    still catches the failure this repo actually reproduced -- a run killed
    at the confirmation prompt left no `sort_by_title.ex` on disk and a log
    asserting its composition.
  * It deliberately performs NO statistical process control. Two runs are
    not a time series; Western-Electric rules over n=2 would be
    manufactured significance, not evidence. SPC becomes admissible only
    once a real run history exists.

The verdict names its own inputs (`ontology_sha256`, `gates_sha256`), so a
recorded green result can be checked against the ontology it was computed
from instead of being trusted on its filename.

Usage: conformance.py <fixture-root> <evidence-out-dir>

Exit 0 = conformant. Exit 1 = a real violation (reported in stdout JSON).
"""

import glob
import hashlib
import json
import os
import re
import sys

# CONTRACT (qualify.sh:132-171 label arguments): the harness records each
# manufacture invocation under the literal label `manufacture-<phase>-<run>`.
LEDGER_LABEL = "manufacture-%s-%s"

# CONTRACT (manufacture task `maybe_write_ocel/3`): a log is named
# `<task>.<phase>.ocel.json`, so the phase is the last dot-segment of the stem.
OCEL_SUFFIX = ".ocel.json"

# CONTRACT (ggen_igniter.ocel.seal.ex:43-44): the two seal activity names.
SEAL_APPLIED = "manufacture_run_applied"
SEAL_ABORTED = "manufacture_run_aborted"

# CONTRACT (the manufacture task's own event vocabulary): a plan step
# resolves to exactly one of these two, never both and never neither.
DECISION_TYPES = ("task_composed", "task_admission_refused")


def load_ocel(path):
    with open(path) as fh:
        return json.load(fh)


def sha256_file(path):
    h = hashlib.sha256()
    with open(path, "rb") as fh:
        h.update(fh.read())
    return h.hexdigest()


def events_of(doc):
    out = []
    for e in doc.get("events", []):
        attrs = {a["name"]: a["value"] for a in e.get("attributes", [])}
        rels = e.get("relationships", [])
        out.append(
            {
                "id": e["id"],
                "type": e["type"],
                "attrs": attrs,
                "objects": [(r["objectId"], r["qualifier"]) for r in rels],
                "task": next(
                    (
                        r["objectId"]
                        for r in rels
                        if r["qualifier"] == "generator"
                    ),
                    None,
                ),
                "subject": next(
                    (r["objectId"] for r in rels if r["qualifier"] == "subject"),
                    None,
                ),
            }
        )
    return out


def parse_admitted(ttl_path):
    """Extract (mix_task -> admitted?) from the ontology, without an RDF lib.

    Deliberately a narrow, literal parse of the exact shape this pack
    writes: any drift in that shape shows up as a missing capability rather
    than a silently wrong answer.
    """
    text = open(ttl_path).read()
    caps = {}
    for block in re.findall(
        r"amp:\w+ a amp:GeneratorCapability ;(.*?)\.\n", text, re.S
    ):
        task = re.search(r'amp:mixTask "([^"]+)"', block)
        adm = re.search(r"amp:admitted (true|false)", block)
        phase = re.search(r'amp:phase "([^"]+)"', block)
        if task and adm:
            caps[task.group(1)] = {
                "admitted": adm.group(1) == "true",
                "phase": phase.group(1) if phase else None,
            }
    return caps


# A plan field, wherever it sits: after `%{`, after a `,`, or at the start of
# its own line. Anchoring on the FIELD NAME rather than on layout keeps this
# parse alive across template reformatting; only a rename of the field itself
# breaks it, and that breaks loudly (zero steps) rather than silently.
def _field(name):
    return re.compile(r'(?:[{,]|^)\s*%s:\s*"([^"]*)"' % name, re.M)


_PLAN_FIELDS = ("phase", "step", "task", "subject")


def parse_plan(task_path):
    """Extract the rendered manufacturing plan from the composed Mix task.

    Splits on `%{` and keeps every fragment that carries all four join
    fields. `@refusals` entries carry none of them, so they drop out without
    needing to know where `@plan` ends -- which is what makes this survive a
    template that reorders or renames the surrounding attributes.
    """
    text = open(task_path).read()
    steps = []
    for chunk in text.split("%{"):
        found = {}
        for name in _PLAN_FIELDS:
            m = _field(name).search(chunk)
            if m:
                found[name] = m.group(1)
        if len(found) == len(_PLAN_FIELDS):
            steps.append(found)
    return steps


def underscore(module):
    """Elixir `Macro.underscore/1` semantics, for module -> lib-relative path.

    `Foo.BarBaz` -> `foo/bar_baz`. A run of capitals splits before the last
    one (`HTTPServer` -> `http_server`), matching Macro.underscore; getting
    that wrong would report a false missing file for any acronym-led module.
    """
    s = module.replace(".", "/")
    s = re.sub(r"([A-Z]+)([A-Z][a-z])", r"\1_\2", s)
    s = re.sub(r"([a-z\d])([A-Z])", r"\1_\2", s)
    return s.replace("-", "_").lower()


def load_ledger(path):
    """Read the harness step ledger as {label: record}.

    A duplicate label would let one step's exit code stand in for another's,
    so the caller is told rather than silently given the last one.
    """
    steps = {}
    dupes = []
    with open(path) as fh:
        for line in fh:
            line = line.strip()
            if not line:
                continue
            rec = json.loads(line)
            label = rec.get("label")
            if label is None:
                continue
            if label in steps:
                dupes.append(label)
            steps[label] = rec
    return steps, dupes


def check_structure(result, run, name, doc):
    """OCEL 2.0 structural integrity for one document.

    Existence of the four top-level keys says the document parses; it says
    nothing about whether the graph inside it closes. These five checks are
    what turn "has an events array" into "is a log you can join on".
    """
    where = "%s/%s" % (run, name)

    declared_event_types = {
        t.get("name") for t in doc.get("eventTypes", []) if isinstance(t, dict)
    }
    declared_object_types = {
        t.get("name") for t in doc.get("objectTypes", []) if isinstance(t, dict)
    }
    declared_object_ids = {
        o.get("id") for o in doc.get("objects", []) if isinstance(o, dict)
    }

    seen_ids = set()
    for e in doc.get("events", []):
        eid = e.get("id")
        if eid in seen_ids:
            result["violations"].append(
                "%s: duplicate event id %r -- two events share one identity, "
                "so any per-event join silently collapses them" % (where, eid)
            )
        seen_ids.add(eid)

        if e.get("type") not in declared_event_types:
            result["violations"].append(
                "%s: event %s has type %r which eventTypes does not declare"
                % (where, eid, e.get("type"))
            )

        tuples = {}
        for r in e.get("relationships", []):
            key = (r.get("objectId"), r.get("qualifier"))
            tuples[key] = tuples.get(key, 0) + 1
            if r.get("objectId") not in declared_object_ids:
                result["violations"].append(
                    "%s: event %s references undeclared objectId %r"
                    % (where, eid, r.get("objectId"))
                )
        for (oid, qual), count in sorted(tuples.items()):
            if count > 1:
                result["violations"].append(
                    "%s: event %s repeats relationship (objectId=%r, "
                    "qualifier=%r) %d times -- a duplicated edge inflates "
                    "every count taken over this log"
                    % (where, eid, oid, qual, count)
                )

    for o in doc.get("objects", []):
        if o.get("type") not in declared_object_types:
            result["violations"].append(
                "%s: object %r has type %r which objectTypes does not declare"
                % (where, o.get("id"), o.get("type"))
            )


def check_seal_ledger(result, run, name, doc, ledger, ledger_path):
    """Does the seal's recorded exit agree with the harness's own record?

    The seal is an observation supplied by the caller; the ledger is the
    caller's own record of the same invocation. If they disagree, one of the
    two is fiction, and the log stops being evidence either way.
    """
    where = "%s/%s" % (run, name)
    phase = name[: -len(OCEL_SUFFIX)].rsplit(".", 1)[-1]
    label = LEDGER_LABEL % (phase, run)

    seals = [
        e
        for e in doc.get("events", [])
        if e.get("type") in (SEAL_APPLIED, SEAL_ABORTED)
    ]
    for e in seals:
        attrs = {a["name"]: a["value"] for a in e.get("attributes", [])}
        seal_exit = attrs.get("exit")

        # The seal must be internally consistent before it is worth
        # comparing to anything else.
        expected_activity = SEAL_APPLIED if seal_exit == 0 else SEAL_ABORTED
        if e["type"] != expected_activity:
            result["violations"].append(
                "%s: seal %s records exit %r but is typed %s, not %s"
                % (where, e.get("id"), seal_exit, e["type"], expected_activity)
            )

        if label not in ledger:
            result["violations"].append(
                "%s: no ledger step labelled %r in %s, so the seal's exit %r "
                "is uncorroborated" % (where, label, ledger_path, seal_exit)
            )
            continue

        ledger_exit = ledger[label].get("exit")
        if ledger_exit != seal_exit:
            result["violations"].append(
                "%s: seal records exit %r but ledger step %r records exit %r"
                % (where, seal_exit, label, ledger_exit)
            )


def check_coverage(result, run, plan, run_events):
    """Join the rendered plan against the observed decision stream.

    Keyed on (phase, step, subject): `step` alone is not unique (two
    `gen_domain` steps, two `gen_resource` steps), and `subject` alone would
    not catch a step that ran in the wrong phase.
    """
    decisions = [e for e in run_events if e["type"] in DECISION_TYPES]

    observed = {}
    for e in decisions:
        key = (e["attrs"].get("phase"), e["attrs"].get("step"), e["subject"])
        observed.setdefault(key, []).append(e["id"])

    planned = {}
    for s in plan:
        planned.setdefault((s["phase"], s["step"], s["subject"]), []).append(s)

    # A phase that produced no decisions at all is ONE fact (the phase never
    # ran), not N facts. Reporting it per-step would bury the cause under its
    # own consequences.
    observed_phases = {k[0] for k in observed}
    silent_phases = set()
    for phase in sorted({s["phase"] for s in plan}):
        if phase not in observed_phases:
            silent_phases.add(phase)
            result["violations"].append(
                "%s: phase %r produced NO decision events, though the "
                "rendered plan carries %d step(s) for it"
                % (run, phase, sum(1 for s in plan if s["phase"] == phase))
            )

    for key in sorted(planned, key=lambda k: tuple("" if p is None else p for p in k)):
        phase, step, subject = key
        if phase in silent_phases:
            continue
        ids = observed.get(key, [])
        if not ids:
            result["violations"].append(
                "%s: plan step %s/%s (subject %s) produced NO decision event "
                "-- it vanished between render and execution"
                % (run, phase, step, subject)
            )
        elif len(ids) > len(planned[key]):
            result["violations"].append(
                "%s: plan step %s/%s (subject %s) produced %d decision events "
                "for %d planned occurrence(s) (%s) -- the stream double-counts"
                % (
                    run,
                    phase,
                    step,
                    subject,
                    len(ids),
                    len(planned[key]),
                    ", ".join(ids),
                )
            )

    for key in sorted(observed, key=lambda k: tuple("" if p is None else p for p in k)):
        if key not in planned:
            phase, step, subject = key
            result["violations"].append(
                "%s: decision event(s) %s claim step %s/%s (subject %s), which "
                "the rendered plan does not contain"
                % (run, ", ".join(observed[key]), phase, step, subject)
            )


def check_subjects_on_disk(result, run, fixture, composed):
    """Every composed subject must be a real file in the fixture tree.

    POST-HOC for run 1: this reads the tree as it stands now, which is the
    only tree that exists at check time. It still catches the reproduced
    failure where a log asserted a composition whose file never reached disk.
    """
    for subject in sorted({e["subject"] for e in composed if e["subject"]}):
        # A subject that does not start with an uppercase letter is not an
        # Elixir module and therefore manufactures no file of its own --
        # `ash.install`'s subject is the literal dependency name `ash`. The
        # rule is stated so it generalises, rather than special-casing `ash`.
        if not subject[:1].isupper():
            continue
        path = os.path.join(fixture, "lib", underscore(subject) + ".ex")
        if not os.path.isfile(path):
            result["violations"].append(
                "%s: task_composed claims subject %s but %s does not exist "
                "-- the log asserts a composition that never reached disk"
                % (run, subject, path)
            )


def main():
    if len(sys.argv) < 3:
        sys.stderr.write(
            "usage: conformance.py <fixture-root> <evidence-out-dir>\n"
        )
        return 2

    fixture = sys.argv[1]
    out_dir = sys.argv[2]
    pack = os.path.abspath(os.path.join(os.path.dirname(__file__), ".."))
    ontology_path = os.path.join(pack, "ontology.ttl")
    caps = parse_admitted(ontology_path)

    result = {
        "capabilities_declared": len(caps),
        "admitted": sorted(t for t, c in caps.items() if c["admitted"]),
        "not_admitted": sorted(t for t, c in caps.items() if not c["admitted"]),
        # The verdict names its own inputs. A recorded conformance.json whose
        # digests do not match today's pack describes an ontology that no
        # longer exists, and says so instead of reading as a current pass.
        "ontology_sha256": sha256_file(ontology_path),
        "gates_sha256": {
            os.path.basename(g): sha256_file(g)
            for g in sorted(glob.glob(os.path.join(pack, "gates", "*.rq")))
        },
        "runs": {},
        "violations": [],
        "spc": "NOT_APPLICABLE: n=2 runs is not a time series; no control "
        "limits are computed and none should be inferred.",
    }

    if not os.path.isdir(fixture):
        result["violations"].append(
            "fixture root %s is not a directory, so no subject can be "
            "checked against the tree it claims to have manufactured" % fixture
        )

    # The rendered plan is the ADMITTED process. Glob rather than hardcode the
    # task name: the pack renders one composed task per project.
    plan = []
    task_glob = os.path.join(fixture, "lib", "mix", "tasks", "*.manufacture.ex")
    matches = sorted(glob.glob(task_glob))
    if len(matches) != 1:
        result["violations"].append(
            "expected exactly ONE rendered manufacture task at %s, found %d "
            "(%s) -- refusing to guess which one is the plan"
            % (task_glob, len(matches), ", ".join(matches) or "none")
        )
    else:
        result["manufacture_task"] = matches[0]
        result["manufacture_task_sha256"] = sha256_file(matches[0])
        plan = parse_plan(matches[0])
        if not plan:
            result["violations"].append(
                "parsed ZERO plan steps out of %s -- the coverage join has no "
                "left-hand side, so its silence proves nothing" % matches[0]
            )
    result["plan_steps"] = len(plan)

    ledger = {}
    ledger_path = os.path.join(out_dir, "steps.jsonl")
    if not os.path.isfile(ledger_path):
        result["violations"].append(
            "no harness ledger at %s, so no seal's exit code can be "
            "corroborated" % ledger_path
        )
    else:
        ledger, dupes = load_ledger(ledger_path)
        for label in sorted(set(dupes)):
            result["violations"].append(
                "ledger %s records label %r more than once; one step's exit "
                "code would stand in for another's" % (ledger_path, label)
            )

    for run in ("run1", "run2"):
        ocel_dir = os.path.join(out_dir, "ocel-" + run)
        if not os.path.isdir(ocel_dir):
            result["violations"].append("missing OCEL directory for " + run)
            continue

        run_events = []
        for name in sorted(os.listdir(ocel_dir)):
            if not name.endswith(OCEL_SUFFIX):
                continue
            doc = load_ocel(os.path.join(ocel_dir, name))
            # H: the document must be a real OCEL 2.0 log, not a bag of events.
            for key in ("eventTypes", "objectTypes", "events", "objects"):
                if key not in doc:
                    result["violations"].append(
                        "%s/%s: missing required OCEL 2.0 key %r" % (run, name, key)
                    )
            check_structure(result, run, name, doc)
            # A log is only evidence of what HAPPENED if something observed
            # the outcome. The manufacture task emits from inside igniter/1,
            # before Igniter applies anything, so an unsealed log describes
            # intent, not effect.
            sealed = [
                e
                for e in doc.get("events", [])
                if e["type"] in (SEAL_APPLIED, SEAL_ABORTED)
            ]
            if not sealed:
                result["violations"].append(
                    "%s/%s: UNSEALED -- no manufacture_run_applied/aborted "
                    "event, so the log asserts composition that nothing "
                    "confirmed reached disk" % (run, name)
                )
            for e in sealed:
                if e["type"] == SEAL_ABORTED:
                    result["violations"].append(
                        "%s/%s: sealed as ABORTED" % (run, name)
                    )
            if ledger:
                check_seal_ledger(result, run, name, doc, ledger, ledger_path)

            run_events.extend(events_of(doc))

        composed = [e for e in run_events if e["type"] == "task_composed"]
        guarded_off = [
            e for e in run_events if e["type"] == "task_admission_refused"
        ]
        refused = [e for e in run_events if e["type"] == "capability_refused"]

        # 1. COVERAGE -- every admitted plan step decided exactly once.
        if plan:
            check_coverage(result, run, plan, run_events)

        # 2. ADMISSION -- nothing inadmissible may ever be composed.
        for e in composed:
            cap = caps.get(e["task"])
            if cap is None:
                result["violations"].append(
                    "%s: composed %s which the ontology does not declare"
                    % (run, e["task"])
                )
            elif not cap["admitted"]:
                result["violations"].append(
                    "%s: composed NOT-ADMITTED task %s (subject %s)"
                    % (run, e["task"], e["subject"])
                )

        # 3. REFUSAL -- every inadmissible capability must be visibly refused.
        refused_tasks = {e["task"] for e in refused}
        for task, cap in caps.items():
            if not cap["admitted"] and task not in refused_tasks:
                result["violations"].append(
                    "%s: inadmissible %s was silently skipped, not refused"
                    % (run, task)
                )

        # 4. ORDER -- base before core within the observed event stream.
        # Read the phases off run_events in EMITTED order. Bucketing by event
        # type first (composed, then guarded) would reorder the stream and
        # manufacture a false ordering violation, since on run 2 most base
        # steps are guarded and most core steps are composed.
        phases = [
            e["attrs"].get("phase")
            for e in run_events
            if e["attrs"].get("phase")
        ]
        seen_core = False
        for p in phases:
            if p == "core":
                seen_core = True
            elif p == "base" and seen_core:
                result["violations"].append(
                    "%s: a base-phase step ran after a core-phase step" % run
                )
                break

        # 5. SUBJECT -- the tree must carry what the log says was composed.
        if os.path.isdir(fixture):
            check_subjects_on_disk(result, run, fixture, composed)

        result["runs"][run] = {
            "events": len(run_events),
            "composed": sorted({e["task"] for e in composed}),
            "composed_count": len(composed),
            "decisions": len(composed) + len(guarded_off),
            "guarded_admission_refused": sorted(
                {e["subject"] for e in guarded_off}
            ),
            "capability_refused": sorted(refused_tasks),
        }

    # The run1 -> run2 guard flip.
    r1 = result["runs"].get("run1", {})
    r2 = result["runs"].get("run2", {})
    if r1 and r2:
        flipped = set(r2.get("guarded_admission_refused", [])) - set(
            r1.get("guarded_admission_refused", [])
        )
        result["guard_flip_run1_to_run2"] = sorted(flipped)
        if not flipped:
            result["violations"].append(
                "no guarded step flipped to admission-refused on run 2; the "
                "admission guards are not demonstrably doing anything"
            )

    result["conformant"] = not result["violations"]
    json.dump(result, sys.stdout, indent=2, sort_keys=True)
    sys.stdout.write("\n")
    return 0 if result["conformant"] else 1


if __name__ == "__main__":
    sys.exit(main())
