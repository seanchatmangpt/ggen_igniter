# Deterministic timing benchmark for GgenIgniter.EA.Ignition and
# GgenIgniter.EnterpriseArchitecture (RFC v26.9.26
# abb-sbb-implementation). Run: MIX_ENV=test mix run bench/ea_ignition_bench.exs
# Prints one JSON line per operation: iterations, median/p99 microseconds per op
# over 7 rounds (median of rounds, not a single sample).
alias GgenIgniter.EA.Ignition
d = &GgenIgniter.Digest.sha256/1

input = %{
  "architectureContract" => %{"iri" => "urn:ea:contract:payments", "digest" => d.("contract")},
  "abb" => %{"iri" => "urn:ea:abb:message-broker", "digest" => d.("abb")},
  "sbb" => %{
    "iri" => "urn:ea:sbb:rabbitmq",
    "digest" => d.("sbb-rabbitmq"),
    "realizes" => "urn:ea:abb:message-broker",
    "standing" => "ALIVE",
    "qualification" => %{"digest" => d.("qual-rabbitmq"), "mutable" => false}
  },
  "originAuthority" => %{"iri" => "urn:ea:authority:arb", "digest" => d.("arb")},
  "authorityCeiling" => "CONSTRUCT",
  "provenance" => %{"digest" => d.("prov")}
}

kafka =
  put_in(input, ["sbb"], %{
    input["sbb"]
    | "iri" => "urn:ea:sbb:kafka",
      "digest" => d.("sbb-kafka")
  })

{:ok, b} = Ignition.admit(input)
lock = Ignition.lock(b)
{:ok, nb, r} = Ignition.substitute(b, kafka)
refused = %{input | "authorityCeiling" => "DO"}

alias GgenIgniter.EnterpriseArchitecture, as: EA

ea_input = %{
  abb_digest: d.("abb"),
  contract_digest: d.("contract"),
  sbb_digest: d.("sbb-a"),
  qualification_digest: d.("qualification-a"),
  origin_authority: :construct,
  requested_authority: :construct,
  standing: :qualified,
  mutable: false
}

ea_repl = %{ea_input | sbb_digest: d.("sbb-b"), qualification_digest: d.("qualification-b")}
{:ok, ea_receipt} = EA.migrate(ea_input, ea_repl)

ops = [
  {"EnterpriseArchitecture.admit", fn -> EA.admit(ea_input) end},
  {"EnterpriseArchitecture.scaffold", fn -> EA.scaffold(ea_input) end},
  {"EnterpriseArchitecture.migrate", fn -> EA.migrate(ea_input, ea_repl) end},
  {"EnterpriseArchitecture.verify_receipt", fn -> EA.verify_receipt(ea_receipt) end},
  {"admit", fn -> Ignition.admit(input) end},
  {"admit_refuse_widening", fn -> Ignition.admit(refused) end},
  {"lock", fn -> Ignition.lock(b) end},
  {"verify_lock", fn -> Ignition.verify_lock(lock, b) end},
  {"substitute", fn -> Ignition.substitute(b, kafka) end},
  {"apply_migration", fn -> Ignition.apply_migration(b, r, nb) end}
]

n = String.to_integer(System.get_env("EA_BENCH_N", "20000"))

for {name, f} <- ops do
  for _ <- 1..1000, do: f.()

  rounds =
    for _ <- 1..7 do
      {us, _} = :timer.tc(fn -> for _ <- 1..n, do: f.() end)
      us / n
    end
    |> Enum.sort()

  IO.puts(
    ~s({"op":"#{name}","n":#{n},"rounds":7,"median_us":#{Float.round(Enum.at(rounds, 3), 3)},"max_round_us":#{Float.round(List.last(rounds), 3)}})
  )
end
