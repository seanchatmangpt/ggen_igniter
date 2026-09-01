# Adversarial Verification: doctor break/fix/no-op cycle

Independent verifier, zero trust in prior claims. All commands below were executed for
real, right now, against real repository disk state and real throwaway `/tmp` fixtures.
No file inside `/Users/sac/ggen_igniter` was modified by this verification.

## Environment facts (measured, not assumed)

- Repo `HEAD`: `767bccea32d03790a1f4975596a06ecd16df365f`
- Working tree at verification time: **dirty** (`git status --porcelain` in the repo
  shows uncommitted changes to `lib/ggen_igniter/actuate.ex`,
  `lib/ggen_igniter/query/oxigraph.ex`, `lib/mix/tasks/ggen_igniter.doctor.ex`,
  `mix.exs`, and ~15 test files) — pre-existing state, not caused by this verification
  (this verifier only read files inside the repo and wrote/ran fixtures under `/tmp`).
- Real `mix.exs` version string: **`26.8.27`** (`mix.exs:9`) — the task brief's stated
  release target "v26.7.27" does **not** match the real repo value. Reporting the real
  value per instructions rather than the assumed one.
- `mix --version`: Mix 1.19.5, Erlang/OTP 28, Elixir 1.19.5.
- Files read in full before constructing anything: `lib/mix/tasks/ggen_igniter.doctor.ex`
  (551 lines) and `lib/ggen_igniter/doctor_fixes.ex` (477 lines).

## Claims checked and verdicts

### Claim 1 — `check_dcatr_env_config`/`fix_dcatr_env_config!` (doctor check 6) really
detects a missing `config :dcatr, env: ...` and really fixes it via a live
`mix ggen_igniter.doctor --fix` subprocess run.

**CONFIRMED.**

Fixture (`/tmp/doctor_adv_verify_<pid>`, since removed): a real, minimal Mix project
`:doctor_adv_fixture` with a real dependency on `{:ggen_igniter, path:
"/Users/sac/ggen_igniter"}`, unrestricted `{:igniter, "~> 0.8"}`, unrestricted
`{:sourceror, "~> 1.7"}`, a real `{:gno, "~> 0.1"}` dependency (this is what makes
`config :dcatr, env: ...` become necessary, per `doctor_fixes.ex:181-188`'s real
`app_loaded?(:gno) or app_loaded?(:dcatr)` check), and a real `{:ash, "~> 3.0"}`
dependency (see Claim 2). `config/config.exs` ended in the standard
`import_config "#{config_env()}.exs"` marker with no `dcatr` entry.

Real commands run, in order, from that fixture directory:

```
mix deps.get                      # exit 0, resolved cleanly (network reachable, hex.pm 200)
MIX_ENV=dev mix compile           # exit 0, real cargo build of ggen_graph_nif, real ash/gno compile
MIX_ENV=dev mix ggen_igniter.doctor          # exit 0
MIX_ENV=dev mix ggen_igniter.doctor --fix    # exit 0
```

Before `--fix`, real doctor output included:

```
⚠ :gno/:dcatr present in the dependency tree but config :dcatr, env: ... is missing from
  /private/tmp/doctor_adv_verify_<pid>/config/config.exs -- run `mix ggen_igniter.doctor --fix` to fix
```

After `--fix`, real doctor output included:

```
✔ FIXED: added `config :dcatr, env: Mix.env()` to /private/tmp/doctor_adv_verify_<pid>/config/config.exs
```

Re-reading the real file from disk after the fix confirmed the exact insertion point
(before `import_config`, matching the documented Phoenix-convention insertion strategy
at `doctor_fixes.ex:212-220`):

```
import Config

config :dcatr, env: Mix.env()

config :doctor_adv_fixture, ash_domains: [DoctorAdvFixture.Shop]

import_config "#{config_env()}.exs"
```

### Claim 2 — `check_ash_domains`/`fix_ash_domains!` (doctor check 7) really detects an
unregistered `use Ash.Domain` module and really fixes it via a live
`mix ggen_igniter.doctor --fix` subprocess run.

**CONFIRMED.**

Same fixture as Claim 1, with a real `lib/my_shop_domain.ex`:

```elixir
defmodule DoctorAdvFixture.Shop do
  use Ash.Domain
end
```

`use Ash.Domain` genuinely requires `:ash` to be a real, compiled dependency of the
fixture (`check_ash_domains/1` itself is a pure textual scan per
`doctor_fixes.ex:252-259`'s own moduledoc and doesn't require compilation, but the
*fixture project itself* must compile to be run via a live `mix` subprocess at all —
confirmed by first omitting `:ash`, which failed real compilation with `module
Ash.Domain is not loaded and could not be found`, then adding `{:ash, "~> 3.0"}`, which
compiled clean).

Before `--fix`:

```
⚠ 1 Ash domain module(s) not registered in config :doctor_adv_fixture, ash_domains: [...]:
  DoctorAdvFixture.Shop -- run `mix ggen_igniter.doctor --fix` to fix
```

After `--fix`:

```
✔ FIXED: registered 1 Ash domain module(s) in /private/tmp/doctor_adv_verify_<pid>/config/config.exs:
  DoctorAdvFixture.Shop
```

Real file re-read from disk confirmed `config :doctor_adv_fixture, ash_domains:
[DoctorAdvFixture.Shop]` was actually written (shown in the combined file dump under
Claim 1).

### Claim 3 — running `mix ggen_igniter.doctor --fix` a second time is a genuine no-op
for both fixes 3 and 4 (nothing left to fix, identical check output, exit 0).

**CONFIRMED.**

Second real run (`MIX_ENV=dev mix ggen_igniter.doctor --fix`) against the now-fixed
fixture, exit 0, with:

```
✔ config :dcatr, env: ... already present in /private/tmp/doctor_adv_verify_<pid>/config/config.exs
✔ all 1 Ash domain module(s) already registered in config :doctor_adv_fixture, ash_domains: [...]
```

No `FIXED:` lines present. A **third** real run was executed immediately after and its
`✔`/`⚠`/`✘`-prefixed check lines were diffed byte-for-byte against the second run's
check lines (`diff run2_checks.txt run3_checks.txt`): **zero diff, both exit 0** —
genuine idempotency, not merely "no FIXED line this time."

### Claim 4 — the doctor `--fix` cycle for the `igniter`/`sourceror` `:only` mismatch
(fixes 1 & 2) can be broken, fixed, and re-verified as a no-op via a live
`mix ggen_igniter.doctor --fix` subprocess run against a real consumer project, the
same way fixes 3/4 were.

**REFUTED** (for the live-subprocess CLI path specifically) — **CONFIRMED instead via
direct in-process function calls**, which is the only reachable path for this gap
shape. This is a real, independently-reproduced architectural constraint, not a
convenient excuse:

Real repro, attempt 1 (mismatch present from the start): a fixture `mix.exs` with
`{:ggen_igniter, path: "/Users/sac/ggen_igniter"}` (needs `:igniter` unconditionally,
transitively) plus `{:igniter, "~> 0.8", only: [:dev, :test]}` and `{:sourceror, "~>
1.7", only: :test}` declared directly. Running `mix deps.get` in that fixture produced,
verbatim:

```
Dependencies have diverged:
* igniter (Hex package)
  the :only option for dependency igniter
  > In mix.exs:
    {:igniter, "~> 0.8", [env: :prod, hex: "igniter", only: [:dev, :test], repo: "hexpm"]}
  does not match the :only option calculated for
  > In /Users/sac/ggen_igniter/mix.exs:
    {:igniter, "~> 0.8", [env: :prod, hex: "igniter", repo: "hexpm"]}
  Remove the :only restriction from your dep
** (Mix) Can't continue due to errors on dependencies
```

Real repro, attempt 2 (ruling out "just re-run `deps.get` first" as a workaround): built
a *working* fixture with unrestricted `igniter`/`sourceror`, ran real `mix deps.get` +
`mix compile` successfully, ran `mix ggen_igniter.doctor`/`--fix` successfully (Claims
1-3 above), **then** hand-edited `mix.exs` to add `only: [:dev, :test]` /
`only: :test` to the already-resolved `igniter`/`sourceror` deps (the realistic "a
consumer's dependency spec drifts after their project already works" scenario) and ran
`mix ggen_igniter.doctor` again **without** re-running `deps.get`. Real result: exit 1,
the same "Dependencies have diverged ... Remove the :only restriction from your dep"
error for `igniter`, thrown by Mix's own dependency-graph loader before
`Mix.Tasks.GgenIgniter.Doctor.igniter/1` (or any of its checks) ever executes.

**Conclusion**: for this specific real gap (an `:only`-restricted `igniter`/`sourceror`
dep in a project that also carries a real, unconditional `{:ggen_igniter, path: ...}`
dependency), Mix's own resolver refuses to run **any** task, doctor included, before
`GgenIgniter.DoctorFixes.check_dep_only/2`/`fix_dep_only!/2` ever get a chance to run.
The "break it via a live consumer project, then run `mix ggen_igniter.doctor --fix` as
a real subprocess, then re-run as a no-op" cycle the task brief describes is
**structurally impossible** for this gap class, independent of whether the fix logic
itself is correct. This independently reproduces (not merely repeats) what
`test/ggen_igniter_doctor_fix_e2e_test.exs`'s own moduledoc already states was found on
2026-08-27 — this verifier hit the identical wall from scratch, unprompted, before
reading that test file's conclusion.

Given that constraint, the only way to real-world-verify
`check_dep_only/2`/`fix_dep_only!/2` is a direct in-process call against a real
`mix.exs` file (the function only ever does `File.read!(Path.join(project_dir,
"mix.exs"))` — it never requires the target directory to be a Mix-resolvable project).
Did this for real, from inside the real `ggen_igniter` project (so the real compiled
`GgenIgniter.DoctorFixes` module was exercised, not a copy), against a separate plain
fixture directory (`/tmp/doctor_adv_verify_directfn_<pid>`, since removed) containing:

```elixir
defp deps do
  [
    {:rdf, "~> 3.0"},
    {:igniter, "~> 0.8", only: [:dev, :test]},
    {:sourceror, "~> 1.7", runtime: false, only: :test},
    {:jason, "~> 1.4"}
  ]
end
```

`mix run -e` output (real, this session), before fix:

```
{:fixable, "igniter dependency in .../mix.exs is restricted ({:igniter, \"~> 0.8\", only: [:dev, :test]}) -- ggen_igniter needs :igniter unconditionally, in every Mix.env"}
{:fixable, "sourceror dependency in .../mix.exs is restricted ({:sourceror, \"~> 1.7\", runtime: false, only: :test}) -- ggen_igniter needs :sourceror unconditionally, in every Mix.env"}
```

After `fix_dep_only!/2` for both:

```
{:fixed, "relaxed :igniter dependency in .../mix.exs: `{:igniter, \"~> 0.8\", only: [:dev, :test]}` -> `{:igniter, \"~> 0.8\"}`"}
{:fixed, "relaxed :sourceror dependency in .../mix.exs: `{:sourceror, \"~> 1.7\", runtime: false, only: :test}` -> `{:sourceror, \"~> 1.7\", runtime: false}`"}
```

Real file re-read from disk confirmed the exact rewritten `deps/0`:

```elixir
defp deps do
  [
    {:rdf, "~> 3.0"},
    {:igniter, "~> 0.8"},
    {:sourceror, "~> 1.7", runtime: false},
    {:jason, "~> 1.4"}
  ]
end
```

`runtime: false` on `sourceror` was correctly preserved (only `only:` was stripped),
confirming the "precise single-occurrence text replacement... any other options...
preserved" claim at `doctor_fixes.ex:101-109`. Re-running `check_dep_only/2` for both
deps afterward returned `{:ok, "... has no :only restriction"}` for both — genuine
no-op, re-verified by calling `fix_dep_only!/2` again and confirming it also returned
`{:ok, ...}` rather than a second `{:fixed, ...}`.

**Verdict for fixes 1/2 overall: the underlying `DoctorFixes` detect/fix/no-op logic is
CONFIRMED correct and real (verified by direct function call against a real file, twice,
covering both the list-`:only` and atom-`:only` shapes and an option-preservation
case). The specific "live `mix ggen_igniter.doctor --fix` subprocess" cycle the task
asked for is REFUTED as reachable for this gap shape — it is blocked one layer up, by
Mix's own dependency resolver, not by any defect in `doctor.ex`/`doctor_fixes.ex`.**

### Claim 5 — `check_git_status` (check 13) never fails the aggregate run by itself, even
for a project with no `.git` at all.

**CONFIRMED** (observed as a side effect of the fixtures above, which had no `git init`
run). Real output on every fixture run: `⚠ not a git repo (or git not on PATH): fatal:
not a git repository (or any of the parent directories): .git` — `:warn`, not `:error`,
and the aggregate exit code was 0 in every run where the only non-`:ok` results were
this warning plus the (also `:warn`) sparql-0.3.12 advisory.

## Summary table

| # | Claim | Verdict |
|---|-------|---------|
| 1 | `check`/`fix_dcatr_env_config!` detect+fix live via `--fix` subprocess | CONFIRMED |
| 2 | `check`/`fix_ash_domains!` detect+fix live via `--fix` subprocess | CONFIRMED |
| 3 | second `--fix` run is a genuine no-op (identical output, exit 0) for fixes 3/4 | CONFIRMED (verified across 2nd AND 3rd runs, byte-diffed) |
| 4 | igniter/sourceror `:only` break/fix/no-op reachable via live `--fix` subprocess | REFUTED for the live-subprocess path (Mix resolver blocks all tasks first, confirmed two independent ways); underlying fix logic CONFIRMED via direct in-process calls instead |
| 5 | git-status check never fails the aggregate run by itself | CONFIRMED |

## Real commands index (for reproducibility)

```
mix deps.get                                              # in fixture, twice (once diverged/blocked, once clean)
MIX_ENV=dev mix compile                                   # in fixture
MIX_ENV=dev mix ggen_igniter.doctor                        # in fixture, pre-fix
MIX_ENV=dev mix ggen_igniter.doctor --fix                  # in fixture, 1st/2nd/3rd runs
mix run -e '... GgenIgniter.DoctorFixes.check_dep_only/fix_dep_only! ...'   # from /Users/sac/ggen_igniter, against plain fixture
```

All throwaway fixtures under `/tmp` were removed after verification
(`rm -r /tmp/doctor_adv_verify_<pid>`, `rm -r /tmp/doctor_adv_verify_directfn_<pid>`,
plus loose scratch txt files); confirmed removed via `ls` returning "no matches found."
No file under `/Users/sac/ggen_igniter` was written or modified by this verification.
