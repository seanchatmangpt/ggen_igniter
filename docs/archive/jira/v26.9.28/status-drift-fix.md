# status.md drift fix (lane w8)

Re-derived on the current tree (2026-09-28); derivation commands now sit inline in `docs/status.md`.

| fact | before | after | derivation |
|---|---|---|---|
| doctor checks | 18-check | 19-check | `grep -cE '^[0-9]+\. \*\*' docs/reference/cli/doctor.md` -> 19 |
| ash_manufacture_pack SPARQL gates (3 places) | 11 | 13 (added `090_citations`, `092_dependency_pins` to the list) | `ls test/fixtures/ash_manufacture_pack/gates/*.rq \| wc -l` -> 13 |
| StreamData files | 10 | 16 | `grep -rl StreamData test \| wc -l` -> 16 |
| `System.cmd("mix"` sites | 78 | 108 (78 kept as the `e74bc5d` snapshot) | `grep -rn 'System.cmd("mix"' test \| wc -l` -> 108 |

Verified unchanged (no edit): 118 JSONL records (`wc -l`), 21 `amp:GeneratorCapability`, dispatch test 12 tests, EDS receipt 114 lines, 5 EDS test files. Historical SHAs `767bcce`, `90c1da4` exist (`git cat-file -t` -> commit) and remain labeled snapshots.
