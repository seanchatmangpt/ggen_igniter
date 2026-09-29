# Pack lockfile (`mix ggen_igniter.pack.lock`)

v26.9.30. Pins packs to the sha256 of their content so a tampered or silently changed pack is
refused instead of trusted. Source: `lib/ggen_igniter/pack_lock.ex`,
`lib/mix/tasks/ggen_igniter.pack.lock.ex`.

## Usage

```bash
mix ggen_igniter.pack.lock [--path DIR] [--pack NAME...] [--lock PATH] [--check] [--force-regenerate] [--json]
mix ggen_igniter.pack.fetch <spec> --lock PATH [--force-regenerate]
```

- `--path DIR`: pack root, default `priv/ggen` (each subdirectory is a pack; a directory holding
  `pack.toml` or `ontology.ttl` is a single pack).
- `--pack NAME`: restrict to named packs (repeatable).
- `--lock PATH`: default `ggen_igniter.pack.lock`.
- `--check`: verify only, write nothing.
- `--force-regenerate`: overwrite an existing lockfile that is not a valid lock. Without it an
  invalid lockfile is refused (`REFUSED:PACK_LOCK_INVALID`, exit 1) in every path, never silently
  replaced.

## Digest

sha256 hex over files sorted by relative path; each file contributes
`tag path NUL byte-length NUL content`, tag `F` (regular file) or `L` (symlink), so a symlink and
a regular file can never collide. `.git`, `_build`, `.DS_Store` are ignored; mtimes and
permissions never enter the digest.

Symlinks are followed the way the pack loaders follow them. An in-pack symlink to a regular file
hashes the RESOLVED content. A symlink resolving outside the pack root, any directory symlink
(including a symlinked `templates/`), a symlink loop and a dangling link are refused
`REFUSED:PACK_SYMLINK_ESCAPE <detail>`; an unreadable file is `REFUSED:PACK_FILE_UNREADABLE
<detail>`. Digests computed before v26.9.30-F3 (no tag) do not match; re-lock.

## Lockfile writes

Writes are atomic (temp file in the same directory, then rename) so a concurrent reader never sees
partial JSON, and read-modify-write (`PackLock.update/3`, used by `pack.lock` and
`pack.fetch --lock`) is serialized across OS processes by an atomic `mkdir` of `<lock>.lockdir`
(`:global.trans` would not cover two `mix` invocations). Stale lock dirs (>120s) are reclaimed.

## `--lock` scope limitation (sync)

`mix ggen_igniter.sync --lock` verifies only the resolved pack directory. Explicit
`--ontology`, `--query` or `--template` paths outside that directory are not covered by the
digest. Suggested fix (sync.ex): refuse `--lock` combined with an explicit input path that does
not resolve inside the locked pack directory.

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
| 1 | `REFUSED:PACK_DIGEST_MISMATCH pack=... expected=... actual=...`, `PACK_LOCK_MISSING <path>`, `PACK_LOCK_INVALID <path>`, `PACK_SYMLINK_ESCAPE <detail>`, `PACK_FILE_UNREADABLE <detail>` |
| 2 | invalid invocation |

## `pack.fetch --lock PATH`

The pack is fetched into a staging cache, its digest compared with any existing entry, and only
on match (or a new entry) copied into the real cache and recorded. A mismatch exits 1 and leaves
the real cache untouched. The staging directory is always removed.

## Library seam

`GgenIgniter.PackLock.check(pack_dir, lock_path)` returns `:ok`,
`{:error, {:pack_digest_mismatch, %{pack:, expected:, actual:}}}` or
`{:error, {:lock_missing, path}}`, `{:error, {:lock_invalid, path}}`,
`{:error, {:pack_symlink_escape, detail}}` or `{:error, {:pack_file_unreadable, detail}}`;
`digest/1` (raises `PackLock.Refusal`), `digest_checked/1`, `update/3`, `with_staging/1`, `read/1`, `write/2`, `put/3`, `entry/3` complete
the API.

## Receipts

`GgenIgniter.Receipt` accepts optional `pack_name` and `pack_digest` (sha256 hex); they appear in
the JSON and `priv/schema/receipt.schema.json` only when set, so existing receipt hashes are
unchanged.

## See Also

- `docs/reference/cli/lock.md` (the process mutex, unrelated to this lockfile)
- `docs/reference/cli/index.md`
