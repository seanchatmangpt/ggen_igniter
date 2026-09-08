#!/usr/bin/env bash
# PreToolUse guard: refuse hand-authored Ash domains/resources where the
# qualified ggen_igniter -> Igniter/Ash manufacturing path already owns the
# semantic mutation.
#
# This exists because of a real failure, not a hypothetical one. In the
# Next Read / xaas attempt an agent reasoned "I know Ash syntax", wrote
# `lib/xaas/library/book.ex` and friends directly, and thereby bypassed
# `mix ash.gen.domain`'s `config :app, ash_domains:` registration,
# `mix ash.gen.resource`'s attribute/action/accept derivation, and
# `mix ash_postgres.install`'s repo wiring. The files looked right and the
# project was wrong. See AGENTS.md.
#
# ## Input protocol
#
# A PreToolUse hook receives the tool call as JSON on STDIN
# (`{"tool_name":..., "tool_input":{"file_path":..., "content"|"new_string":...}}`).
# An earlier revision of this guard read `$CLAUDE_TOOL_INPUT`/`$CLAUDE_FILE_PATH`
# only, which meant it saw an empty string in production and exited 0 --
# it FAILED OPEN, and its passing qualification cases were passing against a
# code path that never runs for real. Stdin is now the primary source and
# the environment variables are a fallback, so the guard is exercised the
# same way it is invoked.
#
# ## Why the body is extracted by walking, not by key lookup
#
# A later revision read the body from four hardcoded keys (`content`,
# `new_string`, `new_str`, `replace_all_string`) and fell back to scanning the
# raw payload only when path AND body were both empty. A MultiEdit-shaped call
# carries its body under `edits[].new_string`, so it yielded a non-empty path
# and an empty body -- past the fallback, straight to `exit 0`. Measured: a
# resource header inside `edits[]` was ALLOWED. `NotebookEdit` was blocked only
# by accident, because `notebook_path` was also unrecognised and both
# extractions came back empty; teaching the parser that one key alone would
# have flipped it from blocked to allowed.
#
# So the parser now walks `tool_input` recursively and joins every string leaf
# except the path keys and `old_string`/`old_str`. Excluding the pre-edit side
# is deliberate: an Edit that DELETES a resource header must not be refused.
# The settings matcher is the regex `Edit|Write`, so every present and future
# *Edit tool is in scope and none of them can introduce a new body key that
# this parser does not already see.
#
# Contract: exit 2 blocks the tool call and shows stderr to the agent.
# Exit 0 allows it. Deliberately narrow -- it fires only on content that
# declares an Ash resource or domain, never on ordinary Elixir.

set -uo pipefail

payload=""
if [ ! -t 0 ]; then
  payload="$(cat 2>/dev/null || true)"
fi

path=""
input=""
suspicious=""

if [ -n "$payload" ]; then
  # Parse with python3 rather than grep: a `content` field is arbitrary
  # source text containing quotes and newlines, and a regex over it would
  # both miss real cases and invent false ones.
  parsed="$(
    printf '%s' "$payload" | python3 -c '
import json, posixpath, sys

# Keys that carry a FILE PATH rather than file content.
PATH_KEYS = ("file_path", "path", "notebook_path")
# The pre-edit side of an edit. Excluded so that removing a resource header
# is not itself treated as authoring one.
SKIP_KEYS = ("old_string", "old_str")

try:
    doc = json.load(sys.stdin)
except Exception:
    # Signal "unparseable" to the caller so it can fall back to a raw scan.
    # Exiting 0 with empty output would be indistinguishable from a valid
    # call with nothing to inspect, which is the difference between failing
    # closed and failing open.
    sys.exit(1)

tool_input = doc.get("tool_input")
if not isinstance(tool_input, dict):
    tool_input = {}

paths = []
bodies = []


def walk(node, key):
    if isinstance(node, dict):
        for k, v in node.items():
            walk(v, k)
    elif isinstance(node, list):
        for v in node:
            walk(v, key)
    elif isinstance(node, str):
        if key in PATH_KEYS:
            paths.append(node)
        elif key not in SKIP_KEYS:
            bodies.append(node)


walk(tool_input, None)

path = paths[0] if paths else ""
suspicious = ""
if path:
    # The allowlist below glob-matches the path. Unnormalised, that is a
    # bypass: `/x/lib/mix/tasks/../app/book.ex` matches the mix-tasks
    # allowlist and resolves to an ordinary lib/ resource. Measured allowed.
    path = posixpath.normpath(path)
    if ".." in path.split("/"):
        # A traversal that survives normalisation cannot be reasoned about,
        # so it forfeits the allowlist entirely rather than matching by luck.
        suspicious = "1"

# NOT a NUL separator: bash strips NUL bytes out of command substitution
# entirely, which silently merged the fields and made the guard
# mis-classify. \x1f (unit separator) survives. The body is emitted LAST so
# the two fixed-width-ish fields can be split off by prefix expansion even
# though the body contains newlines.
sys.stdout.write(path + "\x1f" + suspicious + "\x1f" + "\n".join(bodies))
' 2>/dev/null
  )"
  rc=$?

  if [ "$rc" -eq 0 ]; then
    path="${parsed%%$'\x1f'*}"
    rest="${parsed#*$'\x1f'}"
    suspicious="${rest%%$'\x1f'*}"
    input="${rest#*$'\x1f'}"
  fi
fi

# If the payload arrived but did NOT parse as JSON -- or parsed but carried
# neither a path nor a body, meaning the tool call does not follow the
# protocol this parser knows -- do not fail open: an unrecognised tool call is
# exactly when a guard is least entitled to assume innocence. Fall back to
# scanning the raw payload. This is coarser (it can see an Ash construct
# inside an unrelated field) but it errs toward refusing, and the refusal
# message names the ambiguity.
if [ -n "$payload" ] && [ -z "$path" ] && [ -z "$input" ]; then
  input="$payload"
  path=""
  suspicious=""
fi

# Fallback for clients that expose the call through the environment instead.
[ -n "$path" ] || path="${CLAUDE_FILE_PATH:-}"
[ -n "$input" ] || input="${CLAUDE_TOOL_INPUT:-}"

# Nothing to inspect -> nothing to refuse.
[ -n "$input" ] || exit 0

# Only .ex files can define an Ash resource/domain. An empty path is NOT
# treated as "not an .ex file": the content is still inspected, so a client
# that omits the path cannot smuggle a resource past the guard.
#
# This gate is also why an allowlist row for `*.eex`/`*.ttl`/`*.rq`/`*.md`
# would be unreachable: those extensions exit here, several branches earlier.
case "$path" in
  *.ex|*.exs) ;;
  "") ;;
  *) exit 0 ;;
esac

# ---- allowlist: surfaces ALLOWED to mention these constructs --------------
# * pack templates (they MODEL the constructs), anchored to the two real pack
#   roots -- an unanchored `*/templates/*` allowed a resource in ANY directory
#   named templates, anywhere
# * any manufactured mix task (it COMPOSES the generators)
# * ggen_igniter's own rendering fixtures and vendored dependency source
#
# Skipped entirely for a path whose `..` survived normalisation: such a path
# has no single meaning, so it gets no allowlist match.
if [ -z "$suspicious" ]; then
  case "$path" in
    */priv/ggen/*/templates/*|*/test/fixtures/*/templates/*) exit 0 ;;
    */lib/mix/tasks/*) exit 0 ;;
    */test/fixtures/ash-lifecycle-pack/*) exit 0 ;;
    */deps/*|*/_build/*) exit 0 ;;
    # config/ and test/ legitimately NAME resources (ash_domains lists, test
    # setup) without declaring them. `use Ash.Resource` there would still be
    # hand-authoring, but a .exs under those trees is far likelier to be a
    # reference than a declaration, and a false block on config is worse than
    # a missed .exs resource -- which the .ex rule above still catches.
    */config/*.exs|*/test/*.exs) exit 0 ;;
  esac
fi

# ---- the detector ---------------------------------------------------------
# Matched against a FLATTENED copy of the body. grep is line-oriented, and
# `use Ash.` / newline / `    Resource` is one valid alias continuation that
# grep sees as two records and therefore never matched. Measured allowed.
# Collapsing newlines and tabs to spaces, then squeezing runs of spaces,
# makes the declaration a single record regardless of how it was wrapped.
flat="$(printf '%s' "$input" | tr '\n\r\t' '   ' | tr -s ' ')"

# `use Ash.Domain` / `use Ash.Resource` are the two declarations that make a
# module an Ash domain or resource. `use` may be followed by whitespace OR by
# `(` -- `use(Ash.Resource, domain: X)` is the same macro call written as a
# parenthesised one, and was measured allowed by a whitespace-only pattern.
# Whitespace is tolerated either side of the dot for the same reason.
# A base-resource indirection (`use MyApp.Resource, otp_app: ..., domain: ...`)
# is caught by the otp_app + domain pair, which only appears in a generated
# resource header.
if printf '%s' "$flat" \
  | grep -qE 'use[[:space:](]+Ash[[:space:]]*\.[[:space:]]*(Resource|Domain)\b'; then
  violation="use Ash.Resource / use Ash.Domain"
elif printf '%s' "$flat" | grep -qE 'otp_app:[[:space:]]*:[a-z_]+' \
  && printf '%s' "$flat" | grep -qE 'domain:[[:space:]]*[A-Z][A-Za-z0-9_.]*'; then
  violation="a base-resource Ash header (otp_app: + domain:)"
else
  exit 0
fi

cat >&2 <<EOF
BLOCKED: refusing to hand-author an Ash surface ($violation) in:
  ${path:-<no file_path in the tool call>}

Ash already knows how to manufacture this. Writing it by hand skips the
semantic mutations the generators own -- domain registration in
config/config.exs, the create/update accept lists derived from public
attributes, base_resources config, repo wiring, and the migration snapshot
that ash.codegen diffs against. The file will look correct and the project
will be wrong.

The admitted path is:

  1. Add or change the FACT in the ontology
     (e.g. test/fixtures/ash_manufacture_pack/ontology.ttl):
       amp:BookIsbnAttribute a amp:Attribute ;
           amp:attributeOf amp:BookResource ;
           amp:attributeName "isbn" ; amp:attributeType "string" ;
           amp:isPublic true .

  2. Re-render the composed manufacture task:
       mix ggen_igniter.sync --pack-dir <pack>

  3. Run the REAL upstream generators through it:
       mix <app>.manufacture --phase base --yes
       mix <app>.manufacture --phase core --yes

  4. Assert idempotency:
       mix <app>.manufacture --phase core --check     # must exit 0

If no admitted generator can express what you need, that is a real result:
record it as an explicit UNSUPPORTED(generator capability) capability row in
the ontology naming the exact semantic element, and only then write the
irreducible residue by hand. Do not silently fall back to hand coding.

Full doctrine: AGENTS.md ("Ash surfaces are manufactured, not written").
To override deliberately for a genuine residue, state the UNSUPPORTED
capability row you added first.
EOF
exit 2
