#!/usr/bin/env python3
"""Eligible-set parity for Mix ↔ hands-free (ggen) frontier twins.

Cross-check PASS requires identical sorted identity sets in `eligible`.
Any divergence is typed REFUSED:HANDS_FREE_TWIN_DRIFT (exit 1).

CLI:
  python3 hands_free_twin_parity.py <mix_frontier.json> <hands_free_frontier.json>
  python3 hands_free_twin_parity.py --self-test
"""

from __future__ import annotations

import json
import sys
from typing import Any, Iterable, Mapping, Sequence, Set, Tuple


REFUSAL = "HANDS_FREE_TWIN_DRIFT"


def _identity(row: Any) -> str | None:
    if isinstance(row, str) and row:
        return row
    if isinstance(row, Mapping):
        ident = row.get("identity")
        if isinstance(ident, str) and ident:
            return ident
    return None


def eligible_identity_set(doc: Any) -> Set[str]:
    """Extract the set of eligible identities from a frontier JSON doc."""
    if not isinstance(doc, Mapping):
        return set()
    eligible = doc.get("eligible") or []
    if not isinstance(eligible, Sequence) or isinstance(eligible, (str, bytes)):
        return set()
    out: Set[str] = set()
    for row in eligible:
        ident = _identity(row)
        if ident is not None:
            out.add(ident)
    return out


def check_parity(
    mix_doc: Any, hands_free_doc: Any
) -> Tuple[bool, str, Set[str], Set[str]]:
    """Return (ok, detail, mix_ids, hf_ids).

    ok is True iff sorted identity sets match. detail is human/typed text.
    """
    if isinstance(hands_free_doc, Mapping) and (
        hands_free_doc.get("status") in ("refused", "REFUSED")
        or hands_free_doc.get("standing") == "REFUSED"
    ):
        return (
            False,
            f"REFUSED:{REFUSAL} hands-free standing refused: {json.dumps(hands_free_doc)}",
            set(),
            set(),
        )

    mix_ids = eligible_identity_set(mix_doc)
    hf_ids = eligible_identity_set(hands_free_doc)
    if mix_ids == hf_ids:
        ordered = sorted(mix_ids)
        return (
            True,
            f"hands-free twin parity: ok eligible={ordered}",
            mix_ids,
            hf_ids,
        )

    detail = (
        f"REFUSED:{REFUSAL} eligible-set mismatch "
        f"mix={sorted(mix_ids)} hands_free={sorted(hf_ids)}"
    )
    return False, detail, mix_ids, hf_ids


def load_json(path: str) -> Any:
    raw = open(path, encoding="utf-8", errors="replace").read().strip()
    if not raw:
        raise ValueError(f"empty JSON file: {path}")
    return json.loads(raw)


def main(argv: Sequence[str]) -> int:
    if len(argv) == 2 and argv[1] == "--self-test":
        return _self_test()
    if len(argv) != 3:
        print(
            "usage: hands_free_twin_parity.py <mix.json> <hands_free.json>",
            file=sys.stderr,
        )
        print("   or: hands_free_twin_parity.py --self-test", file=sys.stderr)
        return 2

    try:
        mix_doc = load_json(argv[1])
        hf_doc = load_json(argv[2])
    except (OSError, ValueError, json.JSONDecodeError) as exc:
        print(f"REFUSED:HANDS_FREE non-JSON frontier: {exc}", file=sys.stderr)
        return 1

    ok, detail, _, _ = check_parity(mix_doc, hf_doc)
    if ok:
        print(detail)
        return 0
    print(detail, file=sys.stderr)
    return 1


def _self_test() -> int:
    """Chicago anti-vacuity: match PASSES, mismatch REFUSES."""
    failures: list[str] = []

    match_mix = {"eligible": [{"identity": "A"}], "blocked": []}
    match_hf = {"eligible": [{"identity": "A"}], "blocked": [{"identity": "B"}]}
    ok, detail, _, _ = check_parity(match_mix, match_hf)
    if not ok:
        failures.append(f"match should PASS, got: {detail}")

    drift_mix = {
        "eligible": [{"identity": "FRI-FMT-A"}],
        "blocked": [{"identity": "FRI-FMT-B", "reason": "dependencies_unsatisfied"}],
    }
    drift_hf = {
        "eligible": [],
        "blocked": [
            {"identity": "FRI-FMT-A", "reason": "authority_index_unavailable"},
            {"identity": "FRI-FMT-B", "reason": "authority_index_unavailable"},
        ],
    }
    ok, detail, mix_ids, hf_ids = check_parity(drift_mix, drift_hf)
    if ok:
        failures.append("mismatch should REFUSE, but ok=True")
    if REFUSAL not in detail:
        failures.append(f"mismatch detail missing {REFUSAL}: {detail}")
    if mix_ids != {"FRI-FMT-A"} or hf_ids != set():
        failures.append(f"unexpected sets mix={mix_ids} hf={hf_ids}")

    # Vacuous JSON-ok twin (skeptic L19): empty eligible vs Mix eligible=1 must refuse.
    vacuous = {"eligible": [], "eligible_count": 0, "standings": {}}
    ok, detail, _, _ = check_parity(drift_mix, vacuous)
    if ok or REFUSAL not in detail:
        failures.append(f"vacuous JSON-ok must REFUSE: {detail}")

    if failures:
        for line in failures:
            print(f"SELFTEST FAIL: {line}", file=sys.stderr)
        return 1
    print("self-test: match PASS + mismatch REFUSED:HANDS_FREE_TWIN_DRIFT")
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))
