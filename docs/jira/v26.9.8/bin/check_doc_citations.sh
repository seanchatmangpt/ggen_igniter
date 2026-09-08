#!/usr/bin/env bash
#
# check_doc_citations.sh -- resolve every artifact citation in the v26.9.8 ticket set.
#
# Why this exists: the ticket set repeatedly cited artifacts that did not exist -- a
# receipt under a filename nothing ever wrote, and four acceptance-ladder log names
# left behind when the harness was renumbered. A citation is the only thing a reader
# has in place of trusting the prose, so an unresolvable one is worse than no citation
# at all. Prose drifts silently; this turns that drift into a non-zero exit.
#
# Both failure classes are the same shape: the docs and the artifacts moved
# independently. Nothing but this script couples them.
#
# Two citation classes are resolved:
#   evidence/<path>   -> docs/jira/v26.9.8/evidence/<path>
#   NN-<name>.log     -> test/fixtures/.qualification/book_library/NN-<name>.log
#
# Exit 0 when every citation resolves; exit 1 listing each one that does not.
#
# Scope bound: this proves the cited path EXISTS. It does not prove the citation
# supports the sentence making it.

set -uo pipefail

DOC_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
REPO_ROOT="$(cd "$DOC_DIR/../../.." && pwd)"
EVIDENCE_DIR="$DOC_DIR/evidence"
QUAL_DIR="$REPO_ROOT/test/fixtures/.qualification/book_library"

failures=0
checked=0

note() { printf '%s\n' "$*"; }
fail() { printf 'MISSING  %s\n' "$*"; failures=$((failures + 1)); }

# Strip trailing sentence punctuation a regex greedily absorbs ("evidence/x.json." ).
strip_trailing_punct() {
  local s="$1"
  # Held in a variable: an inline [.,;:] bracket expression ends the [[ ]] at the ';'.
  local re='[.,;:]$'
  while [[ "$s" =~ $re ]]; do s="${s%?}"; done
  printf '%s' "$s"
}

note "check_doc_citations: $DOC_DIR"
note "  evidence root      : $EVIDENCE_DIR"
note "  qualification root : $QUAL_DIR"
note ""

if [[ ! -d "$EVIDENCE_DIR" ]]; then
  note "SKIP     evidence/ absent -- evidence citations not resolved (regenerate it to check them)"
  skip_evidence=1
else
  skip_evidence=0
fi

# The qualification tree is a run artifact, gitignored, and absent on a fresh clone.
# Skipping loudly beats a check that is permanently red for a reason unrelated to the docs.
if [[ ! -d "$QUAL_DIR" ]]; then
  note "SKIP     qualification tree absent -- .log citations not resolved"
  note "         run: bash test/fixtures/ash_manufacture_pack/bin/qualify.sh"
  skip_logs=1
else
  skip_logs=0
fi

shopt -s nullglob
for md in "$DOC_DIR"/*.md; do
  rel="${md#"$REPO_ROOT"/}"

  if [[ $skip_evidence -eq 0 ]]; then
    # The leading [A-Za-z0-9._/-]* is load-bearing: it greedily absorbs any path prefix,
    # so `docs/reference/evidence/ocel.md` arrives whole and is resolved repo-relative
    # instead of being mistaken for a ticket-relative `evidence/ocel.md` citation.
    while IFS= read -r raw; do
      [[ -z "$raw" ]] && continue
      cite="$(strip_trailing_punct "$raw")"
      [[ -z "$cite" ]] && continue
      checked=$((checked + 1))
      if [[ "$cite" == evidence/* ]]; then
        [[ -e "$DOC_DIR/$cite" ]] || fail "$rel -> $cite (ticket-relative)"
      else
        [[ -e "$REPO_ROOT/$cite" ]] || fail "$rel -> $cite (repo-relative)"
      fi
    done < <(grep -oE '[A-Za-z0-9._/-]*evidence/[A-Za-z0-9._/-]*' "$md" | sort -u)
  fi

  if [[ $skip_logs -eq 0 ]]; then
    while IFS= read -r cite; do
      [[ -z "$cite" ]] && continue
      checked=$((checked + 1))
      [[ -e "$QUAL_DIR/$cite" ]] || fail "$rel -> $cite"
    done < <(grep -oE '[0-9]{2}-[A-Za-z0-9._-]+\.log' "$md" | sort -u)
  fi
done

note ""
note "citations resolved: $((checked - failures))/$checked"

if [[ $failures -gt 0 ]]; then
  note "FAIL: $failures unresolvable citation(s)"
  exit 1
fi

note "OK: every citation resolves"
exit 0
