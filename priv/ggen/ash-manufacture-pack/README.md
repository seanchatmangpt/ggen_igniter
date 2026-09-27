# ash-manufacture-pack

This is the **single shipped Ash manufacture profile** for `ggen_igniter`.

```text
canonical application / marketplace semantics
  -> ash-manufacture-pack
  -> ggen_igniter
  -> Igniter.compose_task/4
  -> real upstream ash.gen.* / ash_postgres.* generators
  -> generated Ash projection
```

Legacy `ash-*` directories in `ggen-marketplace` are not independent selection
authorities. Marketplace selection goes through `marketplace.active.toml` and
`ggen-platform-pack`; this pack is the Ash-specific construction profile after that
semantic selection.

## Why this is shipped

The qualified implementation previously lived only at
`test/fixtures/ash_manufacture_pack`. That made the strongest-proven Ash manufacturing
path a test fixture while consumers could discover historical marketplace Ash pack names.
This promotion gives consumers one executable Ash choice without inventing another
semantic authority.

The fixture remains qualification evidence. `priv/ggen/ash-manufacture-pack` is the
normal `--pack` consumption surface.

## Contract

- The ontology stores semantic facts and a version-scoped generator capability envelope.
- Thirteen SPARQL gates derive generator arguments; CLI strings are not semantic facts.
- `templates/manufacture.ex.eex` renders one composed `Igniter.Mix.Task`.
- That task calls upstream generators; it does not render Ash resource/domain source.
- Unadmitted generator capabilities become typed refusals, never silent handwritten fallback.
- Manufacture is split into `base` then `core` because the real Ash/Igniter contracts
  require the base-resource configuration to be loaded by a later Mix invocation.
- `verify/` carries the bound/cardinality falsifiers from the qualified fixture.

## Use

The included graph is the qualified BookLibrary worked subject. A real application should
supply its admitted application graph while reusing this pack's gates and manufacture
template:

```bash
mix ggen_igniter.sync --pack ash-manufacture-pack --dry-run

mix ggen_igniter.sync \
  --pack ash-manufacture-pack \
  --ontology path/to/application.ttl
```

Then run the manufactured task in the required phases:

```bash
mix <app>.manufacture --phase base --yes
mix <app>.manufacture --phase core --yes
mix <app>.manufacture --phase base --check
mix <app>.manufacture --phase core --check
```

The historical fixture under `test/fixtures/ash_manufacture_pack` is evidence, not a
second `--pack` discovery surface.
