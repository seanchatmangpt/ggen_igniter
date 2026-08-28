# Generating Ash Actions

How `ggen_igniter` projects RDF action definitions into Ash resource `actions do ... end` blocks, distinguishing default CRUD actions from custom actions.

---

## 1. Ontology Action Model

Actions in `test/fixtures/ash-lifecycle-pack/ontology.ttl` are instances of `alp:Action`:

```turtle
alp:Action a rdfs:Class ;
    rdfs:label "One Ash.Resource action, scoped to a single alp:Resource via alp:actionOf." .
```

### RDF Properties
| RDF Predicate | Type | Description |
|---|---|---|
| `alp:actionOf` | `alp:Resource` | The resource defining this action. |
| `alp:actionOrder` | `integer` | 1-based ordering index within the actions block. |
| `alp:actionName` | `string` | Action identifier (e.g. `"create"`, `"read"`, `"archive"`). |
| `alp:actionType` | `string` | Ash action kind (closed set: `"create"`, `"read"`, `"update"`, `"destroy"`). |

### SPARQL Gate: `gates/030_actions.rq`
```sparql
PREFIX alp: <http://seanchatmangpt.github.io/packs/ash-lifecycle-pack#>
SELECT ?resource_name ?action_order ?action_name ?action_type WHERE {
  ?act a alp:Action ; alp:actionOf ?resource ;
       alp:actionOrder ?action_order ; alp:actionName ?action_name ;
       alp:actionType ?action_type .
  ?resource alp:resourceName ?resource_name .
} ORDER BY ?resource_name ?action_order
```

---

## 2. Default CRUD vs. Custom Named Actions

In Ash, standard actions matching the type name (e.g., action `:create` of type `:create`) can be declared concisely via `defaults([:create, :read, :update, :destroy])`. Custom actions (e.g., action `:archive` of type `:update`) require an explicit block (`update :archive do ... end`).

### The Partitioning Rule
- If `action_name == action_type` -> Fold into `defaults([...])`.
- If `action_name != action_type` -> Emit explicit `<action_type> :<action_name> do ... end` block.

### Template Logic (`templates/resource.ex.eex`)
```elixir
  actions do
    default_accept(:*)

<% resource_actions =
     actions
     |> Enum.filter(fn act -> act["resource_name"] == resource_name end)
     |> Enum.sort_by(fn act -> act["action_order"] end)

   default_action_types =
     resource_actions
     |> Enum.filter(fn act -> act["action_name"] == act["action_type"] end)
     |> Enum.map(fn act -> act["action_type"] end) %>
<%= if default_action_types != [] do %>    defaults([<%= default_action_types |> Enum.map(&(":" <> &1)) |> Enum.join(", ") %>])
<% end %>
<%= for act <- resource_actions, act["action_name"] != act["action_type"] do %>    <%= act["action_type"] %> :<%= act["action_name"] %> do
    end

<% end %>  end
```

---

## 3. Generated Code Examples

### Standard CRUD Resource (`Customer`)
From `ontology.ttl`:
```turtle
alp:CustomerCreateAction a alp:Action ; alp:actionOf alp:CustomerResource ; alp:actionName "create" ; alp:actionType "create" .
alp:CustomerReadAction   a alp:Action ; alp:actionOf alp:CustomerResource ; alp:actionName "read"   ; alp:actionType "read" .
alp:CustomerUpdateAction a alp:Action ; alp:actionOf alp:CustomerResource ; alp:actionName "update" ; alp:actionType "update" .
alp:CustomerDestroyAction a alp:Action ; alp:actionOf alp:CustomerResource ; alp:actionName "destroy" ; alp:actionType "destroy" .
```

Generated Output:
```elixir
  actions do
    default_accept(:*)
    defaults([:create, :read, :update, :destroy])
  end
```

### Resource with Custom Action (`Ticket`)
From `ontology.ttl`:
```turtle
alp:TicketArchiveAction a alp:Action ;
    alp:actionOf alp:TicketResource ;
    alp:actionOrder 5 ;
    alp:actionName "archive" ;
    alp:actionType "update" .
```

Generated Output:
```elixir
  actions do
    default_accept(:*)
    defaults([:create, :read, :update, :destroy])
    update :archive do
    end
  end
```

---

## 4. Downstream Effects on Form & Generator Tooling

1. **`AshPhoenix.Form`**: When multiple actions of the same type exist (such as `:update` and `:archive`), consumers specifying forms must pass the explicit action name:
   ```elixir
   AshPhoenix.Form.for_update(ticket, :archive, domain: SupportDesk.Support)
   ```
2. **`mix ash_phoenix.gen.live` Disambiguation**: Because `Ticket` has two update actions, generators detect ambiguity and prompt or require explicit action configuration.
