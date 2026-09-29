# Pack lockfile (`mix ggen_igniter.pack.lock`)

v26.9.30. Pins packs to the sha256 of their content so a tampered or silently changed pack is
refused instead of trusted. Source: `lib/ggen_igniter/pack_lock.ex`,
`lib/mix/tasks/ggen_igniter.pack.lock.ex`.

## Usage

```bash
mix ggen_igniter.pack.lock [--path DIR] [--pack NAME...] [--lock PATH] [--check] [--json]
mix ggen_igniter.pack.fetch <spec> --lock PATH
```

- `--path DIR`: pack root, default `priv/ggen` (each subdirectory is a pack; a directory holding
  `pack.toml` or `ontology.ttl` is a single pack).
- `--pack NAME`: restrict to named packs (repeatable).
- `--lock PATH`: default `ggen_igniter.pack.lock`.
- `--check`: verify only, write nothing.

## Digest

sha256 hex over files sorted by relative path; each file contributes
`path NUL byte-length NUL content`. `.git`, `_build`, `.DS_Store` are ignored; mtimes and
permissions never enter the digest.

## Lockfile format

JSON, sorted keys, trailing newline (byte-identical on rewrite):

```json
{
  "packs": {
    "demo-pack": {
      "locked_by": "26.9.29",
      "name": "demo-pack",
      "sha256": "<64 hex>",
      "source": "priv/ggen/demo-pack",
      "version": "1.2.3"
    }
  },
  "schema_version": "1"
}
```

## Exit codes and refusals

| exit | meaning |
|---|---|
| 0 | written, or all packs match |
| 1 | `REFUSED:PACK_DIGEST_MISMATCH pack=... expected=... actual=...` or `REFUSED:PACK_LOCK_MISSING <path>` |
| 2 | invalid invocation |

## `pack.fetch --lock PATH`

The pack is fetched into a staging cache, its digest compared with any existing entry, and only
on match (or a new entry) copied into the real cache and recorded. A mismatch exits 1 and leaves
the real cache untouched.

## Library seam

`GgenIgniter.PackLock.check(pack_dir, lock_path)` returns `:ok`,
`{:error, {:pack_digest_mismatch, %{pack:, expected:, actual:}}}` or
`{:error, {:lock_missing, path}}`; `digest/1`, `read/1`, `write/2`, `put/3`, `entry/3` complete
the API.

## Receipts

`GgenIgniter.Receipt` accepts optional `pack_name` and `pack_digest` (sha256 hex); they appear in
the JSON and `priv/schema/receipt.schema.json` only when set, so existing receipt hashes are
unchanged.

## See Also

- `docs/reference/cli/lock.md` (the process mutex, unrelated to this lockfile)
- `docs/reference/cli/index.md`
