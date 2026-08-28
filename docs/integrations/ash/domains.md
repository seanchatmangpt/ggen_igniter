# Generating Ash Domains

How `ggen_igniter` projects RDF ontology triples into `Ash.Domain` modules, enforces multi-domain partitioning, and manages domain registration in application configuration.

---

## 1. Domain Ontology Model

Domains in the `ash-lifecycle-pack` are represented by `alp:Domain` individuals:

```turtle
alp:SupportDeskDomain a alp:Domain ;
    alp:domainName "Support" ;
    alp:domainModule "SupportDesk.Support" .
```

Resources reference their owning domain via `alp:resourceDomain`:
```turtle
alp:TicketResource a alp:Resource ;
    alp:resourceName "Ticket" ;
    alp:resourceModule "SupportDesk.Support.Ticket" ;
    alp:resourceDomain alp:SupportDeskDomain .
```

---

## 2. Gate Queries & Multi-Domain Partitioning

Domain generation uses two distinct SPARQL queries to avoid single-domain assumption bugs:

1. **`gates/055_domains.rq` (Driver Gate)**: Selects distinct domains to drive the `for_each: domains` template iteration.
```sparql
PREFIX alp: <http://seanchatmangpt.github.io/packs/ash-lifecycle-pack#>
SELECT DISTINCT ?domain_name ?domain_module WHERE {
  ?resource a alp:Resource ; alp:resourceDomain ?domain .
  ?domain alp:domainName ?domain_name ; alp:domainModule ?domain_module .
} ORDER BY ?domain_name
```

2. **`gates/050_domain_resources.rq` (Membership Gate)**: Retrieves the full mapping of domains to resources.
```sparql
PREFIX alp: <http://seanchatmangpt.github.io/packs/ash-lifecycle-pack#>
SELECT DISTINCT ?domain_name ?domain_module ?resource_name ?resource_module WHERE {
  ?resource a alp:Resource ; alp:resourceName ?resource_name ; alp:resourceModule ?resource_module ;
            alp:resourceDomain ?domain .
  ?domain alp:domainName ?domain_name ; alp:domainModule ?domain_module .
} ORDER BY ?domain_name ?resource_name
```

### Domain Template (`templates/domain.ex.eex`)
```elixir
---
to: "lib/support_desk/<%= String.downcase(domain_name) %>.ex"
for_each: domains
mode: file
---
<% resources_in_domain = Enum.filter(domain_resources, &(&1["domain_module"] == domain_module)) %>
defmodule <%= domain_module %> do
  @moduledoc """
  Ash.Domain registering resources belonging to <%= domain_module %>.
  """

  use Ash.Domain

  resources do
<%= for d <- resources_in_domain do %>    resource(<%= d["resource_module"] %>)
<% end %>  end
end
```

---

## 3. Ash Compile-Time Domain Verification & `config.exs`

When an Elixir module contains `use Ash.Domain`, Ash's compile-time Spark DSL verifier (`Module.ParallelChecker`) requires the domain module to be registered in the application's configuration under `config :otp_app, ash_domains: [...]`.

If a domain is not registered, compilation under `mix compile --warnings-as-errors` fails:
```text
warning: Domain SupportDesk.Support is not present in config :support_desk, ash_domains: [].
```

---

## 4. Doctor Rule: `ash_domains_rule` in `GgenIgniter.DoctorFixes`

`ggen_igniter` includes automated detection and reconciliation for missing Ash domain registrations via `mix ggen_igniter.doctor --fix`.

### Rule Implementation in [`lib/ggen_igniter/doctor_fixes.ex`](file:///Users/sac/ggen_igniter/lib/ggen_igniter/doctor_fixes.ex#L398-L480):

1. **Predicate (`check_ash_domains/1`)**:
   - Scans `lib/**/*.ex` for modules containing `use Ash.Domain`.
   - Reads the project's `mix.exs` to extract the OTP app name (`app: :my_app`).
   - Checks `config/config.exs` to verify if all discovered domains are present in `config :otp_app, ash_domains: [...]`.
   - Returns `{:ok, msg}` if all registered, `{:fixable, msg}` if missing, or `{:unrecognized, msg}` if config syntax is unparseable.

2. **Transformation (`fix_ash_domains!/1`)**:
   - If `config :otp_app, ash_domains:` is present as a literal list, merges missing domain module names in-place without altering other lines.
   - If `ash_domains:` config is absent, inserts `config :otp_app, ash_domains: [DiscoveredDomain]` right before `import_config "#{config_env()}.exs"`.

3. **Verification**:
   - Re-reads `config/config.exs` to ensure the predicate now returns `{:ok, ...}`.

### Example Doctor Fix Execution
```bash
mix ggen_igniter.doctor --fix
# [*] ash_domains_registration: registered 1 Ash domain module(s) in config/config.exs: SupportDesk.Support
```
