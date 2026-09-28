# `mix ggen_igniter.install`

Consumer first-mile installer (Igniter task, group `:ggen_igniter`). Also reachable as
`mix igniter.install ggen_igniter` because the task name follows Igniter's
`<package>.install` convention.

## Usage

```bash
mix igniter.install ggen_igniter                      # thin: formatter import only
mix igniter.install ggen_igniter --with-ash-domain --domain MyApp.Ash.Domain --yes
mix ggen_igniter.install [--with-ash-domain] [--domain Module.Name] [--otp-app name] [--yes]
```

## What it does

Default (thin, no Ash): `Igniter.Project.Formatter.import_dep(igniter, :ggen_igniter)` --
prepends `:ggen_igniter` to `.formatter.exs` `import_deps` when absent. Skipped with a notice
when `:ggen_igniter` is not in the consumer's `mix.exs` deps (`mix format` would otherwise
raise "Unknown dependency"). A generator's installer does not add the consumer's Ash app.

With `--with-ash-domain`, also real `Igniter.Project.Deps`/`Config`/`Application` codemods:

1. adds `{:ash, "~> 3.0"}` to `defp deps`;
2. registers `--domain` (default `<OtpApp>.Ash.Domain`) under `config :otp_app, ash_domains: [...]`;
3. adds the domain as a supervised child (introducing a `children = [...]` binding first
   when `start/2` inlines the list).

Idempotent: a second run leaves the files unchanged. With `--with-ash-domain`, a `mix.exs`
with `deps: [...]` inline in `project/0` is refused with a typed issue and zero writes
(upstream `Igniter.Project.Deps.add_dep` crashes on that shape; see `HANDWRITTEN.md`).

## Flags

| flag | meaning |
|---|---|
| `--with-ash-domain` | opt in to the Ash dep / domain config / supervision child wiring (default off) |
| `--domain` | domain module name (used with `--with-ash-domain`) |
| `--otp-app` | OTP app name (default derived from `mix.exs`) |
| `--yes`, `-y` | accept all prompts |
| `--help` | task help (handled by `GgenIgniter.TaskShell`) |

Breaking change: before v26.9.28 the Ash wiring ran by default; pass `--with-ash-domain` to
keep it.

## See also

- `test/ggen_igniter_install_real_files_test.exs` — real-file proofs of the Ash wiring.
- `test/ggen_igniter_install_installer_test.exs` — thin installer, formatter import, idempotence.
- `docs/reference/cli/index.md`.
