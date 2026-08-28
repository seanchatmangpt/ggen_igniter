# `GgenIgniter.Controller`

**Status: PARTIAL_ALIVE.** Real, tested, and opt-in — a bounded
proof-of-concept slice, not a general workflow engine. Source:
`lib/ggen_igniter/controller.ex`; tests: `test/ggen_igniter_controller_test.exs`.

## What it is

A persistent `GenServer` that holds live reconciliation state **in its own
process** across multiple `reconcile/2` calls. Contrast with the CLI
(`mix ggen_igniter.sync`): every CLI invocation is a fresh OS process with
zero in-memory continuity — "what did the last run do" can only be answered
by re-reading disk. The Controller can answer that question (for keys it has
handled) without touching disk at all, because it never left memory between
calls.

It adds **no new reconciliation logic of its own**. It wraps one of the two
real pipeline implementations (see `docs/operations/runtime.md`'s "Which
reconciliation pipeline actually runs") and adds only in-process
bookkeeping around that one shared call.

## State shape

```elixir
%{
  last_reconciliations: %{
    pack_key => %{
      ontology_path: String.t(),
      manifest: %{out_path :: String.t() => outcome :: atom()},
      reconciliation_count: pos_integer(),
      last_run_at: DateTime.t(),
      receipt: map()
    }
  }
}
```

`reconciliation_count` is real, process-only knowledge: it is **not**
recoverable by reading the output file alone. `Actuate.write_file!/3`'s
idempotency guard means the file's content is byte-identical after
reconciliation #1 and reconciliation #2 once nothing has changed — that is
the whole point of the guard. Yet the Controller can still answer "how many
times has this key actually been reconciled, in this process" — a concrete,
testable economic claim over the CLI's stateless model.

## Public API

```elixir
GgenIgniter.Controller.start_link(opts \\ [])
# opts are plain GenServer.start_link/3 options. Pass name: GgenIgniter.Controller
# to start the singleton the application's supervision tree expects; a test
# omits :name to get an independent, unnamed instance addressed by its pid.

GgenIgniter.Controller.reconcile(server, pack_key, reconcile_opts)
# :infinity timeout. reconcile_opts is the same option shape mix ggen_igniter.sync
# accepts, within GgenIgniter.Reconcile.run/1's bounded scope: :ontology, :query,
# :template, :pack, :pack_dir, :engine, :mode, :out, :unless_exists, :skip_if, :dry_run.
# Returns {:ok, record} on success, {:error, reason} on a real pipeline failure.

GgenIgniter.Controller.status(server, pack_key)
# {:ok, record} or :never_reconciled. Pure in-process read; never touches disk.
```

## Wiring: opt-in only

Started as a child of `GgenIgniter.Application`'s supervision tree **only
when** `Application.get_env(:ggen_igniter, :start_controller, false)` is
`true` — a consuming application sets `config :ggen_igniter,
start_controller: true` explicitly. The default is `false`. A library must
never impose a persistent process on every consumer by default; with the
default left alone, a consumer that only wants the CLI sees zero behavior
change from this module's existence. In a test (or any other caller that
wants its own instance), call `start_link/1` directly instead of relying on
the application's supervision tree.

## Fault isolation — a real, tested guarantee

A real failure inside the underlying pipeline call (bad ontology path,
missing template, engine error, ...) is caught in `handle_call/3` and turned
into a clean `{:error, reason}` reply. It does **not** crash the GenServer,
and it does **not** touch any other `pack_key`'s already-stored good record.
This is the one place the module catches an exception
(`run_pipeline/1`'s `rescue`/`catch`); every other code path in this
GenServer (state bookkeeping) is left to crash loudly on purpose if it is
ever actually buggy.

## Which pipeline it dispatches to

`run_pipeline/1` branches on `Application.get_env(:ggen_igniter,
:use_reactor, false)`:

- **`false` (default)** — calls `GgenIgniter.Reconcile.run/1` directly.
  Behavior here is byte-for-byte unchanged from before the Reactor pipeline
  existed.
- **`true`** — calls `GgenIgniter.Reactors.ReconcileReactor.run/1` (that
  module's own recommended entry point, which guarantees a persisted
  receipt on every path — see `docs/operations/failure-recovery.md`) and
  reshapes the resulting `%GgenIgniter.Receipt{}` into the same result shape
  `Reconcile.run/1` returns, via `receipt_to_legacy_result/2`, using the
  receipt's own best-effort single-target compatibility fields in
  `receipt.metadata`. This reshaping is real for any run with exactly one
  target — the only shape `reconcile_opts` arrives in through the
  Controller's public API, which has no `:targets` concept of its own (the
  Reactor's multi-target `:targets` list is a Reactor-only capability today,
  not reachable through the Controller).

## Explicit scope boundary (do not extend past this without a new design pass)

Per the module's own moduledoc: this is a bounded, real proof-of-concept
slice. It explicitly does **not** attempt:

- Reactor integration beyond the opt-in dispatch above (the Controller
  itself is not built on Reactor; it calls into a Reactor pipeline as one
  branch).
- Distributed/multi-node topology.
- Crash-supervision policy design for the Controller process itself — this
  module is about fault **isolation** between keys within one already-alive
  GenServer, a different concern from a Supervisor's restart strategy for
  the GenServer process, which this module does not attempt to design.

These are legitimate future directions, explicitly out of scope for what
exists today — see `docs/contributing/architecture-rules.md`'s "GenServer
(Controller) does not become a workflow engine" rule for why this boundary
is load-bearing, not incidental.

## See Also

- `docs/operations/runtime.md` — where the Controller fits in the two-pipeline, two-process-model picture
- `docs/operations/failure-recovery.md` — receipts and the four standings, produced only on the Reactor path
- `docs/contributing/architecture-rules.md` — the ownership rule this module's scope boundary enforces
- `test/ggen_igniter_controller_test.exs` — the real, passing test suite this behavior is verified against
