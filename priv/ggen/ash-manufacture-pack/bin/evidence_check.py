#!/usr/bin/env python3
"""Verify that every `amp:evidence` citation in the ontology resolves.

A capability's standing is only as good as the citation behind it, and an
unvalidated citation field degrades silently: an adversarial review of this
pack found `amp:evidence "deps/ash/lib/mix/tasks/ash.install.ex"` on a file
that does not exist (the real path is `.../mix/tasks/install/ash.install.ex`)
and an idempotency claim attributing a call to a file that does not contain
it. Nothing caught it, because `080_capabilities.rq` selects `?evidence`
without ever resolving it.

This check resolves them. It is the WEAKER of the pack's two citation checks
and is deliberately kept that way: it validates the human-readable prose in
`amp:evidence`. `bin/citation_check.py` validates the machine-readable
`amp:Citation` anchors, which additionally assert that the cited range still
CONTAINS the claimed symbol. Three off-by-N defects passed this file and were
caught only by that one, which is the measured value of the anchor.

Two things were raised here after that review.

1. CONTINUATION REFERENCES ARE RESOLVED. The old regex required a literal
   `deps/` prefix, so a citation of the form
   `deps/.../ash.extend.ex:40-52 (Info), :57 (compile), :264-277 (dispatch)`
   resolved exactly one of its three references and silently ignored the
   other two. A bare `:NNN` now resolves against the most recent `deps/` path
   in the same literal. A shorthand that carries a filename but no `deps/`
   prefix (`change.ex:23-25`) is NOT guessed at -- guessing a path would
   manufacture a resolution rather than check one.

2. THE LINE RANGE IS UNCONDITIONAL FOR ADMITTED CAPABILITIES. Ten of the
   twenty-five references used to be bare whole-file citations, and the set
   included `ash_postgres.install.ex` -- 643 lines, so citing it whole
   asserted nothing a reader could check while backing a live idempotency and
   guard claim. Every `amp:admitted true` capability is one this pack actually
   composes, so its idempotency claim is load-bearing and must name lines.
   `amp:admitted false` capabilities may still cite a file whole: their claim
   really is whole-file ("this file declares `use Igniter.Mix.Task`, and this
   pack never ran it"), and a line number would assert more than was observed.

Usage: evidence_check.py <pack-dir> <fixture-dir>
Exit 0 = every citation resolves and the floor holds. Exit 1 = it does not.
"""

import json
import os
import re
import sys

CITATION = re.compile(r"(deps/[A-Za-z0-9_./-]+\.(?:ex|exs|erl|rs))(?::(\d+)(?:-(\d+))?)?")

# A bare `:NNN` / `:NNN-MMM` continuation. The lookbehind is what keeps
# `change.ex:23-25` out: there the colon follows a word character, so the
# reference carries its own (unresolvable) filename and is left alone.
CONTINUATION = re.compile(r"(?<![\w./-]):(\d+)(?:-(\d+))?")

CAPABILITY = re.compile(r"amp:(\w+) a amp:GeneratorCapability ;(.*?)\.\n", re.S)


def references(literal):
    """Yield (path, first, last) for every resolvable reference, in order.

    Continuations bind to the nearest preceding `deps/` path, which is what
    the prose means and what a reader does by eye.
    """
    marks = []
    for m in CITATION.finditer(literal):
        marks.append(("path", m.start(), m.end(), m.groups()))
    for m in CONTINUATION.finditer(literal):
        # Skip a colon that is already inside a matched `deps/...:NNN`.
        if any(s <= m.start() < e for _, s, e, _ in marks):
            continue
        marks.append(("cont", m.start(), m.end(), m.groups()))

    marks.sort(key=lambda t: t[1])

    current = None
    for kind, _s, _e, groups in marks:
        if kind == "path":
            path, start, end = groups
            current = path
            yield path, start, end
        elif current is not None:
            start, end = groups
            yield current, start, end


def main():
    pack, fixture = sys.argv[1], sys.argv[2]
    text = open(os.path.join(pack, "ontology.ttl")).read()

    problems = []
    checked = 0
    bare = 0

    for name, block in CAPABILITY.findall(text):
        admitted = bool(re.search(r"amp:admitted true", block))
        task = re.search(r'amp:mixTask "([^"]+)"', block)
        task = task.group(1) if task else "amp:" + name

        for literal in re.findall(r'amp:evidence "((?:[^"\\]|\\.)*)"', block, re.S):
            found = list(references(literal))
            if not found:
                # A prose-only citation (a command that was run, a shell
                # transcript) is legitimate; only file references are
                # resolvable.
                continue

            for path, start, end in found:
                checked += 1
                full = os.path.join(fixture, path)
                if not os.path.exists(full):
                    problems.append("dangling citation: %s does not exist" % path)
                    continue

                total = sum(1 for _ in open(full, errors="replace"))

                if not start:
                    bare += 1
                    if admitted:
                        problems.append(
                            "%s is admitted, so its evidence must name lines: "
                            "%s is cited whole (%d lines), which asserts nothing "
                            "a reader can check" % (task, path, total)
                        )
                    continue

                first, last = int(start), int(end or start)
                if first < 1 or last > total:
                    problems.append(
                        "citation %s:%s-%s is outside the file (%d lines)"
                        % (path, first, last, total)
                    )

    result = {
        "citations_checked": checked,
        "whole_file_citations": bare,
        "problems": problems,
        "all_resolve": not problems,
    }
    json.dump(result, sys.stdout, indent=2, sort_keys=True)
    sys.stdout.write("\n")
    return 0 if not problems else 1


if __name__ == "__main__":
    sys.exit(main())
