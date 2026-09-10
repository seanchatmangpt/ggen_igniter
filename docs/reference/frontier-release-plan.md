# Frontier Release response plans

`GgenIgniter.FrontierReleasePlan` composes a selected Frontier Release Factory opportunity into the existing `GgenIgniter.RuntimeShape` semantic IR. It is a **CONSTRUCT-time plan**, not an actuator.

## Why RuntimeShape

The source opportunity has already crossed semantic admission before it reaches ggen_igniter. `RuntimeShape` already provides the closed-field, portable, content-addressed IR required to preserve that identity across projectors. The Frontier Release plan therefore becomes another RuntimeShape projection instead of introducing a parallel project-spec format.

The generated plan carries:

- source RuntimeShape digest and subject identity;
- bounded response mode (`reuse`, `compose`, `extend`, `invent`);
- repository disposition (`reuse`, `create`);
- target repository and local project identity;
- exact pack directory selected for manufacture;
- structured executable/argv intents;
- an explicit `CONSTRUCT` authority ceiling.

## Structured intents, not shell scripts

A create-mode plan describes four ordered edges:

```text
mix igniter.new                 CONSTRUCT
mix ggen_igniter.sync           CONSTRUCT
mix compile --warnings-as-errors OBSERVE
gh repo create                  DO (broker + receipt required)
```

A reuse-mode plan omits both `mix igniter.new` and `gh repo create`; it manufactures into the admitted existing project and verifies it. This preserves DfCM's reuse-before-invent rule and avoids turning every external announcement into repository proliferation.

The module returns data only. It never calls `System.cmd/3`, `GgenIgniter.Actuate`, Igniter, Mix tasks, or `gh` itself. A runtime that later receives the `gh repo create` intent must independently admit the exact repository creation under its broker/receipt boundary.

## Example

```elixir
source =
  GgenIgniter.RuntimeShape.new!(%{
    subject_id: "opportunity:frontier-x",
    source_digest: "sha256:source",
    graph_digest: "sha256:graph",
    admission: %{"standing" => "CANDIDATE", "authority" => "NONE"}
  })

{:ok, plan} =
  GgenIgniter.FrontierReleasePlan.new(source, %{
    opportunity_id: "frontier-x",
    project_name: "frontier_x",
    project_dir: "/work/frontier_x",
    target_repository: "owner/frontier-x",
    pack_dir: "/packs/frontier-x",
    response_mode: "compose",
    repository_mode: "create",
    visibility: "public"
  })

{:ok, do_intents} = GgenIgniter.FrontierReleasePlan.do_intents(plan)
```

`do_intents` contains an exact structured `gh repo create` intent, but no repository has been created merely by evaluating this code.

## Standing and verification

Source presence establishes no runtime standing. Qualification requires the normal repository gate (`mix compile --warnings-as-errors`, `mix test`, disk reread/diff inspection, no-mock grep) and, for real end-to-end project manufacture, the existing real `mix e2e` lifecycle or a bounded consumer execution using the generated plan.

The plan is falsified if reuse mode scaffolds a replacement project, if any DO intent omits broker/receipt requirements, if map insertion order changes its content identity, or if constructing the plan executes a side effect.
