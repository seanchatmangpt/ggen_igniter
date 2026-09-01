# Red-team: same-real-output-path concurrency, run via the real Reactor path

Role: independent adversarial reviewer. No builder reasoning taken on faith
from the module's own moduledoc/tests — every claim below is backed by a
real, freshly-executed run of the real, compiled
`GgenIgniter.Reactors.ReconcileReactor` (`lib/ggen_igniter/reactors/reconcile_reactor.ex`),
invoked exactly as production code invokes it
(`GgenIgniter.Reactors.ReconcileReactor.run/1` → `Reactor.run/4` → the real
`:admit`/`:actuate` steps, `:actuate`'s real `Task.async_stream/3`
concurrency), against real scratch Mix projects, with a real `mix compile
--warnings-as-errors` in `:verify`. Zero mocks anywhere in this chain.

## Verdict

**CONFIRMED — nondeterminism found (a real defect).**

Two real reconciliation targets can be made to share the *same real output
path* (same inode on disk) while carrying two different, non-canonicalized
raw path strings. When they do, `:admit`'s duplicate-output-path guard —
the guard the shipped test suite
(`test/ggen_igniter_reactor_concurrency_test.exs`) already calls
"structurally impossible to race" — never fires, `:actuate`'s real
`Task.async_stream/3` genuinely races both writes against the identical
real file, and the byte content that survives on disk is genuinely
last-writer-wins: which target's content wins is a real function of
relative completion timing, and independently varying that timing (list
order, then randomized per-target delay) across repeated real runs produced
**both** possible winners. The pipeline reports `standing: :alive`
(full success, `target_count: 2`) every single time regardless of which
target's content was silently discarded, and the persisted manifest records
two independently "owned" logical entries for what is, in reality, one
physical file.

## Method (why the literal-string case alone would be the wrong test)

The shipped test suite's "Property 2" only exercises two targets with the
exact same `out:` STRING. Reading the real code
(`admit_pending/2` in `reconcile_reactor.ex`, and `for_file/6`/`logical_id/3`
in `lib/ggen_igniter/pending_actuation.ex`) shows the duplicate check groups
pending writes `Enum.group_by(& &1.target)` — a raw Elixir string
comparison — and `target` is stored **verbatim**, never passed through
`Path.expand/1`, `Path.absname/1`, or any realpath/canonicalization. That is
the load-bearing gap: it means "same real output path" and "same `target`
string" are silently assumed to be the same test, when they are not. The
adversarial construction here targets exactly that gap: two raw strings that
are lexically different but resolve, at the OS/kernel level, to the
identical real file (one string has a literal `/./` path segment injected).
This was verified as a real filesystem fact BEFORE running anything through
Reactor:

```
$ elixir -e '
project = "/tmp/pathcheck"
out_a = Path.join([project, "lib", "collision.ex"])
out_b = Path.join([project, "lib", "."]) <> "/collision.ex"
IO.inspect({out_a, out_b, out_a == out_b}, label: "strings")
File.write!(out_a, "AAA")
IO.inspect(File.read!(out_b), label: "read_via_b_after_write_a")
File.write!(out_b, "BBB")
IO.inspect(File.read!(out_a), label: "read_via_a_after_write_b")
'
strings: {"/tmp/pathcheck/lib/collision.ex", "/tmp/pathcheck/lib/./collision.ex", false}
read_via_b_after_write_a: "AAA"
read_via_a_after_write_b: "BBB"
```

Strings differ (`false`); the real file is identical (write via one alias is
immediately visible via the other).

## Real scenario 1 (control): identical `out:` string, run 3x

Two targets (`ex:Alpha` / `ex:Beta`, distinct real SPARQL query results, real
`.ex.eex` template, real scratch Mix project) with the byte-identical `out:`
string, run through `ReconcileReactor.run/1` three real times in a row
(fresh scratch project each time):

```
iter=1 standing=:refused canonical_exists=false winner=neither
iter=2 standing=:refused canonical_exists=false winner=neither
iter=3 standing=:refused canonical_exists=false winner=neither
reason (all 3, verbatim): "refused: duplicate output path(s): [...]"
```

Independently reproduced: this literal-string case **is** genuinely
deterministic — `:admit` refuses before `:actuate` ever runs
(no `ACTUATION_STARTED` in this path), neither target's content ever
touches disk, all 3 runs identical. This matches the shipped test's claim
for THIS specific case — confirmed independently, not merely trusted.

## Real scenario 2 (adversarial): alias strings, same real inode, run 3x

Same fixtures; `out_a = ".../lib/collision.ex"`, `out_b = ".../lib/./collision.ex"`
(different strings, same real file, per the filesystem check above). Both
targets given `test_delay_ms: 150` (the module's own, non-mocking test hook
— `Process.sleep/1` before the real write) and a shared ETS `test_probe`
table so real write-window overlap is independently, empirically checked
(not assumed from reading the source).

```
iter=1 standing=:alive canonical_exists=true winner=beta
       probe=[{0,:start}=-751268, {0,:stop}=-751113, {1,:start}=-751268, {1,:stop}=-751112]
       real_overlap=true   (both windows genuinely overlapped)
iter=2 standing=:alive canonical_exists=true winner=beta
       probe=[{0,:start}=-750632, {0,:stop}=-750480, {1,:start}=-750632, {1,:stop}=-750479]
       real_overlap=true
iter=3 standing=:alive canonical_exists=true winner=beta
       probe=[{0,:start}=-750017, {0,:stop}=-749865, {1,:start}=-750017, {1,:stop}=-749865]
       real_overlap=true
```

Every one of the 3 straight runs: `:admit`'s duplicate check is bypassed
(`standing: :alive`, never `:refused`), real overlapping write windows are
confirmed via the ETS probe timestamps (not inferred), and only ONE
target's content survives on the real file — in this first batch, `Beta`
every time.

**A single batch with equal fixed delays winning the same way every time is
not yet proof of nondeterminism** (it could be a fixed scheduling artifact,
e.g. "second task in the list always finishes last on this machine"), so
this was independently probed further, per the adversarial-example
discipline, rather than stopped at 3-for-3:

- **(a) Swapped list order** (Beta listed first, Alpha second), equal fixed
  150 ms delay, 3 more real runs: winner was `beta` all 3 times again — this
  rules out "second in the list always writes first/loses" as the
  explanation (Beta won both when listed second AND when listed first), and
  is consistent with the *actual* mechanism being real completion-time
  ordering, not list position.
- **(b) Original order, randomized per-target delay** (`100 + rand(100)` ms
  independently for each target — still a real `Process.sleep` before the
  real write, not simulated), 5 more real runs:

  ```
  iter=1 delay_a=110 delay_b=176 -> winner=beta   (b's real write finished later)
  iter=2 delay_a=160 delay_b=168 -> winner=beta   (b's real write finished later)
  iter=3 delay_a=192 delay_b=127 -> winner=alpha  (a's real write finished later)
  iter=4 delay_a=174 delay_b=117 -> winner=alpha  (a's real write finished later)
  iter=5 delay_a=199 delay_b=126 -> winner=alpha  (a's real write finished later)
  ```

  Winner flips exactly with which target's real write genuinely completes
  later — textbook last-writer-wins, and **both** `alpha` and `beta` are
  observed as the real winner across these real runs (`all_winners =
  [:beta, :alpha]`), i.e. genuinely nondeterministic as a function of real
  runtime completion order, not a fixed artifact of this implementation.
  `standing: :alive` in every one of these 8 additional runs as well — the
  pipeline never once detects or reports the collision.

## On-disk / receipt evidence for one concrete run (iter=1 of scenario 2)

Real persisted `manifest.json` (two distinct logical entries for one real
file — `Alpha`'s original content is nowhere recorded as lost):

```json
{
  "entries": {
    ".../valid.ex.eex=>.../lib/./collision.ex": {
      "out_template": ".../lib/./collision.ex",
      "outputs": {".../lib/./collision.ex": "sha256:4453719218..."}
    },
    ".../valid.ex.eex=>.../lib/collision.ex": {
      "out_template": ".../lib/collision.ex",
      "outputs": {".../lib/collision.ex": "sha256:4453719218..."}
    }
  }
}
```

Real persisted receipt (`.ggen_igniter/receipts/*.jsonl`):
`"standing":"alive"`, `"target_count":2`, `"outcome":"written"`,
`"notice":"ggen_igniter reactor: 2 target(s) actuated"` — a false claim of
full success; no event, standing, or metadata field anywhere in the receipt
discloses that only one of the two targets' content actually exists on
disk.

Real file on disk after the run:

```elixir
defmodule RedteamAliasRaceFixture.Beta do
  def greeting, do: "BETA_WON_THE_RACE"
end
```

`Alpha`'s real, intended content (`"ALPHA_WON_THE_RACE"`) never exists on
disk at any point after this run — silently and permanently lost, with a
receipt actively asserting the opposite (`:alive`, both targets "actuated").

## Root cause

`admit_pending/2` (`lib/ggen_igniter/reactors/reconcile_reactor.ex`) detects
duplicate output paths via `Enum.group_by(& &1.target)` on the raw string
stored by `PendingActuation.for_file/6` / `logical_id/3`
(`lib/ggen_igniter/pending_actuation.ex`) — never canonicalized. Any two
`:out` renders that are lexically different but resolve to the same real
file (a redundant `.` path segment, a redundant `//`, a relative vs.
equivalent absolute form, `..`-containing paths, case differences on a
case-insensitive filesystem, or a symlinked directory reached by two
different real paths) defeat the guard entirely, letting `:actuate`'s real
`Task.async_stream/3` concurrency race unprotected on the shared real file.

## Scope / limits of this finding (stated for honesty, not to soften it)

- Only the `/./`-segment alias form was exercised end-to-end through
  Reactor. The filesystem-level mechanism (raw-string comparison vs. real
  inode identity) is general, so `//`, `..`, and symlink-based aliases are
  expected to reproduce the same bypass by the same reasoning, but only the
  `/./` form was itself run 11 real times total (3 + 3 + 5) in this review
  — the others are a reasoned extrapolation from the same root cause, not
  independently executed here.
- The literal-identical-string case (scenario 1) genuinely is deterministic
  and refused, confirmed independently — this finding does not contradict
  that; it shows the guard's real coverage is narrower than "same real
  output path," which is the property both the moduledoc and the shipped
  test name as the guarantee.

## Artifacts

- Red-team scripts (outside the repo, scratchpad only, not part of the
  ggen_igniter test suite):
  `/private/tmp/claude-501/-Users-sac/376fbff1-0eef-4666-b865-29fea6816bdd/scratchpad/redteam/alias_race.exs`
  `/private/tmp/claude-501/-Users-sac/376fbff1-0eef-4666-b865-29fea6816bdd/scratchpad/redteam/alias_race_swap.exs`
- Raw run logs:
  `/private/tmp/claude-501/-Users-sac/376fbff1-0eef-4666-b865-29fea6816bdd/scratchpad/redteam/run1.log`
  `/private/tmp/claude-501/-Users-sac/376fbff1-0eef-4666-b865-29fea6816bdd/scratchpad/redteam/run2_swap.log`
- Invocation used (real Reactor path, real compiled app, cwd = the actual
  repo so the real project's deps/config are loaded):
  `mix run <script>.exs` from `/Users/sac/ggen_igniter`.
- No files inside `/Users/sac/ggen_igniter` were modified by this review
  other than this report (scratch Mix projects and fixtures all live under
  the OS temp dir / the scratchpad above).
