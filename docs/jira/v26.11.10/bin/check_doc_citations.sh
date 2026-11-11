#!/usr/bin/env bash
#
# check_doc_citations.sh -- resolve every artifact citation in the v26.11.10 ticket set.
#
# Resolves:
#   evidence/<path>                 -> docs/jira/v26.11.10/evidence/<path>
#   <prefix>/evidence/<path>        -> repo-relative path
#   NN-<name>.log                   -> docs/jira/v26.11.10/evidence/ or test/fixtures/.qualification/
#   NN-<name>.md                    -> docs/jira/v26.11.10/NN-<name>.md (ticket cross-reference)
#
# Exit 0 when every citation resolves; exit 1 listing each one that does not.

set -uo pipefail

DOC_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
REPO_ROOT="$(cd "$DOC_DIR/../../.." && pwd)"
EVIDENCE_DIR="$DOC_DIR/evidence"
QUAL_DIR="$REPO_ROOT/test/fixtures/.qualification/book_library"

failures=0
checked=0

note() { printf '%s\n' "$*"; }
fail() { printf 'MISSING  %s\n' "$*"; failures=$((failures + 1)); }

strip_trailing_punct() {
  local s="$1"
  local re='[.,;:]$'
  while [[ "$s" =~ $re ]]; do s="${s%?}"; done
  printf '%s' "$s"
}

note "check_doc_citations: $DOC_DIR"
note "  evidence root      : $EVIDENCE_DIR"
note "  repo root          : $REPO_ROOT"
note ""

if [[ ! -d "$EVIDENCE_DIR" ]]; then
  note "SKIP     evidence/ absent -- evidence citations not resolved"
  skip_evidence=1
else
  skip_evidence=0
fi

shopt -s nullglob
for md in "$DOC_DIR"/*.md; do
  rel="${md#"$REPO_ROOT"/}"

  if [[ $skip_evidence -eq 0 ]]; then
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

  # Check numbered markdown ticket cross-references
  while IFS= read -r raw; do
    [[ -z "$raw" ]] && continue
    cite="$(strip_trailing_punct "$raw")"
    [[ -z "$cite" ]] && continue
    checked=$((checked + 1))
    [[ -e "$DOC_DIR/$cite" ]] || fail "$rel -> $cite (ticket cross-reference)"
  done < <(grep -oE '\b[0-9]{2}-[A-Za-z0-9._-]+\.md\b' "$md" | sort -u)

  # Check log files
  while IFS= read -r raw; do
    [[ -z "$raw" ]] && continue
    cite="$(strip_trailing_punct "$raw")"
    [[ -z "$cite" ]] && continue
    checked=$((checked + 1))
    if [[ -e "$EVIDENCE_DIR/$cite" ]]; then
      : # ok evidence dir
    elif [[ -e "$QUAL_DIR/$cite" ]]; then
      : # ok qual dir
    elif [[ -e "$REPO_ROOT/$cite" ]]; then
      : # ok repo-relative
    else
      fail "$rel -> $cite (log file)"
    fi
  done < <(grep -oE '[0-9]{2}-[A-Za-z0-9._-]+\.log' "$md" | sort -u)

done

note ""
note "citations resolved: $((checked - failures))/$checked"

if [[ $failures -gt 0 ]]; then
  note "FAIL: $failures unresolvable citation(s)"
  exit 1
fi

note "OK: every citation resolves"
exit 0
