#!/usr/bin/env python3
"""Resolve every `amp:Citation` anchor against real, pinned dependency source.

`bin/evidence_check.py` asserts that a cited file exists and that a cited
range fits inside it. Its own docstring concedes the rest: it "does NOT
attempt to verify that the cited lines say what the claim says". That gap is
not theoretical. Three off-by-N defects lived inside citations that check
passed:

  * `ash.gen.resource.ex:74` was cited for `ignore_if_exists` in the schema.
    Line 74 is `da: :string,`. The real line is 76.
  * `igniter/project/module.ex:475` was cited for `try_full_scan/3`.
    `defp try_full_scan` is on 474; 475 is its first body line.
  * `ash.gen.custom_expression.ex:46` was cited for the emitted `args: [...]`.
    Line 46 is blank. The real line is 45.

Each range was inside its file, so each passed. What distinguishes a correct
citation from a near-miss is not the range -- it is whether the range still
CONTAINS the thing being claimed. `amp:citesSymbol` states that token, and
this script asserts it.

Two failure classes, reported separately and on purpose:

  * PIN DRIFT -- an `amp:DependencyPin` disagrees with the subject's real
    `mix.lock`. Line numbers are version-scoped facts; a `mix deps.update`
    invalidates every anchor into that package at once. Reporting it as one
    cause, and suppressing that package's anchor misses, is the difference
    between "ash moved to 3.34.0, re-read the citations" and thirty-one
    separate mystery misses whose shared root the reader has to infer.
  * ANCHOR MISS -- the pin holds, so the file really did change under a
    citation that claims to describe it, or the citation was always wrong.

Deliberately no RDF library: the pack's checkers parse Turtle with the same
narrow regexes over a file this pack itself authors and controls, so the
qualification ladder has no dependency the manufacturing subject does not
already resolve.

Usage: citation_check.py <pack-dir> <fixture-dir>
Exit 0 = every anchor resolves and every pin matches. Exit 1 = at least one
does not.
"""

import json
import os
import re
import sys

# The subject's mix.lock line shape is an upstream CONTRACT (Mix writes it):
# `  "ash": {:hex, :ash, "3.33.1", "<sha>", ...`.
LOCK_ENTRY = re.compile(r'^\s*"([A-Za-z0-9_]+)":\s*\{:hex,\s*:[A-Za-z0-9_]+,\s*"([^"]+)"')

BLOCK = re.compile(r"amp:(\w+) a amp:%s ;(.*?)\.\n", re.S)


def blocks(text, cls):
    return re.findall(BLOCK.pattern % cls, text, re.S)


def literal(block, prop):
    """Return a Turtle string literal, unescaped, or a loud sentinel.

    A missing property must surface as a visible failure, never as a None that
    silently short-circuits a comparison into vacuous success.
    """
    m = re.search(r'amp:%s "((?:[^"\\]|\\.)*)"' % prop, block, re.S)
    if not m:
        return "<MISSING:%s>" % prop
    return m.group(1).replace('\\"', '"').replace("\\\\", "\\")


def integer(block, prop):
    m = re.search(r"amp:%s (\d+)" % prop, block)
    return int(m.group(1)) if m else None


def ref(block, prop):
    m = re.search(r"amp:%s (amp:\w+)" % prop, block)
    return m.group(1) if m else "<MISSING:%s>" % prop


def parse_pins(text):
    pins = {}
    for name, block in blocks(text, "DependencyPin"):
        pins["amp:" + name] = {
            "dep": literal(block, "pinnedDep"),
            "version": literal(block, "pinnedVersion"),
        }
    return pins


def parse_citations(text):
    out = []
    for name, block in blocks(text, "Citation"):
        start = integer(block, "citesLine")
        out.append(
            {
                "id": "amp:" + name,
                "file": literal(block, "citesFile"),
                "line": start,
                # An absent end line means a single line, not an unbounded
                # range -- the narrower reading, so a citation never claims
                # more territory than it wrote down.
                "end_line": integer(block, "citesEndLine") or start,
                "symbol": literal(block, "citesSymbol"),
                "supports": ref(block, "supports"),
                "cited_property": literal(block, "citedProperty"),
                "pin": ref(block, "citesPin"),
            }
        )
    return out


def parse_lock(path):
    if not os.path.exists(path):
        return None
    resolved = {}
    for line in open(path, errors="replace"):
        m = LOCK_ENTRY.match(line)
        if m:
            resolved[m.group(1)] = m.group(2)
    return resolved


def main():
    pack, fixture = sys.argv[1], sys.argv[2]
    text = open(os.path.join(pack, "ontology.ttl")).read()

    pins = parse_pins(text)
    citations = parse_citations(text)
    lock_path = os.path.join(fixture, "mix.lock")
    resolved = parse_lock(lock_path)

    pin_drift = []
    drifted_deps = set()

    if resolved is None:
        pin_drift.append("pin drift: %s does not exist, so no pin can be reconciled" % lock_path)
        drifted_deps = {p["dep"] for p in pins.values()}
    else:
        for pin in sorted(pins.values(), key=lambda p: p["dep"]):
            actual = resolved.get(pin["dep"])
            if actual is None:
                pin_drift.append(
                    "pin drift: %s declared %s, mix.lock does not resolve it at all"
                    % (pin["dep"], pin["version"])
                )
                drifted_deps.add(pin["dep"])
            elif actual != pin["version"]:
                pin_drift.append(
                    "pin drift: %s declared %s, mix.lock has %s"
                    % (pin["dep"], pin["version"], actual)
                )
                drifted_deps.add(pin["dep"])

    misses = []
    skipped = []
    checked = 0

    for c in citations:
        dep = pins.get(c["pin"], {}).get("dep", "<UNRESOLVED-PIN>")

        # Suppressed on purpose: with the pin broken every anchor into that
        # package is expected to miss, and thirty reports of a consequence
        # bury the one report of the cause.
        if dep in drifted_deps:
            skipped.append("%s (pin %s drifted)" % (c["id"], dep))
            continue

        full = os.path.join(fixture, c["file"])
        if not os.path.exists(full):
            misses.append(
                "%s: %s does not exist (expected %r at :%s)"
                % (c["id"], c["file"], c["symbol"], c["line"])
            )
            continue

        lines = open(full, errors="replace").read().splitlines()
        checked += 1

        first, last = c["line"], c["end_line"]
        if first is None or first < 1 or last > len(lines) or last < first:
            misses.append(
                "%s: %s:%s-%s is not a valid range in a %d-line file (expected %r)"
                % (c["id"], c["file"], first, last, len(lines), c["symbol"])
            )
            continue

        window = "\n".join(lines[first - 1 : last])
        if c["symbol"] not in window:
            misses.append(
                "%s: %s:%s-%s does not contain expected symbol %r -- "
                "the cited range no longer says what the claim says"
                % (c["id"], c["file"], first, last, c["symbol"])
            )

    result = {
        "anchors_checked": checked,
        "citations_declared": len(citations),
        "pins_declared": len(pins),
        "pin_drift": pin_drift,
        "misses": misses,
        "skipped_for_pin_drift": skipped,
        "all_anchored": not pin_drift and not misses,
    }
    json.dump(result, sys.stdout, indent=2, sort_keys=True)
    sys.stdout.write("\n")
    return 0 if result["all_anchored"] else 1


if __name__ == "__main__":
    sys.exit(main())
