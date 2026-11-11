# `mix ggen_igniter.security_review`

Source: `lib/mix/tasks/ggen_igniter.security_review.ex`
(`Mix.Tasks.GgenIgniter.SecurityReview`). Status: **IMPLEMENTED** — every
flag below is verbatim from the module's `@switches` list (lines 39–46) and
its own help text.

```
mix ggen_igniter.security_review [--base SHA] [--cwd DIR]
                                 [--receipt-out FILE] [--json] [--check]
```

The CLI hop of the diff-level security gate (`GgenIgniter.SecurityReview`):
reviews the added lines of the working diff through the five registered
checks (secrets, shell interpolation, path traversal, dependency change,
hook/settings change) and exits on the `GgenIgniter.TaskContract` code
table. The base is a 40-hex `--base SHA`, else the merge-base with the
default branch, else `HEAD~1`.

## Flag reference

| Flag | Type | Default | Notes |
|---|---|---|---|
| `--base SHA` | string | merge-base with main/master, else `HEAD~1` | 40-hex commit to diff against. |
| `--cwd DIR` | string | `File.cwd!()` | Repo root to review. |
| `--receipt-out FILE` | string | *(none)* | Also write the JSON envelope to FILE. |
| `--json` | boolean | `false` | Print the `TaskContract.envelope/3` shape (machine-readable). |
| `--check` | boolean | `false` | Read mode: the review runs and reports but writes no ledger/sealed copy. |
| `--help` | boolean | `false` | Help text, exit 0 (alias `-h`). |

## Exit codes

Cross-checked against `GgenIgniter.TaskContract.exit_codes/0`
(`lib/ggen_igniter/task_contract.ex`) and `docs/reference/cli/exit-codes.md`:

| Code | Name | Meaning |
|---|---|---|
| 0 | `ok` | Review ran, no open security findings (ALIVE). |
| 1 | `refusal` | Typed refusal `REFUSED:SECURITY_REVIEW_DIFF_UNAVAILABLE` — the diff could not be produced. |
| 2 | `invocation` | Invalid invocation (bad flag). |
| 5 | `security_blocked` | Review ran, open findings block landing (SECURITY_BLOCKED — distinct from `:drift`'s BLOCKED: the tree is not stale, the diff carries open security findings). |

## Example

```
mix ggen_igniter.security_review --base 9a1b2c3d4e5f60718293a4b5c6d7e8f90a1b2c3d --json --receipt-out /tmp/sec.json
```
