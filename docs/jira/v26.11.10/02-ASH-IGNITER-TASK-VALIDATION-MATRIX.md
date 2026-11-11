# Upstream Ash 3.x & Igniter 0.8+ Task Capability Validation Matrix (v26.11.10)

Comprehensive audit and standing classification of all generator tasks provided by Ash 3.x,
Igniter 0.8+, and AshPostgres 2.x as driven by `ggen_igniter`.

- **Release Version:** `26.11.10`
- **Toolchain Grounding (from mix.lock):**
  - `ash`: `3.33.11`
  - `igniter`: `0.8.4`
  - `spark`: `2.7.3`
  - `ash_postgres`: `2.13.1`
  - `ecto`: `3.14.2`
- **Machine Evidence:** [evidence/receipt.json](evidence/receipt.json), [evidence/conformance.json](evidence/conformance.json)

---

## 1. Standing Vocabulary

In accordance with repository operating doctrine, capabilities are categorized into 5 mutually exclusive, verifiable standings:

| Standing | Definition |
|---|---|
| `ALIVE` | Directly observed and qualified in executed runs with passing tests and verified output on disk. |
| `PARTIAL_ALIVE` | Partially functional; generates valid code for certain options but exhibits limitations or requires strict invocation sequences. |
| `BUILD_BROKEN` | Upstream generator emits code or raises exceptions that fail compilation or break toolchain execution. |
| `UNSUPPORTED` | Capability cannot be expressed by the upstream generator; requires typed refusal rather than silent omission or handwriting. |
| `UNKNOWN` | Unverified; no observed execution in this fixture. Never admitted as an active capability without proof. |

---

## 2. Generator Capability Validation Matrix

The following matrix documents all 21 generator capabilities declared in `priv/ggen/ash-manufacture-pack/ontology.ttl`:

| # | Task Name | Module / Dependency Source | Standing | Phase | Idempotency Mechanism | Notes / Evidence |
|---|---|---|---|---|---|---|
| 1 | `ash.install` | `deps/ash/lib/mix/tasks/ash.install.ex:1` | `ALIVE` | `base` | Igniter notice on re-run | Wires Ash dependencies and core configuration in `config.exs`. |
| 2 | `ash_postgres.install` | `deps/ash_postgres/lib/mix/tasks/ash_postgres.install.ex:1` | `ALIVE` | `base` | Ecto repo configuration check | Configures Repo, AshPostgres DataLayer, and repo supervision tree entry. |
| 3 | `ash.gen.base_resource` | `deps/ash/lib/mix/tasks/gen/ash.gen.base_resource.ex:1` | `PARTIAL_ALIVE` | `base` | Module existence check (`on_exists: :error`) | Must run in `base` phase. Requires `base_resources` config loaded before compiling resources. |
| 4 | `ash.gen.domain` | `deps/ash/lib/mix/tasks/gen/ash.gen.domain.ex:1` | `PARTIAL_ALIVE` | `core` | Composed via `compose_task/4` | Strict CLI argv rejects `--ignore-if-exists`; succeeds when composed in-memory. Appends to `ash_domains`. |
| 5 | `ash.gen.resource` | `deps/ash/lib/mix/tasks/gen/ash.gen.resource.ex:1` | `ALIVE` | `core` | `--ignore-if-exists` switch supported | Generates resource module, derives public accept-lists, and wires domain. |
| 6 | `ash.gen.enum` | `deps/ash/lib/mix/tasks/gen/ash.gen.enum.ex:1` | `ALIVE` | `core` | `--ignore-if-exists` switch supported | Generates `Ash.Type.Enum` modules. |
| 7 | `ash.gen.change` | `deps/ash/lib/mix/tasks/gen/ash.gen.change.ex:1` | `ALIVE` | `core` | Module existence check | Emits `Ash.Resource.Change` behaviour module. |
| 8 | `ash.gen.preparation` | `deps/ash/lib/mix/tasks/gen/ash.gen.preparation.ex:1` | `ALIVE` | `core` | Module existence check | Emits `Ash.Resource.Preparation` behaviour module. |
| 9 | `ash.gen.validation` | `deps/ash/lib/mix/tasks/gen/ash.gen.validation.ex:1` | `ALIVE` | `core` | Module existence check | Emits `Ash.Resource.Validation` behaviour module. |
| 10 | `ash.extend` | `deps/ash/lib/mix/tasks/ash.extend.ex:1` | `PARTIAL_ALIVE` | `core` | AST inspection in Sourceror | Appends extension module (e.g. `AshPostgres.DataLayer`) to `use Ash.Resource` options. |
| 11 | `ash.codegen` | `deps/ash/lib/mix/tasks/ash.codegen.ex:1` | `PARTIAL_ALIVE` | `lifecycle` | Snapshot diffing in `priv/resource_snapshots` | Requires `--name <name>`. Rejects `--yes` due to strict validation in `ash_postgres.generate_migrations`. |
| 12 | `ash.setup` | `deps/ash/lib/mix/tasks/ash.setup.ex:1` | `ALIVE` | `lifecycle` | Ecto migration idempotency | Executes `ecto.create` and `ash_postgres.migrate`. |
| 13 | `ash.gen.custom_expression` | `deps/ash/lib/mix/tasks/gen/ash.gen.custom_expression.ex:46` | `BUILD_BROKEN` | `core` | None (compile failure) | **Upstream Bug:** Emits `args: [...]` but `Ash.CustomExpression` requires `arguments: [...]`. Typed refusal emitted. |
| 14 | `ash.attach.support_module` | N/A (Missing upstream task) | `UNSUPPORTED` | `core` | None | No upstream task exists to attach validation/change/preparation modules to resource action DSL blocks. |
| 15 | `ash.extend:policies` | `deps/ash/lib/mix/tasks/ash.extend.ex:1` | `UNKNOWN` | `core` | N/A | Not exercised in validation fixture. Maintained as `UNKNOWN` rather than admitted. |
| 16 | `ash.patch.extend` | `deps/ash/lib/mix/tasks/ash.patch.extend.ex:1` | `UNSUPPORTED` | `core` | N/A | Ad-hoc AST patching avoided in favor of clean Igniter generator composition. |
| 17 | `ash.reset` | `deps/ash/lib/mix/tasks/ash.reset.ex:1` | `UNSUPPORTED` | `lifecycle` | N/A | Destructive database drop/recreate; refused by release safety doctrine. |
| 18 | `ash.tear_down` | `deps/ash/lib/mix/tasks/ash.tear_down.ex:1` | `UNSUPPORTED` | `lifecycle` | N/A | Destructive operation; permanently refused. |
| 19 | `ash.set.domains` | `deps/ash/lib/mix/tasks/ash.set.domains.ex:1` | `UNSUPPORTED` | `base` | N/A | Superseded by automatic domain registration in `mix ash.gen.domain`. |
| 20 | `ash_postgres.gen.resources`| `deps/ash_postgres/lib/mix/tasks/ash_postgres.gen.resources.ex:1` | `UNSUPPORTED` | `core` | N/A | Batch resource generator; superseded by individual resource generation. |
| 21 | `ash_postgres.setup_vector` | `deps/ash_postgres/lib/mix/tasks/ash_postgres.setup_vector.ex:1` | `UNSUPPORTED` | `base` | N/A | Vector extension setup; out of scope for standard relational fixtures. |

---

## 3. Admitted vs. Refused Capabilities

### 3.1 Admitted Tasks (12 Tasks)
The 12 admitted tasks are composed into a single unified execution task:
`lib/mix/tasks/<app>.manufacture.ex`.
Composition occurs via `Igniter.compose_task/4`:
```elixir
igniter
|> Igniter.compose_task("ash.gen.domain", [to_string(domain_mod), "--ignore-if-exists"])
|> Igniter.compose_task("ash.gen.resource", [to_string(res_mod), "--domain", to_string(domain_mod), ...])
```
By composing in-memory, all AST modifications accumulate on a shared `Igniter.Rewrite` struct, and files are written to disk in a single coordinated atomic pass.

### 3.2 Typed Refusals (9 Tasks)
Operating doctrine strictly forbids silent omission or ad-hoc workarounds. When an upstream task cannot express the required semantics, it is assigned a typed refusal:

1. **`ash.gen.custom_expression` (`BUILD_BROKEN`)**:
   - Upstream generator line 46 emits `args: [...]`.
   - `Ash.CustomExpression.__using__/1` (`ash/lib/ash/custom_expression.ex:113-115`) raises `ArgumentError` ("You must provide arguments for the custom expression").
   - Result: Refused in pack ontology with `standing: BUILD_BROKEN` and emitted as an OCEL `capability_refused` event.

2. **`ash.attach.support_module` (`UNSUPPORTED`)**:
   - No upstream generator task attaches validation, change, or preparation modules to action blocks in a resource DSL.
   - Result: Refused in ontology; support modules remain generated as clean standalone modules.

3. **`ash.codegen --yes` (`BUILD_BROKEN`)**:
   - `mix ash.codegen` forwards argv directly to `ash_postgres.generate_migrations`.
   - `ash_postgres.generate_migrations` uses strict Igniter switch validation without declaring `yes: :boolean`.
   - Result: `--yes` is rejected as an unknown option. `ggen_igniter` uses `--name <migration_name>` instead.

---

## 4. AGENTS.md Invariant Enforcement

To prevent agents from bypassing upstream generators by writing raw Elixir modules containing `use Ash.Resource`, the repo enforces two layers of defense:

1. **PreToolUse Execution Guard (`.claude/hooks/refuse-handwritten-ash.sh`)**:
   - Intercepts tool calls on `Edit` and `Write`.
   - Rejects payloads containing `use Ash.Resource` or `domain:` + `otp_app:` headers with exit code 2.
   - Fails closed on unparseable payloads.

2. **ExUnit Falsifier (`test/ggen_igniter_agent_guard_test.exs`)**:
   - Executes 25 real-subprocess test cases feeding real JSON payloads via stdin.
   - Proves that bypass attempts (such as heredocs, newline splitting, or path traversal) are blocked.
