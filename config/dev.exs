import Config

# ash_a2a 26.9.31 boots a strict security preflight (RFC-SA2A-007) that this
# checkout's dev receipt surface (in-memory receipt store, unkeyed outbox)
# does not satisfy. Deps compile under Mix.env(:prod), so the only non-strict
# profile available here is the explicit :legacy_compat (:dev_bypass is
# compiled out of prod builds); :strict stays the default everywhere it is
# actually reachable.
config :ash_a2a, :security_profile, :legacy_compat
