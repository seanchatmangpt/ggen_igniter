# 09 sJira Authority Exploration

Standing: UNVERIFIED

Lane 09 of v26.11.17. Scope: the origin-authority law (SJ-002, ADR-012),
`sj:CodeWorkAuthority` admission, and `mix semantic_jira.admit_candidates`. This was a
read-only source pass. `mix` is not installed in this sandbox (`timeout: failed to run
command 'mix': No such file or directory`), so no test was run and no behavior below is
executed. Every row is a reading of source or a grep, hence UNVERIFIED unless noted. The
pass found one crash path (bad hex key), one cwd-dependence inconsistency, a moduledoc gate
ordering that differs from the code, a class-name gap between ADR-012 and the code, and
several untested flag paths.

## Findings

| id | finding | standing | evidence |
|---|---|---|---|
| F1 | `Base.decode16!` on a `--sovereign-keys` value raises on non-hex input, so a malformed keys file crashes the whole run instead of failing closed per SOVEREIGN candidate as the moduledoc promises for unreadable keys. | UNVERIFIED (read, not run) | `lib/mix/tasks/semantic_jira.admit_candidates.ex:186-188` vs doc `:52-54` |
| F2 | Pack ontology digest is read via `File.cwd!()`-relative path, while the authority index uses `Application.app_dir`. Run outside the repo root: every SOVEREIGN candidate refuses with `pack_ontology_digest_unavailable`, while non-SOVEREIGN still admit. | UNVERIFIED | `admit_candidates.ex:101,177` vs `authority.ex:576` |
| F3 | Moduledoc says candidate_bounds runs "before either gate" and sovereign is Gate 3, epoch Gate 4. Code order is epoch, bounds, admit_work_order, sovereign, origin resolve. Sovereign is judged before origin resolution, so a SOVEREIGN candidate with a bad origin and no lease prints the lease refusal, not the origin refusal. | UNVERIFIED | `admit_candidates.ex:224-228` vs doc `:20-72` |
| F4 | ADR-012 says origin must be an admitted instance of `sj:CodeWorkAuthority`; code indexes only `StrategicObjective` and `GoalCheckpoint`. A node typed only `sj:CodeWorkAuthority` never enters the index and resolves `authority_not_admitted`. No `lib/` code references the class by IRI. | UNVERIFIED | `authority.ex:49-52`; `grep -rn CodeWorkAuthority lib` hits only the moduledoc comment (`authority.ex:6`); ontology `:2247,:2420` |
| F5 | Pin law makes `--authority-graph` nearly inert for admission: any caller graph passes `pin/2` against canonical trust roots, so only the three canonical objectives can admit; no GoalCheckpoint is pinned. The flag can only add refusals. Moduledoc does not say so. | UNVERIFIED | `authority.ex:263-268,421-466`; ontology comment `:2553-2555`; trust roots `:2570,:2576` (three canonical objectives per ontology comment) |
| F6 | No admit_candidates test passes `--authority-graph` or `--epoch-manifest` to the task; epoch coverage is in a separate file calling the module. | UNVERIFIED | `grep -n "authority_graph\|epoch_manifest" test/*admit*` returned nothing; `grep -ln admit_candidates test/*.exs` lists epoch_admission, sovereign, and base test files |
| F7 | Test names in the base file cover: origin vs prose, bad JSON, duplicates, literal standing, actuation ceilings, ladder ceilings, missing flag. None cover: unreadable candidates file (exit 2), unavailable authority index (exit 1), or a candidate with `authority_requirement` outside NONE/SOVEREIGN. | UNVERIFIED | `test/mix_semantic_jira_admit_candidates_test.exs:48,80,91,118,145,176,198` |
| F8 | Dedupe keys include `replay_identity`/`work_order_digest` read with `wo[f]`; if `admit_work_order` can emit a nil for either, two admitted lines would collide on `{field, nil}`. Whether nil is reachable was not checked. | UNVERIFIED | `admit_candidates.ex:346-351`; `SemanticJira.admit_work_order/1` not read |
| F9 | `names_actuation?` prefix roots (`PUSH`, `DO`, `MERGE`...) over-refuse benign ceilings like `PUSHBACK_REVIEWED` or `RELEASE_NOTES`; this is conservative, undocumented as a false-positive class. | UNVERIFIED | `admit_candidates.ex:296-297,331-338` |
| F10 | Exit-code contract: every judged line is exit 0 even if all refused; callers must parse the `summary` line. A SOVEREIGN gate crash (F1) would surface as a raise, not exit 1 or 2. | UNVERIFIED | `admit_candidates.ex:86-90,161-165` |
| F11 | Authority index is cached in `:persistent_term` by byte digest; no eviction of stale keys when a file changes, so long-lived VMs accumulate entries. Low risk for a Mix task. | UNVERIFIED | `authority.ex:245-251,360-366` |
| F12 | ADR-012 states Invariant B (candidate-only orders) is a recorded exclusion; admit_candidates is the nearest "candidate" surface but admits straight to work_order output with no further transition. Consistent with the ADR, but worth restating in docs. | UNVERIFIED | ADR-012 lines 66-72 |
| F13 | ADR-012 claims 34/34 orders carry an origin and a 3-objective split (32/1/1). Not recounted this pass. | UNVERIFIED (not run) | ADR-012 lines 82-86 |

## Next

1. Run `mix test` on the three admit/authority test files where Elixir is installed.
2. Add a falsifier: sovereign keys file with a non-hex value; assert refusal, not a raise (F1).
3. Add a falsifier: run the task from a non-root cwd with a SOVEREIGN candidate (F2).
4. Decide F4: index `sj:CodeWorkAuthority` directly, or reword ADR-012 to the two subclasses.
5. Document F3 order and F5 pin effect in the moduledoc and `docs/reference/cli/`.
6. Cover exit 1/exit 2 paths and `--authority-graph`/`--epoch-manifest` end to end (F6, F7).
7. Recount WorkOrders and origins in the pack (F13).

## See Also

- `docs/architecture/adr/ADR-012-prose-never-originates-work-orders.md`
- `lib/mix/tasks/semantic_jira.admit_candidates.ex`
- `lib/ggen_igniter/semantic_jira/authority.ex`
- `docs/jira/v26.11.17/LANES.md`
