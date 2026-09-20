import Config

# ash_a2a (dev/test dep) capability grants: fail-closed :broker policy backed by
# the real in-memory broker; the broker process is started by the A2A tests.
config :ash_a2a, :authority_policy, :broker
config :ash_a2a, :authority_broker, AshA2A.Authority.Broker.InMemory
