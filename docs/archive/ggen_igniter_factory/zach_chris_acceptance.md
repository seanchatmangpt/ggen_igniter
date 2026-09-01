# Zach Daniel / Chris McCord Acceptance Review — ggen_igniter (Agent 9)

Reviewed 2026-08-27. Sources read in full: `test/fixtures/ash-lifecycle-pack/templates/resource.ex.eex`,
`test/fixtures/ash-lifecycle-pack/templates/domain.ex.eex`, `test/e2e/lifecycle_test.ex`,
`lib/mix/tasks/ggen_igniter.sync.ex` moduledoc, `README.md`, `CHANGELOG.md`.

## 1. Zach Daniel verdict — "Does Ash remain the authoritative application model?"

**Real generated code, quoted verbatim** (rendering `resource.ex.eex` against `ontology.ttl`,
per `test/e2e/lifecycle_test.ex` Stage 1 assertions, lines 143-151):

```elixir
defmodule SupportDesk.Support.Ticket do
  @moduledoc """
  Ash.Resource for `Ticket`, backed by `Ash.DataLayer.Ets`.

  Manufactured by ggen_igniter from the admitted alp: ontology (pack
  test/fixtures/ash-lifecycle-pack/) -- do not hand-edit; regenerate from the
  ontology instead.
  """

  use Ash.Resource,
    domain: SupportDesk.Support,
    data_layer: Ash.DataLayer.Ets

  attributes do
    uuid_primary_key(:id)
    attribute :subject, :string do
      allow_nil?(false)
      public?(true)
    end
    attribute :status, :atom do
      allow_nil?(false)
      public?(true)
      default(:open)
    end
    attribute :assignee, :string do
      allow_nil?(true)
      public?(true)
    end
  end

  actions do
    default_accept(:*)
    defaults([:create, :read, :update, :destroy])
  end

  relationships do
    belongs_to :customer, SupportDesk.Support.Customer do
      attribute_writable?(true)
      source_attribute(:customer_id)
    end
  end
end
```

This is **byte-for-byte ordinary Ash DSL** — `use Ash.Resource, domain: ..., data_layer: ...`,
`attributes do ... attribute :x, :type do allow_nil?/public?/default end end`,
`actions do defaults([...]) end`, `relationships do belongs_to/has_many ... end`. A human
running `mix ash.gen.resource` and hand-filling in the block bodies would produce
structurally identical code. There is no ggen-specific DSL wrapper, no macro indirection, no
custom `use GgenIgniter.Resource` — the generated module's only "manufactured" marker is a
`@moduledoc` sentence, which is documentation, not code shape.

**Namespace-leakage grep** (`grep -n "GgenIgniter" test/fixtures/ash-lifecycle-pack/templates/*.eex`):

```
domain.ex.eex:14:  injecting into an existing file: `GgenIgniter.Actuate.inject_content!/5`
domain.ex.eex:15:  exists in this codebase but `Mix.Tasks.GgenIgniter.Sync` never calls it for
```

Both hits are inside `domain.ex.eex`'s own `@moduledoc` prose (explaining, to a future
maintainer, why this template regenerates the whole file instead of injecting) — they name
the *pipeline's own* modules as commentary about the generation mechanism, not as an
identifier, import, `use`, or call inside the generated `SupportDesk.Support` domain
module's actual code body. **Verdict: PASS, no functional/structural `GgenIgniter.*`
leakage into generated application code** — the domain module itself
(`domain.ex.eex` lines 21-25 rendered) is plain `use Ash.Domain` / `resources do resource(...) end`.

**Does a domain change stay coherent without hand-editing derived layers?** Real answer from
the e2e, not a survey:

- Stage 2 (add `priority` attribute) and Stage 3 (relationships) are handled cleanly:
  re-running `mix ggen_igniter.sync` regenerates `ticket.ex` as a superset (lines 157-174,
  187-205) — no hand-edit needed, no drift.
- Stage 4 (custom `:archive` action) is likewise auto-coherent (lines 207-212).
- **Stage 7 (rename `assignee` -> `assigned_to`) is the disclosed failure mode the mission
  calls a manufacturing defect.** Per `lifecycle_test.ex` lines 279-316: after the resource
  regenerates cleanly (old name gone, new name present, everything else survives), the test
  explicitly asserts `mix compile --warnings-as-errors` **raises**, because Stage 6's
  `ash_phoenix.gen.live`-generated `TicketLive.Index`/`TicketLive.Show` still dot-access the
  now-gone `ticket.assignee` / `@ticket.assignee`, and `ggen_igniter` "only ever regenerates
  the ONE file its own `--template`/`--out` ... targets — it has no knowledge of Stage 6's
  separately-generated" LiveView files (lines 297-304, code comment, not paraphrase).

  This is honestly disclosed in-source ("no cross-file stale-reference repair anywhere in
  this codebase") rather than hidden, but functionally it **is** exactly the "restore write
  access to derived files" defect class: an Ash schema change does not propagate to the
  derived AshPhoenix/LiveView layer automatically — a human must re-run
  `ash_phoenix.gen.live` (or hand-edit) after every rename/removal that a generated LiveView
  references. The system currently offers no automated re-sync of AshPhoenix.Form/LiveView
  consequences; it only guarantees the failure is loud (a real compile error naming
  `assignee`) rather than silent.

**Zach Daniel score: PARTIAL PASS.** Ash resource/domain generation itself is idiomatic and
free of dialect leakage (full pass on that specific question). The "derived Phoenix/AshPhoenix
consequences stay coherent automatically" half of the test **fails today** — Stage 7 proves a
real, reproducible break in the LiveView layer on an Ash-level rename, with no automated
repair path, only a loud compile failure. Recorded as an implementation-scope finding, see
ledger entry below (not fixed here per this role's write-scope restriction).

## 2. Chris McCord verdict — "Is the result ordinary, understandable Phoenix?"

**Real flag count per `mix ggen_igniter.sync` invocation**, from `sync!/3`
(`lifecycle_test.ex` lines 350-366), used identically for all 4 real sync calls across the
8 stages (Stage 1 x2, Stage 2 x1, Stage 7 x1):

```
mix ggen_igniter.sync --pack-dir <dir> --ontology <path> --template <path> --engine sparql
```

**4 flags per call** (`--pack-dir`, `--ontology`, `--template`, `--engine`), not the stated
DX bar of "one clean `--pack NAME` call." Three of those four flags are load-bearing for a
real, disclosed reason each, per the test's own comments:

- `--ontology` and `--template` are both required explicitly because this fixture pack ships
  **two** templates (`resource.ex.eex`, `domain.ex.eex`), so `GgenIgniter.Pack`'s
  single-template auto-selection (`--pack NAME` alone) cannot disambiguate — the task's own
  moduledoc documents a `--pack NAME:TEMPLATE_STEM` syntax (e.g.
  `--pack ash-lifecycle-pack:resource`) that exists precisely to collapse this back toward
  one clean flag, but the e2e test does not use it — it uses the more verbose
  `--pack-dir`/`--template`/`--ontology` explicit form instead.
- `--engine sparql` is pinned only to work around a real, currently-open bug: the CLI's own
  default engine (`oxigraph`, per `sync.ex` line 326) mangles string values (embeds literal
  quote characters in bound template variables, confirmed via a real `--dry-run` probe cited
  in the test's own comment, lines 328-349) — so the e2e test cannot use the zero-flag
  default at all today without breaking its own generated paths/content.

**Chris McCord score against the stated DX bar: FAIL as currently exercised.** The one-clean-
call bar (`mix ggen_igniter.sync --pack NAME`) is architecturally present in the code
(`--pack NAME:TEMPLATE_STEM`, pack-derived ontology/query discovery) but the real e2e
invocation actually used is 4 hand-threaded flags, not 1 — and one of those 4 is a
workaround for a live default-engine correctness bug, not an ergonomics choice. A developer
following the CLI's own documented "clean" path (`--pack ash-lifecycle-pack:resource`) would
still need `--engine sparql` today to get correct output, making the realistic minimum "clean"
invocation for this pack **2 flags** (`--pack NAME:STEM` + `--engine sparql`), not the stated
1.

**Generated LiveView/router wiring**: `mix ash_phoenix.gen.live` (Stage 6, lines 247-260) is
the real upstream `ash_phoenix` generator, invoked with zero `ggen_igniter`-specific
machinery — `--domain`, `--resource`, `--resource-plural`, `--yes` are all real
`ash_phoenix` flags. Router wiring is added by the test as literal, ordinary Phoenix
(lines 391-395: `live "/tickets", TicketLive.Index, :index`, etc.) — exactly what a human
following `ash_phoenix.gen.live`'s own printed Igniter notice would type by hand (the task
itself only prints instructions; it does not patch `router.ex`). **Verdict: PASS** — the
LiveView/router layer is unmodified, recognizable, idiomatic Phoenix/Ash-Phoenix, introduced
by the real upstream generator, not by `ggen_igniter`.

## 3. Concrete pass/fail summary

| Criterion | Evidence | Verdict |
|---|---|---|
| Generated resource is idiomatic Ash DSL, not a dialect | Quoted `ticket.ex` output above: standard `attributes do`/`actions do`/`relationships do` | PASS |
| No `GgenIgniter.*` leakage into generated app code | `grep` hit count: 2, both in `domain.ex.eex`'s own `@moduledoc` prose, none in generated identifiers/calls | PASS |
| Ash-level attribute add/rename stays coherent automatically | Stages 2/3/4 auto-coherent; Stage 7 rename **causes a real, asserted compile failure** in `TicketLive.Index`/`Show` with no auto-repair | FAIL (loud, disclosed, but unresolved) |
| CLI invocation is "one clean `--pack NAME` call" | Real `sync!/3` used 4 flags (`--pack-dir`, `--ontology`, `--template`, `--engine`) across all 4 real sync calls in the e2e | FAIL as exercised (2-flag minimum achievable via `--pack NAME:STEM` + engine pin, not the stated 1) |
| Default engine (`oxigraph`) usable without a workaround flag | e2e must pin `--engine sparql` to avoid a real quote-corruption bug in the default oxigraph engine, confirmed via `--dry-run` probe | FAIL (open bug forces a 4th flag) |
| LiveView/router layer is ordinary, recognizable Phoenix | `ash_phoenix.gen.live` real upstream generator + hand-added literal `live "/tickets", ...` routes | PASS |

## 4. Explicit reject-or-accept

**Qualified ACCEPT, not unconditional.** The Ash-resource-generation core of this pipeline
genuinely satisfies "the developer should notice the capability, not the machinery" —
the generated `.ex` files are indistinguishable in shape from hand-written Ash, and there is
no dialect leakage. But two real, evidenced gaps keep this short of full acceptance today:

1. Ash-to-LiveView coherence is not automatic on a rename/remove — the developer must notice
   and manually re-run `ash_phoenix.gen.live` (or hand-patch) after such a change; the system
   only guarantees the break is loud, not that it doesn't happen.
2. The CLI's real per-invocation ergonomics (4 flags, one of them a bug workaround) fall
   short of the stated "one clean `--pack NAME` call" bar as actually exercised in the
   canonical e2e test, even though a narrower path to ~1-2 flags exists in the code
   (`--pack NAME:STEM`) and is undocumented-in-practice (not used by the project's own
   reference e2e).

Both gaps are honestly disclosed in-source and in `README.md`'s "Known Limitations" section —
this is a project practicing real disclosure discipline, not overclaiming completeness — but
disclosure does not change the underlying acceptance-test outcome: as of 2026-08-27, this
system does not yet fully clear either the Zach Daniel or the Chris McCord bar without
qualification.
