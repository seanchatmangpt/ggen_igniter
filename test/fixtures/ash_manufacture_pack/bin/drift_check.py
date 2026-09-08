#!/usr/bin/env python3
"""Deterministic ontology <-> generated-invocation drift check.

The whole architecture rests on one claim: every `mix ash.*` argument the
manufacture task passes is DERIVED from a fact in the ontology, and every
fact in the ontology reaches a real generator argument. If that link ever
silently breaks -- a renamed attribute that stops being projected, a flag
someone hand-edits into the generated task -- the project keeps compiling
and the ontology quietly stops being the source of truth.

This check makes that failure loud. It parses the ontology and the RENDERED
task independently and compares them as sets, in both directions:

  * ontology -> invocation : every amp:Attribute / amp:Relationship /
    amp:Domain / amp:Resource / amp:enumValue / amp:defaultAction /
    admitted amp:SupportModule must appear in the rendered argv.
  * invocation -> ontology : every --attribute / --relationship value, every
    ash.gen.enum value, every --default-actions element and every composed
    mix task in the rendered argv must trace back to a fact.

Direction two is the one that catches hand-editing, so it is not optional.

POSITION, for the repeatable properties. amp:enumValue and amp:defaultAction
are object LISTS, and their order survives all the way into the manufactured
source: ash.gen.enum splits its csv and inspects it straight into the
`values:` list (deps/ash/lib/mix/tasks/gen/ash.gen.enum.ex:60-68), and
ash.gen.resource renders --default-actions straight into `defaults [...]`
(ash.gen.resource.ex:620). Reordering either csv is therefore a real change
to a real module, so a set-only comparison would pass a tree that no longer
manufactures what the ontology says. Both directions AND position are
checked, each with its own message.

INDEPENDENCE IS THE POINT, not an accident of how this grew. Every
derivation here reads the RAW GRAPH. This file does not import the
projection template and does not consume the gates' SPARQL results, so it
can still see a row a conjunctive gate silently dropped -- a checker fed by
the gates is structurally unable to notice a row the gates never emitted.
Do not refactor these derivations to share code with
templates/manufacture.ex.eex or with gates/*.rq: the duplication IS the
second opinion.

NON-VACUITY. Every collection carries a guard that fires when a
deliberately LOOSER detector finds a fact in the ontology text that the
strict structured parse produced no row for. Without it, a regex that
quietly stopped matching is indistinguishable from a genuinely clean run --
both print an empty drift list and exit 0.

Usage: drift_check.py <pack-dir> <rendered-task-file>
Exit 0 = no drift. Exit 1 = drift, itemised on stdout.
"""

import json
import re
import sys

# The amp: properties whose object is a LIST rather than a single literal.
# They are named here because the single-valued reader silently truncates
# them to their first element, which is the exact failure this file exists
# to make impossible.
REPEATABLE_PROPERTIES = ("enumValue", "defaultAction")


def projected_order(values):
    """The order in which a repeatable property's values reach the argv.

    The ontology declares NO rank property for either repeatable property,
    so Turtle declaration order is not load-bearing and cannot be the
    expected order -- amp:LoanStatusEnum declares out/returned/overdue while
    the manufactured module reads [:out, :overdue, :returned]. What the pack
    actually manufactures is a lexical sort.

    That rule is re-derived here rather than read out of gates/*.rq, so that
    deleting a gate's ORDER BY would surface as a position finding instead of
    silently redefining what "correct" means.
    """
    return sorted(values)


def enum_values_in_argv(argv):
    """Values csv of an ash.gen.enum invocation, or None when absent.

    UPSTREAM CONTRACT, not a choice made here: ash.gen.enum declares
    `positional: [:module_name, :types]`
    (deps/ash/lib/mix/tasks/gen/ash.gen.enum.ex:34), so the values arrive as
    the SECOND POSITIONAL. There is no --types flag to read; the task
    declares no such option, and strict option validation would reject one.

    None (rather than []) distinguishes "the csv is missing from the
    invocation" from "the csv is present and empty", which are different
    defects and must not collapse into the same report.
    """
    if len(argv) < 2 or argv[1].startswith("--"):
        return None
    return argv[1].split(",")


def parse_ontology(path):
    text = open(path).read()

    def blocks(cls):
        return re.findall(r"amp:(\w+) a amp:%s ;(.*?)\.\n" % cls, text, re.S)

    def one(block, prop):
        """Return a literal, or a loud sentinel -- never None.

        A missing property must show up as visible drift, not as a None
        that silently poisons a join.
        """
        m = re.search(r'amp:%s "([^"]*)"' % prop, block)
        return m.group(1) if m else "<MISSING:%s>" % prop

    def many(block, prop):
        """Every literal of a REPEATABLE property, in declaration order.

        one() cannot be bent to do this. It is structurally single-valued --
        re.search returns the first match and stops -- so against
        `amp:enumValue "out" , "returned" , "overdue"` it yields "out" and
        the other two values are never compared against anything at all.

        The object list is anchored at the property and consumed as a
        comma-separated run of quoted literals, so it terminates naturally at
        the `;` or `.` that ends the predicate rather than running on into
        the next one.
        """
        m = re.search(
            r'amp:%s\s+((?:"(?:[^"\\]|\\.)*"\s*,\s*)*"(?:[^"\\]|\\.)*")' % prop,
            block,
        )
        if not m:
            return []
        return re.findall(r'"((?:[^"\\]|\\.)*)"', m.group(1))

    def flag(block, prop):
        m = re.search(r"amp:%s (true|false)" % prop, block)
        return m.group(1) == "true" if m else False

    # amp:attributeOf points at a subject IRI; resolve it to that
    # resource's module name so the comparison is by real identity rather
    # than by a string that merely looks similar.
    resource_module = {}
    for name, block in blocks("Resource"):
        resource_module["amp:" + name] = one(block, "resourceModule")

    support_module = {}
    for name, block in blocks("SupportModule"):
        support_module["amp:" + name] = one(block, "supportModuleName")

    def ref(block, prop):
        m = re.search(r"amp:%s (amp:\w+)" % prop, block)
        return m.group(1) if m else "<MISSING:%s>" % prop

    attributes = []
    for _, block in blocks("Attribute"):
        mods = []
        if flag(block, "isPublic"):
            mods.append("public")
        if flag(block, "isRequired"):
            mods.append("required")
        if flag(block, "isSensitive"):
            mods.append("sensitive")
        attributes.append(
            {
                "resource": resource_module.get(ref(block, "attributeOf"), "<UNRESOLVED>"),
                "flag": ":".join(
                    [one(block, "attributeName"), one(block, "attributeType")] + mods
                ),
            }
        )

    relationships = []
    for _, block in blocks("Relationship"):
        mods = []
        if flag(block, "relationshipPublic"):
            mods.append("public")
        kind = one(block, "relationshipKind")
        if kind == "belongs_to" and flag(block, "relationshipRequired"):
            mods.append("required")
        relationships.append(
            {
                "resource": resource_module.get(ref(block, "relationshipOf"), "<UNRESOLVED>"),
                "flag": ":".join(
                    [
                        kind,
                        one(block, "relationshipName"),
                        resource_module.get(ref(block, "relationshipTarget"), "<UNRESOLVED>"),
                    ]
                    + mods
                ),
            }
        )

    caps = {}
    for _, block in blocks("GeneratorCapability"):
        caps[one(block, "mixTask")] = flag(block, "admitted")

    supports = []
    for _, block in blocks("SupportModule"):
        supports.append(
            {
                "module": one(block, "supportModuleName"),
                "kind": one(block, "supportKind"),
                "enum_values": many(block, "enumValue"),
            }
        )

    default_actions = []
    for _, block in blocks("Resource"):
        module = one(block, "resourceModule")
        for value in many(block, "defaultAction"):
            default_actions.append({"resource": module, "value": value})

    domains = [one(b, "domainModule") for _, b in blocks("Domain")]
    resources = [one(b, "resourceModule") for _, b in blocks("Resource")]
    extensions = [
        {
            "resource": resource_module.get(ref(b, "extensionOf"), "<UNRESOLVED>"),
            "name": one(b, "extensionName"),
        }
        for _, b in blocks("Extension")
    ]

    # --- non-vacuity guards -------------------------------------------------
    # Each guard re-detects the fact with a DELIBERATELY LOOSER pattern than
    # the structured parse used above. Sharing the strict pattern would make
    # the guard vacuous in exactly the case it exists for: when that pattern
    # is what broke. A loose hit with zero strict rows means the PARSE
    # changed, not the ontology, and that has to be louder than silence.
    parse_failures = []

    def guard_class(cls, rows):
        if re.search(r"(?m)^amp:\w+ a amp:%s\b" % cls, text) and not rows:
            parse_failures.append(
                "PARSE VACUOUS: ontology declares amp:%s instances but the "
                "block parse produced no rows" % cls
            )

    def guard_property(prop, rows):
        if re.search(r'amp:%s\s+"' % prop, text) and not rows:
            parse_failures.append(
                "PARSE VACUOUS: ontology asserts amp:%s literals but the "
                "parse produced no rows" % prop
            )

    guard_class("Domain", domains)
    guard_class("Resource", resources)
    guard_class("Attribute", attributes)
    guard_class("Relationship", relationships)
    guard_class("Extension", extensions)
    guard_class("SupportModule", supports)
    guard_class("GeneratorCapability", caps)
    repeatable_rows = {
        "enumValue": [v for s in supports for v in s["enum_values"]],
        "defaultAction": default_actions,
    }
    for prop in REPEATABLE_PROPERTIES:
        guard_property(prop, repeatable_rows[prop])

    # An ordering property would make declaration order load-bearing and move
    # the expected order off projected_order()'s lexical sort. Reporting its
    # ABSENCE keeps the position check's authority explicit, so a sort is
    # never mistaken for a declared sequence. The list empties itself once
    # such a property is added.
    unranked = [
        "amp:" + prop
        for prop in REPEATABLE_PROPERTIES
        if not re.search(r"amp:%sOrder\b" % prop, text)
    ]

    return {
        "domains": domains,
        "resources": resources,
        "attributes": attributes,
        "relationships": relationships,
        "supports": supports,
        "default_actions": default_actions,
        "capabilities": caps,
        "extensions": extensions,
        "parse_failures": parse_failures,
        "unranked_repeatable": unranked,
    }


def parse_rendered(path):
    """Read the @plan literal out of the rendered task, without eval."""
    text = open(path).read()
    steps = []
    for m in re.finditer(
        r'task:\s*"([^"]+)",\s*\n\s*argv:\s*\[(.*?)\],\s*\n', text, re.S
    ):
        task = m.group(1)
        argv = re.findall(r'"((?:[^"\\]|\\.)*)"', m.group(2))
        argv = [a.replace('\\"', '"') for a in argv]
        steps.append({"task": task, "argv": argv})
    return steps


def values_after(argv, flag):
    return [argv[i + 1] for i, a in enumerate(argv) if a == flag and i + 1 < len(argv)]


def main():
    pack, rendered = sys.argv[1], sys.argv[2]
    onto = parse_ontology(pack + "/ontology.ttl")
    steps = parse_rendered(rendered)

    # A vacuous parse invalidates every comparison below it, so those
    # failures lead the report rather than trailing the findings they
    # would otherwise be silently responsible for.
    drift = list(onto["parse_failures"])

    if not steps:
        drift.append("rendered task contains no parseable @plan steps")

    by_resource = {}
    for s in steps:
        if s["task"] == "ash.gen.resource" and s["argv"]:
            by_resource[s["argv"][0]] = s["argv"]

    by_enum_step = {}
    for s in steps:
        if s["task"] == "ash.gen.enum" and s["argv"]:
            by_enum_step[s["argv"][0]] = s["argv"]

    onto_actions = {}
    for da in onto["default_actions"]:
        onto_actions.setdefault(da["resource"], []).append(da["value"])

    composed_tasks = {s["task"] for s in steps}

    # --- direction 1: every fact must reach an invocation -----------------
    for d in onto["domains"]:
        if not any(s["task"] == "ash.gen.domain" and d in s["argv"] for s in steps):
            drift.append("ontology domain %s is not manufactured by any step" % d)

    for r in onto["resources"]:
        if r not in by_resource:
            drift.append("ontology resource %s is not manufactured by any step" % r)

    for a in onto["attributes"]:
        argv = by_resource.get(a["resource"], [])
        if a["flag"] not in values_after(argv, "--attribute"):
            drift.append(
                "attribute %r of %s is in the ontology but not in the invocation"
                % (a["flag"], a["resource"])
            )

    for rel in onto["relationships"]:
        argv = by_resource.get(rel["resource"], [])
        if rel["flag"] not in values_after(argv, "--relationship"):
            drift.append(
                "relationship %r of %s is in the ontology but not in the invocation"
                % (rel["flag"], rel["resource"])
            )

    for ext in onto["extensions"]:
        argv = by_resource.get(ext["resource"], [])
        joined = ",".join(values_after(argv, "--extend"))
        if ext["name"] not in joined.split(","):
            drift.append(
                "extension %r of %s is in the ontology but not in the invocation"
                % (ext["name"], ext["resource"])
            )

    for sup in onto["supports"]:
        task = "ash.gen." + sup["kind"]
        admitted = onto["capabilities"].get(task, False)
        present = any(s["task"] == task and sup["module"] in s["argv"] for s in steps)
        if admitted and not present:
            drift.append(
                "admitted support module %s (%s) is not manufactured" % (sup["module"], task)
            )
        if not admitted and present:
            drift.append(
                "NOT-ADMITTED %s was projected into the invocation for %s"
                % (task, sup["module"])
            )

    # --- direction 1, repeatable: enum values ------------------------------
    for sup in onto["supports"]:
        if sup["kind"] != "enum":
            if sup["enum_values"]:
                drift.append(
                    "support module %s carries amp:enumValue facts but its "
                    "amp:supportKind is %r, so no generator argument can ever "
                    "carry them" % (sup["module"], sup["kind"])
                )
            continue

        if not sup["enum_values"]:
            drift.append(
                "enum support module %s declares no amp:enumValue; "
                "ash.gen.enum would manufacture an empty values list"
                % sup["module"]
            )
            continue

        argv = by_enum_step.get(sup["module"])
        if argv is None:
            # Absence of the whole step is already reported by the support
            # module check above; repeating it once per value would bury it.
            continue

        found = enum_values_in_argv(argv)
        if found is None:
            # Not a silent pass: the missing-csv case is reported once, by
            # name, in the direction-2 pass below, which sees every enum step
            # rather than only those with ontology facts behind them.
            continue

        expected = projected_order(sup["enum_values"])
        for v in expected:
            if v not in found:
                drift.append(
                    "enum value %r of %s is in the ontology but not in the "
                    "invocation" % (v, sup["module"])
                )
        # Order is only meaningful once both sides hold the same values.
        # Complaining about the order of a list that is already missing a
        # value would report a second defect that has no separate fix.
        if found != expected and sorted(found) == sorted(expected):
            drift.append(
                "enum values of %s are in the wrong order: invocation has %s, "
                "ontology projects %s"
                % (sup["module"], ",".join(found), ",".join(expected))
            )

    # --- direction 1, repeatable: default actions --------------------------
    for resource, values in sorted(onto_actions.items()):
        argv = by_resource.get(resource, [])
        groups = values_after(argv, "--default-actions")
        if not groups:
            drift.append(
                "resource %s declares amp:defaultAction but the invocation "
                "passes no --default-actions" % resource
            )
            continue

        found = ",".join(groups).split(",")
        expected = projected_order(values)
        for v in expected:
            if v not in found:
                drift.append(
                    "default action %r of %s is in the ontology but not in "
                    "the invocation" % (v, resource)
                )
        if found != expected and sorted(found) == sorted(expected):
            drift.append(
                "default actions of %s are in the wrong order: invocation has "
                "%s, ontology projects %s"
                % (resource, ",".join(found), ",".join(expected))
            )

    # --- direction 2: every invocation must trace back to a fact ----------
    # This is the direction that catches a hand-edit of the generated task.
    known_attr = {(a["resource"], a["flag"]) for a in onto["attributes"]}
    known_rel = {(r["resource"], r["flag"]) for r in onto["relationships"]}
    known_ext = {(e["resource"], e["name"]) for e in onto["extensions"]}

    for resource, argv in by_resource.items():
        if resource not in onto["resources"]:
            drift.append("invocation manufactures %s which the ontology does not declare" % resource)
        for v in values_after(argv, "--attribute"):
            if (resource, v) not in known_attr:
                drift.append(
                    "invocation passes --attribute %r for %s with no ontology fact behind it"
                    % (v, resource)
                )
        for v in values_after(argv, "--relationship"):
            if (resource, v) not in known_rel:
                drift.append(
                    "invocation passes --relationship %r for %s with no ontology fact behind it"
                    % (v, resource)
                )
        for group in values_after(argv, "--extend"):
            for v in group.split(","):
                if (resource, v) not in known_ext:
                    drift.append(
                        "invocation passes --extend %r for %s with no ontology fact behind it"
                        % (v, resource)
                    )
        # Iterated over every MANUFACTURED resource, not only those carrying
        # amp:defaultAction facts, so a csv invented for a resource with no
        # such facts at all is still caught.
        for group in values_after(argv, "--default-actions"):
            for v in group.split(","):
                if v not in onto_actions.get(resource, []):
                    drift.append(
                        "invocation passes default action %r for %s with no "
                        "ontology fact behind it" % (v, resource)
                    )

    enum_facts = {s["module"]: s["enum_values"] for s in onto["supports"] if s["kind"] == "enum"}

    for module, argv in sorted(by_enum_step.items()):
        found = enum_values_in_argv(argv)
        if found is None:
            drift.append(
                "ash.gen.enum step for %s carries no values csv; ash.gen.enum "
                "declares positional [:module_name, :types]" % module
            )
            continue
        for v in found:
            if v not in enum_facts.get(module, []):
                drift.append(
                    "invocation passes enum value %r for %s with no ontology "
                    "fact behind it" % (v, module)
                )

    for task in sorted(composed_tasks):
        if task not in onto["capabilities"]:
            drift.append("invocation composes %s which the ontology does not declare" % task)
        elif not onto["capabilities"][task]:
            drift.append("invocation composes NOT-ADMITTED task %s" % task)

    result = {
        "rendered_task": rendered,
        "steps": len(steps),
        "ontology_counts": {
            "domains": len(onto["domains"]),
            "resources": len(onto["resources"]),
            "attributes": len(onto["attributes"]),
            "relationships": len(onto["relationships"]),
            "extensions": len(onto["extensions"]),
            "support_modules": len(onto["supports"]),
            "enum_values": sum(len(s["enum_values"]) for s in onto["supports"]),
            "default_actions": len(onto["default_actions"]),
        },
        # Repeatable properties whose position this run enforced by lexical
        # sort because the graph declares no rank for them. Emitted so the
        # ordering's provenance is machine-visible rather than assumed.
        "unranked_repeatable_properties": onto["unranked_repeatable"],
        "drift": drift,
        "no_drift": not drift,
    }
    json.dump(result, sys.stdout, indent=2, sort_keys=True)
    sys.stdout.write("\n")
    return 0 if not drift else 1


if __name__ == "__main__":
    sys.exit(main())
