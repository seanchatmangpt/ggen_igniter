import Config

# ash_a2a 26.9.31 boots a strict security preflight (RFC-SA2A-007) that this
# checkout's dev receipt surface (in-memory receipt store, unkeyed outbox)
# does not satisfy. Deps compile under Mix.env(:prod), so the only non-strict
# profile available here is the explicit :legacy_compat (:dev_bypass is
# compiled out of prod builds); :strict stays the default everywhere it is
# actually reachable.
config :ash_a2a, :security_profile, :legacy_compat

# D5 (2026-10-02) STOP witness: a strict-boot attempt was made and REVERTED.
# The strict preflight itself IS satisfiable in dev/test config: every
# Boot/SecurityPreflight/boot_check violation was discharged with one
# repo-local durable root (.ggen_igniter/ash_a2a_ekv/<env>/) -- receipt
# store Ekv, Ekv authority broker, DurableFile claim store, keyed 49-byte
# outbox, cluster_size 3, durable kill-switch path. `mix run` booted
# :ash_a2a under :strict clean, and the TransitionLog concurrency test's
# four real dev `mix run` subprocesses passed (10 tests, 0 failures). The
# irreducible blocker is a DIFFERENT strict requirement, in the same
# process/env as a test the config cannot touch:
#
#   * The boot preflight requires the GLOBAL app env
#     `Application.get_env(:ash_a2a, :capability_release_mode) == :strict`
#     at :ash_a2a start (ash_a2a/lib/ash_a2a/security_profile/boot.ex:93-97,
#     131-137). :ash_a2a auto-starts in every `mix test` / `mix run` VM of
#     this checkout (witnessed: `ash_a2a_started?=true` under
#     `MIX_ENV=test mix run`).
#   * The same global env is consulted at every `use AshA2A.Agent` macro
#     expansion (ash_a2a/lib/ash_a2a/capability_release.ex:359-366 ->
#     filter_skills -> info.ex:104 raises
#     `:capability_release_closure_missing` without a frozen closure).
#     test/ggen_igniter_semantic_a2a_dispatch_test.exs:96-99 expands
#     `use AshA2A.Agent` at TEST runtime with no closure: under the boot-
#     required :strict env that compile raises and all 12 dispatch tests
#     go invalid ("12 tests, 0 failures, 12 invalid" -- witnessed). Under
#     the legacy env the same test compiles and passes.
#   * Discharging it needs a frozen `:capability_release_closure` whose
#     members carry court-receipt-backed standing bindings for the test's
#     dynamically manufactured resource (StandingBinding.verify_durable/2,
#     ash_a2a/lib/ash_a2a/standing_binding.ex:80-93 replays a real receipt);
#     that is a runtime capability-release lifecycle, not configuration --
#     and test files are outside this lane's owned set.
