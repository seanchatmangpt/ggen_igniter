# UltraCode two-port pack (`ultracode-two-port-pack`)

v26.9.27. `priv/ggen/ultracode-two-port-pack` generates UltraCode agents whose only external
semantic ports are sJira (work) and SA2A (capability). This page describes what the pack does and
how it enforces that. It is for anyone generating an UltraCode agent from ggen_igniter, and for
reviewers checking the two-port law.

```text
forall generated UltraCode agent A:  ExternalSemanticPorts(A) = {SA2A, sJira}

WORK         = sJira   GgenIgniter.SemanticJira / GgenIgniter.SemanticA2A
CAPABILITY   = SA2A    AshA2A capability index, Dispatcher (:observe), CommandBus (:change)
CONSTRUCTION = local bounded runtime (only the generated `Local` module reaches the OS)
DO           = separately authorized; capability resolution never grants authority
```

Status: **PARTIAL_ALIVE**. The pack, the gates and the generated consumer are exercised by
`test/ggen_igniter_ultracode_two_port_test.exs`: 59 tests, 0 failures, in a local run on
2026-10-02. The 59 tests include:
- 8 firewall falsifiers;
- a 15-module bypass corpus;
- 15 graph falsifiers.

A mutation run confirms the tests are not vacuous: disabling default-deny, or one gate branch,
turns 3 tests red. The XaaS UltraCode runtime does not consume this pack yet
(see "Open edges").

## Where the law is enforced

The pack enforces the law three times over, and each check is a real refusal.

1. **Graph (before any byte is written).** `gates/000_violations.rq` is an *inverted* gate: each
   row it returns is a typed refusal. Every template raises `REFUSED_TWO_PORT_TOPOLOGY` if the gate
   returns any rows, so `mix ggen_igniter.sync` exits non-zero and writes nothing. The refusal codes
   are:
   - Port shape: `MISSING_WORK_PORT`, `MISSING_CAPABILITY_PORT`, `FOREIGN_WORK_PORT`,
     `FOREIGN_CAPABILITY_PORT`, `FOREIGN_PORT`, `FOREIGN_PORT_KEY`.
   - Allow-lists (pinned; a consumer graph can narrow them but never widen them):
     `EXTRA_PORT_PREFIX`, `EXTRA_RUNTIME_APP`, `EXTRA_SHELL_BOUNDARY`, `UNSANCTIONED_LOCAL_VERB`.
   - Edges: `FORBIDDEN_DIRECT_EDGE` (`utp:externalIntegration`).
   - Actuation: `UNMEDIATED_ACTUATION`, `ACTUATION_WITHOUT_AUTHORITY`,
     `MISSING_CAPABILITY_NAME`, `NETWORK_VERB_IN_LOCAL_PRIMITIVE`.
   - Agent shape: `MALFORMED_AGENT` (declared values are spliced into code, so their shape is
     closed), `INCOMPLETE_AGENT`, `MULTIPLE_AGENTS`, `NO_AGENT`.

   Do not score this pack with `GgenIgniter.GateVerify`'s ">= 1 row passes" rule. For this gate,
   zero rows is the pass condition.
2. **Compiled code.** The generated `<Prefix>.Firewall` reads each agent BEAM's Erlang abstract
   code through `:beam_lib`, not the source text, and classifies every remote call and remote
   function reference.
   - **Allowed:** internal calls, sanctioned port prefixes, and local runtime apps. The allowed set
     is default-deny.
   - **Refused:** forbidden modules (network, runtime code loading and eval, and process and
     message machinery), shell or port calls outside `<Prefix>.Local`, and hidden edges such as
     `mod.fun()`, `apply/3`, `spawn/2..5`, `send/2`, `:timer.apply_*` and `:erlang.load_nif/2`.
   - **Guarded modules:** a protocol implementation for an agent type
     (`String.Chars.<Prefix>.X`) is guarded like agent code. An agent-named module that is not in
     the checked set is refused.
   - **Missing debug info:** a module without debug info cannot be proven, so it is refused
     (`:no_debug_info`).
3. **Runtime types.**
   - `Capabilities.resolve/2` returns `"authority" => "NONE"`.
   - `invoke/3` of a `:change`/`:external_do` capability needs an identity admitted by
     `AshA2A.Authority.Grant`, and it runs through `AshA2A.CommandBus`, which is the BRCE route.
     The command carries an `AshA2A.SemanticSubject` whose `graph_digest` is the work order's
     `work_order_digest`.
   - HILT work-order binding (CHI-HILT), opt-in via `utp:hilt true` on the agent: the rendered
     `Capabilities` module binds every DO command before the bus sees it
     (`AshA2A.Hilt.WorkOrder.for_command!/3` -> `bind_command/2`, then
     `CommandBus.run(..., work_order: order)`). The order freezes the exact task/candidate/subject
     identities the resolution carries and carries the subject's `graph_digest` as checkpoint
     evidence, so a re-pointed graph is refused `:stale_graph_identity` at the bus and the
     `stale_*` refusal family surfaces as the typed failure it names. The pinned SA2A port
     prefix list admits `AshA2A.Hilt` for exactly this edge. The opt-in is a graph declaration,
     not ambient: a consumer that sets it must pin an ash_a2a carrying `AshA2A.Hilt` (the hex
     26.9.x line does not), so the default render stays compilable against the pinned dep.
   - Consequential actuations (`git.push`, `pr.create`, `merge.remote`, `tracker.mutate`) are
     refused with `:unauthorized` before resolution unless authority is supplied.
   - `Local.git/3` runs only the allowlisted local verbs, and refuses workspace or remote override
     flags (`-c`, `-C`, `--git-dir`, `--remote`, `--upload-pack`, ...).
   - `Capabilities.invoke/3` honours a resolution only if its digest still re-derives, its subject
     is complete, and its target is unchanged.
   - `Work.update/5` refuses a receipt that is not genuine, not bound to this work's exact subject,
     or not for `final_head` (`:receipt_not_bound`).
   - The Constructor re-reads HEAD after construction. The final head must descend from the work's
     `base_sha`, and the SA2A CommandBus receipt's `graph_digest` must equal the work's
     `work_order_digest`.

## Using the pack

The consumer graph is the pack ontology concatenated with one agent declaration. See
`test/fixtures/ultracode-two-port/agent.ttl` for an example:

```turtle
ex:Constructor a utp:ConstructorAgent ;
    utp:workPort utp:sJira ;
    utp:capabilityPort utp:SA2A ;
    utp:otpApp "my_app" ;
    utp:modulePrefix "MyApp.Agent" ;
    utp:agentName "my_app_agent" ;
    utp:libPath "lib/my_app/agent" ;
    utp:sa2aTarget "MyApp.Work.Task" .
```

Render each template once. The pack has eight templates, so the stems must be selected
explicitly:

```bash
cat priv/ggen/ultracode-two-port-pack/ontology.ttl my_agent.ttl > consumer.ttl
for t in world work capabilities local constructor firewall config architecture_test; do
  mix ggen_igniter.sync --pack ultracode-two-port-pack:$t --ontology consumer.ttl \
    --out "<consumer>/<to: of the template>" --manifest-dir <consumer>
done
```

The generated surface is `World`, `Work`, `Capabilities`, `Local`, `Constructor` and `Firewall`,
plus two more files:
- `config/ultracode_ports_<agent>.exs`, which sets
  `allowed_external_semantic_ports: [:sa2a, :sjira]`;
- `test/<app>/<agent>_architecture_test.exs`, which runs `Firewall.check_app/1` over the app's
  `.beam` files on disk.

`Constructor.run/5` is the only flow:

```text
sJira work -> bind exact subject (base_sha == local HEAD, else :stale_subject)
  -> SA2A resolve -> SA2A invoke -> local CONSTRUCT -> verify -> receipt
  -> sJira promote/apply_transition
```

Each step emits one OCEL 2.0 event.

## Typed capability failures

A failure from the capability port is one of `:no_capability`, `:ambiguous_capability`,
`:unauthorized`, `:provider_unavailable`, `:invalid_requirement`, `:invocation_refused`, or a HILT
work-order binding refusal (`:stale_task_identity`, `:stale_candidate_identity`,
`:stale_subject_identity`, `:stale_work_order_identity`, `:stale_graph_identity`,
`:stale_capability_identity`, `:authority_ceiling_exceeded`, `:consequence_unclassified`; the HILT
family only in the `utp:hilt` opt-in render). A failure
is never permission to bypass SA2A. A missing capability is a missing SA2A capability to add, not
a reason for a direct adapter.

## Residue (known limits)

- **Named module sets.** The firewall allows by port module prefix and OTP application. A new SA2A
  or sJira entry module must be added to `utp:portModulePrefix` in the ontology.
- **Allowed runtime apps.** `utp:runtimeApp` names the local runtime apps, and anything in those
  apps is allowed unless `utp:forbiddenModule` names it. The forbidden list covers the known
  network modules (`:gen_tcp`, `:inet`, `:httpc`, `:ssl`, `:socket`, `:prim_*`, `:os`, `:rpc`,
  `:erpc`, ...).
- **Tamper-evident, not tamper-proof.** The resolution digest is a SHA-256 over the resolution,
  not a MAC. A caller that recomputes it can re-shape a resolution, but a `:change` still passes
  through `AshA2A.CommandBus` admission and grants. The Constructor checks the subject that SA2A
  actually recorded, not the caller's copy.
- **Injected closures.** `construct` and `verify` are closures supplied by the caller. The
  firewall proves the agent's own modules, not the caller's code.
- **Debug info required.** A consumer build that strips debug info fails the firewall closed
  (`:no_debug_info`).
- **Single-ontology sync.** `mix ggen_igniter.sync` takes one `--ontology`, so the consumer
  concatenates the pack ontology with its agent graph.

## Open edges

- **XaaS migration.** Render the pack into XaaS and move the class-D direct edges behind the
  ports. Those edges are:
  - the `:httpc` MCP client in `Xaas.Ultracode.SemanticCrown`;
  - the GLM failover shell dispatcher;
  - the shell-out to a sibling ggen_igniter checkout;
  - the `Req` client in `capability_resolver/source/sa2a.ex`.

  The migration is blocked on XaaS's hex pin `ggen_igniter ~> 26.9.15`, which lacks
  `GgenIgniter.SemanticJira`.
- **Marketplace publication** as a reusable `ultracode-semantic-agent` pack.

## See also

- `priv/ggen/semantic-jira-pack/ontology.ttl`: `sj:capabilityId`, and gate 047's provider
  neutrality rule.
- `docs/jira/v26.9.27/_LANES.md`: the epoch law. This pack is knowledge plane plus tests, so no
  `lib/` implementation-plane file is added.
- `test/ggen_igniter_semantic_a2a_dispatch_test.exs`: the manufactured SA2A resource that the
  consumer resolves against.
