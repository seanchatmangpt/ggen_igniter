# ash_manufacture_pack

A ggen_igniter pack that models an Ash application's **domain semantics** plus the
**generator capability envelope** of the upstream Ash/Igniter mix tasks, and projects
both into a single composed `Igniter.Mix.Task` that calls the real upstream generators.

The pack renders **no Ash resource source**. It renders one orchestrator; Ash's own
`ash.gen.*` tasks write every resource, domain, enum, change, validation and preparation.

Subject of every claim below: `test/fixtures/book_library` at ash 3.33.1,
ash_postgres 2.13.1, igniter 0.8.4, spark 2.7.2, Elixir 1.19.5 / OTP 28.

## Layout

```text
test/fixtures/ash_manufacture_pack/
├── ontology.ttl                    # semantic facts, capability envelope, pins, citations
├── gates/*.rq                      # 13 SPARQL projections, one per template binding
├── templates/manufacture.ex.eex    # renders the composed Igniter.Mix.Task
└── bin/
    ├── day_zero.sh                 # restore the subject to day zero
    ├── qualify.sh                  # the acceptance ladder; runs every check below
    ├── conformance.py              # OCEL log vs capability envelope
    ├── receipt.py                  # machine-readable qualification receipt
    ├── drift_check.py              # ontology vs rendered invocation, both directions
    ├── evidence_check.py           # amp:evidence prose citations resolve
    └── citation_check.py           # amp:Citation anchors still say what they claim
```

Every `bin/` entry is part of `qualify.sh`, not an optional extra. The layout above used
to list only `{day_zero,qualify}.sh` and `{conformance,receipt}.py` while the same README
called the other three non-optional — a doc that disagrees with itself about what runs.

## Rendering the pack

```bash
cd test/fixtures/book_library
mix ggen_igniter.sync --pack-dir ../ash_manufacture_pack
```

`--pack-dir` resolves `ontology.ttl`, every `gates/*.rq` (bound under its filename stem
with the `NNN_` numeric prefix stripped — `GgenIgniter.Pack.discover_queries/1`,
`lib/ggen_igniter/pack.ex:84-99`) and the single `templates/*.eex`. The output path is
not passed on the CLI: the template's frontmatter carries
`to: "lib/mix/tasks/<%= task_name %>.ex"`, so the destination is itself derived from
`amp:manufactureTaskName`.

That writes `lib/mix/tasks/book_library.manufacture.ex`. Then:

```bash
mix book_library.manufacture --phase base --yes
mix book_library.manufacture --phase core --yes
mix ash.codegen --name book_library_manufacture
mix ash.setup
```

`mix ash.codegen --yes` is **BUILD_BROKEN** at these versions: `ash.codegen` is a plain
`Mix.Task` (`ash.codegen.ex:36`) that forwards argv verbatim to
`ash_postgres.generate_migrations`, an Igniter task whose `Info` declares no `yes`
switch, so strict validation rejects it with `--yes : Unknown option`. Do not add it.

## RDF vocabulary

Namespace `amp: <http://seanchatmangpt.github.io/packs/ash-manufacture-pack#>`.

### Project

| Term | Meaning |
| --- | --- |
| `amp:Project` | The single Mix project manufactured into |
| `amp:otpApp` | OTP app atom name, no leading colon |
| `amp:rootModule` | Root Elixir namespace |
| `amp:manufactureTaskModule` | Module name of the rendered composed task |
| `amp:manufactureTaskName` | Mix task name; also drives the frontmatter `to:` path |
| `amp:baseResourceModule` | Module made by `ash.gen.base_resource` |
| `amp:repoModule` | Repo module made by `ash_postgres.install`; used as a guard |

```turtle
amp:BookLibraryProject a amp:Project ;
    amp:otpApp "book_library" ;
    amp:rootModule "BookLibrary" ;
    amp:manufactureTaskModule "Mix.Tasks.BookLibrary.Manufacture" ;
    amp:manufactureTaskName "book_library.manufacture" ;
    amp:baseResourceModule "BookLibrary.Resource" ;
    amp:repoModule "BookLibrary.Repo" .
```

### Domain

`amp:Domain`, `amp:domainModule`, `amp:domainRank` (deterministic ordering key —
ordering is manufactured, not an artifact of SPARQL row order).

```turtle
amp:CatalogDomain a amp:Domain ;
    amp:domainModule "BookLibrary.Catalog" ; amp:domainRank 1 .
```

### Resource

`amp:Resource`, `amp:resourceModule`, `amp:resourceDomain`, `amp:resourceRank`,
`amp:primaryKeyKind` (closed: `uuid` | `uuid_v7` | `integer`), `amp:primaryKeyName`,
`amp:hasTimestamps`, `amp:usesBaseResource`, `amp:defaultAction` (repeatable).

```turtle
amp:BookResource a amp:Resource ;
    skos:closeMatch bibo:Book ;
    amp:resourceModule "BookLibrary.Catalog.Book" ;
    amp:resourceDomain amp:CatalogDomain ;
    amp:resourceRank 1 ;
    amp:primaryKeyKind "uuid" ; amp:primaryKeyName "id" ;
    amp:hasTimestamps true ; amp:usesBaseResource true ;
    amp:defaultAction "create" , "read" , "update" , "destroy" .
```

### Attribute

`amp:Attribute`, `amp:attributeOf`, `amp:attributeName`, `amp:attributeType` (Ash type
atom without leading colon, or a full module name for a custom type),
`amp:attributeOrder`, `amp:isPublic`, `amp:isRequired`, `amp:isSensitive`.

```turtle
amp:BookTitleAttribute a amp:Attribute ;
    skos:closeMatch dcterms:title ;
    amp:attributeOf amp:BookResource ; amp:attributeOrder 1 ;
    amp:attributeName "title" ; amp:attributeType "string" ;
    amp:isPublic true ; amp:isRequired true ; amp:isSensitive false .
```

### Relationship

`amp:Relationship`, `amp:relationshipOf` (the resource it is **declared on**),
`amp:relationshipKind` (closed: `belongs_to` | `has_many` | `has_one` |
`many_to_many`), `amp:relationshipName`, `amp:relationshipTarget`,
`amp:relationshipOrder`, `amp:relationshipRequired` (belongs_to only),
`amp:relationshipPublic`.

```turtle
amp:LoanBookRelationship a amp:Relationship ;
    amp:relationshipOf amp:LoanResource ; amp:relationshipOrder 1 ;
    amp:relationshipKind "belongs_to" ; amp:relationshipName "book" ;
    amp:relationshipTarget amp:BookResource ;
    amp:relationshipRequired true ; amp:relationshipPublic true .
```

### Extension

`amp:Extension`, `amp:extensionOf`, `amp:extensionName` (builtin shorthand or a full
extension module name).

```turtle
amp:BookPostgresExtension a amp:Extension ;
    amp:extensionOf amp:BookResource ; amp:extensionName "postgres" .
```

### Support module

`amp:SupportModule`, `amp:supportModuleName`, `amp:supportKind` (closed: `change` |
`validation` | `preparation` | `enum` | `custom_expression`), `amp:supportRank`,
`amp:enumValue` (repeatable, only meaningful when `supportKind` is `enum`).

```turtle
amp:LoanStatusEnum a amp:SupportModule ;
    amp:supportModuleName "BookLibrary.Circulation.LoanStatus" ;
    amp:supportKind "enum" ; amp:supportRank 1 ;
    amp:enumValue "out" , "returned" , "overdue" .
```

### Generator capability

`amp:GeneratorCapability`, `amp:mixTask`, `amp:standing` (closed: `UNKNOWN` |
`PARTIAL_ALIVE` | `ALIVE` | `BLOCKED` | `BUILD_BROKEN` | `UNSUPPORTED`),
`amp:admitted`, `amp:refusalReason`, `amp:evidence`, `amp:idempotencyMechanism`,
`amp:phase` (closed: `base` | `core` | `lifecycle`).

```turtle
amp:AshGenResourceCapability a amp:GeneratorCapability ;
    amp:phase "core" ; amp:mixTask "ash.gen.resource" ;
    amp:standing "ALIVE" ; amp:admitted true ;
    amp:idempotencyMechanism "ensure_resource_exists/5 skips creation ..." ;
    amp:evidence "deps/ash/lib/mix/tasks/gen/ash.gen.resource.ex:254-267" .
```

### Dependency pin

`amp:DependencyPin`, `amp:pinnedDep` (hex package name as `mix.lock` writes it),
`amp:pinnedVersion` (exact resolved version).

A line number is a **version-scoped fact**: `ash.gen.resource.ex:76` names a line in one
exact tarball, and `mix deps.update` can move it without changing a character of the
ontology. Before these triples the scope existed only as a `#` comment above the
capability instances — and that comment named three dependencies while the file cited
four (it omitted `spark`, cited twice). A comment cannot fail; a pin can.

```turtle
amp:AshPin a amp:DependencyPin ;
    amp:pinnedDep "ash" ; amp:pinnedVersion "3.33.1" .
```

### Citation

`amp:Citation`, `amp:citesFile` (path relative to the subject), `amp:citesLine`,
`amp:citesEndLine` (optional; absent means a single line), `amp:citesSymbol`,
`amp:citesPin`, `amp:supports` (an `amp:GeneratorCapability`), `amp:citedProperty`
(closed: `evidence` | `idempotencyMechanism` | `refusalReason`).

`amp:evidence` is kept as prose and **demoted from load-bearing**; `amp:Citation` is what
a machine resolves. `amp:citesSymbol` is the property that does the work: a token that
must occur inside the cited slice, which turns "the range exists" into "the range still
says it". Three real off-by-N defects passed the range-only check and are caught by this
one — see [Anchors, not line numbers](#anchors-not-line-numbers).

```turtle
amp:AshGenResourceIgnoreIfExistsCitation a amp:Citation ;
    amp:citesFile "deps/ash/lib/mix/tasks/gen/ash.gen.resource.ex" ;
    amp:citesLine 76 ;
    amp:citesSymbol "ignore_if_exists" ;
    amp:supports amp:AshGenResourceCapability ; amp:citedProperty "evidence" ;
    amp:citesPin amp:AshPin .
```

## Public-term grounding

Domain semantics are grounded in published terms wherever a real one exists, recorded as
`skos:closeMatch` (never `exactMatch` — an Ash resource is a persisted record, not an
instance of the source term's class).

| Fact | Public term | Note |
| --- | --- | --- |
| `amp:BookResource` | `bibo:Book` | Bibliographic record sense |
| `title` | `dcterms:title` | |
| `isbn` | `bibo:isbn` | |
| `page_count` | `bibo:numPages` | |
| `published_on` | `dcterms:issued` | |
| `amp:LoanResource` | `schema:LendAction` | Library lends; see below |
| `borrower_name` | `foaf:name` | `schema:borrower` as `rdfs:seeAlso` |
| `copies_total` | **NOT_FOUND** | Operational holdings count |
| `due_on` | **NOT_FOUND** | No public due-date property |

`schema:BorrowAction` is the borrower's side of the reciprocal pair, so `LendAction` is
the correct one for a library. `copies_total` has no public bibliographic term modelling
it. Every schema.org `*Due*` term is payment/order scoped (`schema:paymentDueDate` and
friends) and `dublin-core-terms.ttl` has none, so `due_on` carries no match either.

There is no canonical bibliographic loan class: a case-insensitive search of the local
`bibo.ttl` for loan/circulation/checkout/borrow/lend returns nothing, and no FRBR file is
present. `schema:LendAction` (`schema-org.ttl:2788`, `subClassOf schema:TransferAction`)
is the closest published term. The two NOT_FOUND fields carry no `skos:closeMatch` rather
than a force-fitted one.

## The 13 gates

Each `gates/NNN_<name>.rq` binds `<name>` in the template as a list of string-keyed row
maps. A one-row result additionally flattens its columns into bare top-level bindings —
which is why the template writes `otp_app` and `task_name`, not `hd(project)["otp_app"]`.

Because a gate's name and its column names both become template bindings, adding a gate
extends a real interface. `090`/`092` therefore prefix every column (`citation_*`,
`pinned_*`) so they cannot collide with `080`/`085`'s `mix_task`, `standing` or `evidence`.

- **`010_project.rq` → `project`** — `otp_app`, `root_module`, `task_module`,
  `task_name`, `base_resource_module`, `repo_module`. Single row, so these flatten to
  bare bindings. Supplies the module header, `:group`, the frontmatter `to:` path, the
  `--base` value and the `ash_postgres.install` repo guard.
- **`020_domains.rq` → `domains`** — `domain_module`, `domain_rank`. One
  `ash.gen.domain` plan step per row, ordered by rank.
- **`030_resources.rq` → `resources`** — `resource_module`, `domain_module`,
  `resource_rank`, `pk_kind`, `pk_name`, `has_timestamps`, `uses_base`. One
  `ash.gen.resource` step per row; joins through `amp:resourceDomain` to the domain.
- **`035_default_actions.rq` → `default_actions`** — `resource_module`, `action`.
  Filtered per resource and joined into one `--default-actions` csv.
- **`040_attributes.rq` → `attributes`** — `resource_module`, `attribute_name`,
  `attribute_type`, `attribute_order`, `is_public`, `is_required`, `is_sensitive`.
  One `--attribute` flag per row, in `attribute_order`.
- **`050_relationships.rq` → `relationships`** — `resource_module`,
  `relationship_kind`, `relationship_name`, `target_module`, `relationship_order`,
  `relationship_required`, `relationship_public`. One `--relationship` flag per row.
- **`060_extensions.rq` → `extensions`** — `resource_module`, `extension_name`.
  Joined into one `--extend` csv per resource.
- **`070_support_modules.rq` → `support_modules`** — `support_module`, `support_kind`,
  `support_rank`. One `ash.gen.<kind>` step per row, rank-ordered.
- **`075_enum_values.rq` → `enum_values`** — `support_module`, `enum_value`. Joined
  into the positional types csv for `ash.gen.enum`.
- **`080_capabilities.rq` → `capabilities`** — `mix_task`, `standing`, `admitted`,
  `phase`, `idempotency_mechanism`, `evidence`. The fail-closed admission gate, the
  phase assignment, and the per-capability moduledoc table.
- **`085_refusals.rq` → `refusals`** — `mix_task`, `standing`, `refusal_reason`.
  Only `amp:admitted false` rows; becomes `@refusals` and its `capability_refused`
  events.
- **`090_citations.rq` → `citations`** — `citation_file`, `citation_line`,
  `citation_end_line`, `citation_symbol`, `citation_mix_task`, `cited_property`,
  `pinned_dep`, `pinned_version`. One row per checkable anchor, joined through
  `amp:supports` to the capability and `amp:citesPin` to the version it is valid at.
  `amp:citesEndLine` is genuinely optional (20 of 41 anchors are single-line), so the
  gate uses `OPTIONAL` + `COALESCE` rather than a conjunctive pattern that would
  silently drop those rows. Both constructs were run on both engines before being
  trusted: 41 rows, 0 unbound, on `sparql` 0.3.12 and on the oxigraph NIF alike.
- **`092_dependency_pins.rq` → `dependency_pins`** — `pinned_dep`, `pinned_version`.
  Deliberately no aggregate. An earlier revision selected `(COUNT(?cite) AS
  ?citation_count)` with a `GROUP BY`; oxigraph returned the right 4 rows, but the
  **default** engine (`sparql` hex 0.3.12, the one `GgenIgniter.Query.run/2` uses to
  render this pack) returned 41 rows with `GROUP BY` silently ignored and
  `citation_count` bound to a nested `SPARQL.Query.Result` struct — wrong rows, no
  error. Per-pin counts live in `citation_check.py`, which computes them against real
  files. A gate that is confidently wrong on the engine that actually renders the pack
  is the same fail-open shape this workstream exists to remove.

## argv is derived, never stored

The ontology stores zero CLI strings. `templates/manufacture.ex.eex` derives every flag.

| Ontology triple | Rendered flag |
| --- | --- |
| `amp:primaryKeyKind "uuid"` | `--uuid-primary-key id` |
| `amp:primaryKeyKind "uuid_v7"` | `--uuid-v7-primary-key <pk_name>` |
| `amp:primaryKeyKind "integer"` | `--integer-primary-key <pk_name>` |
| `amp:defaultAction` × 4 | `--default-actions create,read,update,destroy` |
| `amp:extensionName "postgres"` | `--extend postgres` |
| `amp:hasTimestamps true` | `--timestamps` |
| `amp:usesBaseResource true` | `--base BookLibrary.Resource` |
| `amp:resourceDomain` → `amp:domainModule` | `--domain BookLibrary.Catalog` |
| `amp:enumValue "out","returned","overdue"` | positional `out,returned,overdue` to `ash.gen.enum` |

Attributes and relationships are colon-joined rather than tabulated, because their flag
values are composites:

```text
amp:attributeName "title" + amp:attributeType "string"
  + amp:isPublic true + amp:isRequired true + amp:isSensitive false
    -> --attribute title:string:public:required

amp:attributeName "borrower_name" + amp:isSensitive true
    -> --attribute borrower_name:string:public:required:sensitive

amp:relationshipKind "belongs_to" + amp:relationshipName "book"
  + amp:relationshipTarget -> "BookLibrary.Catalog.Book"
  + amp:relationshipPublic true + amp:relationshipRequired true
    -> --relationship belongs_to:book:BookLibrary.Catalog.Book:public:required
```

`required` is only appended to a relationship when the kind is `belongs_to`, matching
what the upstream generator accepts.

Modifier order in an `--attribute` value is fixed at `public`, then `required`, then
`sensitive`, so a re-render is byte-stable.

## Capability envelope and typed refusal

Every `amp:GeneratorCapability` carries a `standing`, an `admitted` boolean, a `phase`,
an `idempotencyMechanism` and `evidence` (file:line or exact command output — no standing
without evidence). `admitted false` additionally carries a `refusalReason`.

The template consults `admitted` before emitting a plan step. An unadmitted capability is
**not silently skipped**: it is rendered into `@refusals`, and every phase run emits a
`capability_refused` OCEL event carrying its standing and reason. `conformance.py` treats
an inadmissible capability with no matching refusal event as a hard violation
("silently skipped, not refused"), and treats composing a non-admitted task as a hard
violation too.

Current non-admitted capabilities:

- `ash.gen.custom_expression` — **BUILD_BROKEN**. The generator emits `args: [...]`
  (`ash.gen.custom_expression.ex:46`) but `Ash.CustomExpression.__using__/1` raises
  `ArgumentError` unless `arguments:` is given (`ash/lib/ash/custom_expression.ex:113-115`),
  so every module it produces fails to compile. `amp:BookTitleLengthExpression` is still
  modelled as a fact, so the refusal is derived from the ontology rather than hard-coded.
- `ash.tear_down`, `ash.reset` — **UNSUPPORTED**, destructive. (`ash_postgres.reset` does
  not exist; the real task is `ash.reset`.)

Phases exist for two evidenced upstream reasons, not tidiness:

1. `ash.gen.resource --base X` validates X against
   `Application.get_env(app, :base_resources)`, and config written earlier in the same
   Igniter run is not yet loaded, so the base resource must be committed by a prior mix
   invocation.
2. `Igniter.update_all_elixir_files/2` short-circuits on the `included_all_elixir_files?`
   assign (`igniter.ex:1112-1123`), which any `find_module` full scan already sets
   (`igniter/project/module.ex:475`). So `ash.gen.base_resource`'s retrofit leg
   (`ash.gen.base_resource.ex:59`) does nothing inside a run that has already looked a
   module up. Reproduced: a composed run with base_resource ordered last left
   `lib/book_library/catalog/book.ex` reading `use Ash.Resource`. The pack uses the
   supported `--base` flag instead of depending on that retrofit.

`lifecycle` steps (`ash.codegen`, `ash.setup`) are never composed into an Igniter run:
they must observe compiled resources.

## bin/

### `day_zero.sh`

Restores the fixture to its documented day-zero state: a plain Mix project declaring
ash/ash_postgres/igniter and nothing else — no domain, resource, repo, Application
module, migration, snapshot or manufactured mix task. It removes only an enumerated list
of manufactured paths and never touches `deps/`, `_build/` or `mix.lock`. Run 1 must
start from a known subject or "run 1 vs run 2" is not a controlled comparison.

```bash
bash test/fixtures/ash_manufacture_pack/bin/day_zero.sh test/fixtures/book_library
```

### `qualify.sh`

The full acceptance ladder A–J, every rung an observed execution: deps resolve, day-zero
compile, `ggen_igniter.sync`, phase base, compile, database isolation rewrite, phase core,
`ash.codegen`, `ash.setup`, then run 2 under both oracles. It writes `steps.jsonl`,
per-step `NN-*.log`, `T0/T1/T2` tree hashes, `T1-vs-T2.diff`, `ocel-run1/`, `ocel-run2/`,
`db-isolation.txt` and `conformance.json` into `test/fixtures/.qualification/book_library`
(outside the fixture, because `day_zero.sh` deletes `.ggen_igniter/`).

```bash
bash test/fixtures/ash_manufacture_pack/bin/qualify.sh
# or: bash .../qualify.sh <fixture-path>   (QUALIFY_OUT, BOOK_LIBRARY_QUAL_DB honored)
```

Idempotency is asserted two ways. Exit code alone is not an oracle: a "File already
exists" conflict is added via `Igniter.add_issue/2` and `do_or_dry_run` returns `:issues`
without halting (`igniter.ex:1279-1281`). So the harness uses Igniter's own `--check`,
which halts non-zero on any change, warning, issue, queued task, move or removal
(`halt_if_fails_check!/3`, `igniter.ex:1293-1330`), **and** compares the run-1 and run-2
tree hashes byte for byte.

Database isolation: before any DB-touching step, the harness rewrites the manufactured
repo config to a run-scoped database (default `book_library_qual`) and records the
rewrite in `db-isolation.txt`. A filesystem-disposable copy still pointed at the original
database would not be isolated.

### `conformance.py`

Reads the emitted OCEL 2.0 logs plus the ontology's capability envelope and answers four
questions: **coverage** (every admitted plan step appears as an event), **admission** (no
event composed a task the ontology does not admit), **refusal** (every inadmissible
capability has a real `capability_refused` event), and **order** (base-phase events
precede core-phase events, and guarded steps flip from `task_composed` on run 1 to
`task_admission_refused` on run 2). Exit 0 = conformant.

```bash
python3 test/fixtures/ash_manufacture_pack/bin/conformance.py \
  test/fixtures/book_library test/fixtures/.qualification/book_library
```

It computes **no SPC**. Two runs are not a time series; Western-Electric rules over n=2
would manufacture significance rather than evidence. The output says so in an `spc` field
rather than leaving the omission to be inferred.

### `receipt.py`

Emits the machine-readable qualification receipt (rung J), read back entirely from
artifacts a real run produced: step exit codes, tree hashes and their equality, OCEL
document shapes and digests, resolved `mix.lock` versions, Elixir/OTP/Postgres versions,
repo HEAD/branch/dirty, the live database name, the ontology and per-gate and template
SHA-256s, and the capability matrix parsed back out of `ontology.ttl`. A missing artifact
yields `null` and degrades `standing`; no field is filled in from intent.

```bash
python3 test/fixtures/ash_manufacture_pack/bin/receipt.py \
  test/fixtures/book_library test/fixtures/.qualification/book_library > receipt.json
```

Five standing booleans are computed: `ONTOLOGY_ALIVE` (`receipt.py:279`),
`ASH_MANUFACTURE_ALIVE` (`:280`), `IDEMPOTENCY_ALIVE` (`:294`), `OCEL_PROCESS_ALIVE`
(`:295`) and `AGENT_HANDWRITE_REFUSAL_ALIVE` (`:298`). This section said four and named
the first four — the fifth, which reports whether the hand-written-Ash guard is live, was
computed and emitted but never documented.

### `citation_check.py`

Resolves every `amp:Citation` anchor against the real, pinned dependency source: it opens
`<fixture>/<citesFile>`, slices `citesLine..citesEndLine`, and asserts `citesSymbol`
occurs in that slice. It also reconciles every `amp:DependencyPin` against the subject's
real `mix.lock`.

```bash
python3 test/fixtures/ash_manufacture_pack/bin/citation_check.py \
  test/fixtures/ash_manufacture_pack test/fixtures/book_library
# {"all_anchored": true, "anchors_checked": 41, "misses": [], "pin_drift": [], ...}
```

Pin drift is reported as its **own** failure class, and the anchors of a drifted package
are listed as suppressed rather than checked. A `mix deps.update` then reads as one cause
(`pin drift: ash declared 3.34.0, mix.lock has 3.33.1`) instead of 31 separate anchor
misses whose shared root the reader has to infer.

Like the other checkers it parses Turtle with narrow regexes and adds no RDF library, so
the qualification ladder depends on nothing the manufacturing subject does not resolve.

### Anchors, not line numbers

`evidence_check.py` asserts a cited file exists and a cited range fits inside it. Its own
docstring concedes the rest: it does not verify the cited lines say what the claim says.
That is not a theoretical gap. Three off-by-N defects lived inside citations it passed:

| Cited | Actually at | What was claimed |
| --- | --- | --- |
| `ash.gen.resource.ex:74` | `:76` | `ignore_if_exists` in the schema (`:74` is `da: :string,`) |
| `igniter/project/module.ex:475` | `:474` | `defp try_full_scan` (`:475` is its first body line) |
| `ash.gen.custom_expression.ex:46` | `:45` | the emitted `args: [...]` (`:46` is blank) |

All three are inside their files, so all three passed. Restoring them and re-running both
checks is the measurement of what the anchor buys:

```bash
# with :74, :475 and :46 restored in the SAME ontology file
python3 bin/citation_check.py . ../book_library    # exit 1, names all three symbols
python3 bin/evidence_check.py . ../book_library    # exit 0, "all_resolve": true
```

The third was found *by* the anchor check while converting the first two, which is the
only reason it is in this table rather than still in the file.

## Added after adversarial review

Three scripts and one mix task were added to close blockers found by
[../../../docs/jira/v26.9.8/08-REVIEW-MANUFACTURE-PATH.md](../../../docs/jira/v26.9.8/08-REVIEW-MANUFACTURE-PATH.md).
They are part of `qualify.sh`, not optional extras.

| Artifact | What it closes |
|---|---|
| `bin/drift_check.py` | ontology vs rendered invocation, in BOTH directions — direction two catches a hand-edit of the generated task |
| `bin/evidence_check.py` | every `amp:evidence` `deps/` citation and line range must resolve; a dangling citation was found and nothing had caught it |
| `bin/citation_check.py` | a cited range must still CONTAIN its `citesSymbol`, and every pin must match `mix.lock`; three off-by-N citations had passed `evidence_check.py` |
| `mix ggen_igniter.ocel.seal` | the manufacture task emits from inside `igniter/1`, before Igniter applies anything, so a log must be sealed with an observed outcome; `conformance.py` rejects an unsealed log |
| run-scoped database | `book_library_qual_<utc>` — a leftover database from a previous run broke `ash.setup`; day zero on disk is not day zero for the subject |

`evidence_check.py` was itself raised twice in the same pass. It now resolves bare `:NNN`
continuation references against the preceding `deps/` path (its old regex required a
literal `deps/` prefix, so `...ash.extend.ex:40-52 (Info), :57, :264-277` resolved one of
three references and ignored two — checked count went from 25 to 42), and it makes the
line range **unconditional for any `amp:admitted true` capability**. Ten of the original
25 references were whole-file, and the set included `ash_postgres.install.ex` — 643
lines, backing a live guard and idempotency claim. Three whole-file citations remain, all
on `amp:admitted false` capabilities whose claim genuinely is whole-file ("this file
declares `use Igniter.Mix.Task`, and this pack never ran it").

Each was falsified before being trusted:

```bash
# drift check, direction 2 -- inject an argument with no fact behind it
python3 bin/drift_check.py . <rendered-task>          # exit 0, no drift
# ...then add an extra "--attribute" and re-run       # exit 1, names it

# evidence check -- point a citation at a file that does not exist
python3 bin/evidence_check.py . ../book_library       # exit 0, all resolve
# ...then move ash.install.ex up one directory        # exit 1, "dangling citation"
# ...or cite an admitted capability's file whole      # exit 1, "must name lines"

# citation check -- shift one amp:citesLine by 1
python3 bin/citation_check.py . ../book_library       # exit 0, 41 anchors, 0 misses
# ...then set citesLine 76 -> 77 and re-run           # exit 1, names file/line/symbol
# ...and evidence_check.py on that same file          # exit 0 -- what the anchor buys

# citation check, pin half -- declare ash 3.34.0
python3 bin/citation_check.py . ../book_library       # exit 1, one "pin drift" line,
                                                      # 31 ash anchors listed suppressed

# seal -- strip the seal from a real log and re-run conformance
python3 bin/conformance.py x <out-dir>                # conformant: false
```

A check that has never been observed failing is not evidence that the property
holds; it is evidence that nothing was measured.

## Adapting the pack to another Ash project

The gates and the template are project-agnostic; only `ontology.ttl` instances change.

1. Copy the pack directory. Leave `gates/` and `templates/` alone.
2. Replace the `amp:Project` instance: `otpApp`, `rootModule`, `manufactureTaskModule`,
   `manufactureTaskName`, `baseResourceModule`, `repoModule`. The frontmatter `to:` path
   follows `manufactureTaskName` automatically.
3. Replace the `amp:Domain` / `amp:Resource` / `amp:Attribute` / `amp:Relationship` /
   `amp:Extension` / `amp:SupportModule` instances with your own. Keep `*Rank` and
   `*Order` values dense and unique — they are the only ordering guarantee.
4. Ground new domain terms in published vocabularies where a real term exists, as
   `skos:closeMatch`. Where none exists, omit the match and say so in an `rdfs:comment`.
5. Re-verify the capability envelope against **your** resolved dependency versions. The
   standings here are scoped to ash 3.33.1 / ash_postgres 2.13.1 / igniter 0.8.4; a
   different version set can move a task between `ALIVE`, `PARTIAL_ALIVE` and
   `BUILD_BROKEN`. Update `amp:evidence` to the file:line you actually read.
6. If you drop the base resource, set `amp:usesBaseResource false` on every resource and
   remove the `ash.gen.base_resource` capability — the `base` phase then holds only the
   two install steps.
7. Point `day_zero.sh`'s `MANUFACTURED` array at your project's manufactured paths, and
   adjust the fixture-specific `lib/*.ex` and `config/*.exs` heredocs.
8. Run `bin/qualify.sh <your-fixture>` and require exit 0 before trusting the pack.

## See also

- `test/fixtures/book_library` — the manufacturing subject
- `test/fixtures/.qualification/book_library` — qualification evidence
- `lib/ggen_igniter/telemetry/ocel2_export.ex` — OCEL 2.0 serializer
- `.claude/hooks/refuse-handwritten-ash.sh` — blocks hand-authoring `use Ash.Resource`
  and `use Ash.Domain` outside the allowlist
