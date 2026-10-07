#!/usr/bin/env python3
"""Point every Mix env's repo config at a run-scoped database.

A filesystem-disposable fixture that still addresses a surviving database is
not a disposable subject. `bin/day_zero.sh` resets the tree; it cannot reset
Postgres. A previous run's `schema_migrations` rows plus this run's fresh
migration timestamps produce `relation "books" already exists`, which is a
collision with the PAST rather than a real defect in the run under test.

Both defects this file exists for were observed, not anticipated:

  1. dev only. Scoping `config/dev.exs` fixed the lifecycle rungs and left
     `config/test.exs` pointing at a shared `book_library_test`. Rung M (run
     the manufactured resources) then failed on exactly the same stale-table
     error, one config file over.
  2. The partition suffix. `mix ash_postgres.install` writes
     `database: "book_library_test#{System.get_env("MIX_TEST_PARTITION")}"`.
     Replacing the whole literal -- not just its prefix -- is deliberate:
     leaving the interpolation in place would append an unset partition and
     make the scoped name depend on an environment variable the harness does
     not control.

Isolation here is by NAMING, never by dropping. Dropping a database the
harness did not create is destructive and out of scope for a test harness;
old qualification databases are left on disk to be removed deliberately.

Usage: isolate_db.py <fixture-dir> <base-db-name> [env ...]
Prints one line per rewritten file. Exit 1 if a config exists but no
`database:` key was found in it -- a silent no-op rewrite is the failure mode
this whole file is about.
"""

import os
import re
import sys

# LINE-WISE, not a quoted-string match. `config/test.exs` really contains:
#     database: "book_library_test#{System.get_env("MIX_TEST_PARTITION")}",
# and a `"[^"]*"` pattern stops at the quote INSIDE the interpolation, leaving
# `MIX_TEST_PARTITION")}",` dangling. That is not hypothetical -- it produced
# `** (SyntaxError) syntax error before: 'MIX_TEST_PARTITION'` and took the
# whole manufacture run down. Replacing the entire value, up to an optional
# trailing comma, is the only form that survives interpolation.
DATABASE = re.compile(r'^(\s*)database:\s*.*?(,?)$', re.M)


def main():
    fixture, base = sys.argv[1], sys.argv[2]
    envs = sys.argv[3:] or ["dev", "test"]

    rewritten = 0
    problems = []

    for env in envs:
        path = os.path.join(fixture, "config", "%s.exs" % env)
        if not os.path.exists(path):
            # Day zero has no repo config at all; ash_postgres.install writes
            # it. Being called before that step is legitimate.
            print("%s: absent, skipped" % path)
            continue

        source = open(path).read()
        scoped = "%s_%s" % (base, env)
        new, n = DATABASE.subn(
            lambda m: '%sdatabase: "%s"%s' % (m.group(1), scoped, m.group(2)),
            source,
        )

        if n == 0:
            problems.append(
                "%s exists but declares no `database:` key -- the rewrite was "
                "a no-op and this env is NOT isolated" % path
            )
            continue

        open(path, "w").write(new)
        rewritten += 1
        print("%s: %d rewrite(s) -> %s" % (path, n, scoped))

    for p in problems:
        sys.stderr.write("isolate_db: %s\n" % p)

    return 1 if problems else 0


if __name__ == "__main__":
    sys.exit(main())
