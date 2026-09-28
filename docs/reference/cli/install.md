# `mix ggen_igniter.install`

Consumer first-mile installer (Igniter task, group `:ggen_igniter`). Also reachable as
`mix igniter.install ggen_igniter` because the task name follows Igniter's
`<package>.install` convention.

## Usage

```bash
mix ggen_igniter.install [--domain Module.Name] [--otp-app name] [--yes]
mix igniter.install ggen_igniter --domain MyApp.Ash.Domain --yes
```

## What it does

Real `Igniter.Project.Deps`/`Config`/`Application` codemods against the consumer project:

1. adds `{:ash, "~> 3.0"}` to `defp deps`;
2. registers `--domain` (default `<OtpApp>.Ash.Domain`) under `config :otp_app, ash_domains: [...]`;
3. adds the domain as a supervised child (introducing a `children = [...]` binding first
   when `start/2` inlines the list).

Idempotent: a second run leaves the files unchanged. A `mix.exs` with `deps: [...]` inline
in `project/0` is refused with a typed issue and zero writes (upstream
`Igniter.Project.Deps.add_dep` crashes on that shape; see `HANDWRITTEN.md`).

## Flags

| flag | meaning |
|---|---|
| `--domain` | domain module name |
| `--otp-app` | OTP app name (default derived from `mix.exs`) |
| `--yes`, `-y` | accept all prompts |
| `--help` | task help (handled by `GgenIgniter.TaskShell`) |

## See also

- `test/ggen_igniter_install_real_files_test.exs` — real-file proofs.
- `docs/reference/cli/index.md`.
