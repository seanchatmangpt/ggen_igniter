import Config

# ash_a2a (dev/test dep) capability grants: fail-closed :broker policy backed by
# the real in-memory broker; the broker process is started by the A2A tests.
config :ash_a2a, :authority_policy, :broker
config :ash_a2a, :authority_broker, AshA2A.Authority.Broker.InMemory

# ash_a2a 26.9.31 boots a strict security preflight (RFC-SA2A-007) that this
# checkout's dev/test receipt surface (in-memory receipt store, unkeyed
# outbox) does not satisfy. Deps compile under Mix.env(:prod), so the only
# non-strict profile available here is the explicit :legacy_compat
# (:dev_bypass is compiled out of prod builds); :strict stays the default
# everywhere it is actually reachable.
config :ash_a2a, :security_profile, :legacy_compat

# D5 (2026-10-02) STOP witness (same finding as config/dev.exs's block): the
# durable-store half of the :strict profile IS config-satisfiable, but the
# boot preflight's global `:capability_release_mode :strict` requirement
# (ash_a2a/lib/ash_a2a/security_profile/boot.ex:93-97, 131-137) collides with
# `test/ggen_igniter_semantic_a2a_dispatch_test.exs:96-99`'s closure-less
# test-time `use AshA2A.Agent` expansion
# (ash_a2a/lib/ash_a2a/capability_release.ex:359-366 ->
# `:capability_release_closure_missing`), which config alone cannot discharge
# -- it needs a court-receipt-backed frozen release closure for the test's
# manufactured resource. Reverted per lane law; see the D5 lane report.
