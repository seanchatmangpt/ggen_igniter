# Generating Ash Resources

How `ggen_igniter` projects RDF ontology triples into fully compliant `Ash.Resource` modules via SPARQL query gates and EEx templates.

---

## 1. Ontology-to-Resource Mapping Model

In `test/fixtures/ash-lifecycle-pack/ontology.ttl`, resources are modeled as instances of `alp:Resource`.

### RDF Vocabulary Mapping
| RDF Predicate | Ash DSL Target | Example | Notes |
|---|---|---|---|
| `alp:resourceName` | Module naming / File path | `"Ticket"` | Lowercased for file naming (`ticket.ex`). |
| `alp:resourceModule` | `defmodule` identifier | `"SupportDesk.Support.Ticket"` | Full Elixir module namespace. |
| `alp:dataLayer` | `use Ash.Resource, data_layer: ...` | `"Ash.DataLayer.Ets"` | In fixtures, ETS is used for database-less hermetic testing. |
| `alp:primaryKeyName` | Primary key identifier | `"id"` | Passed to primary key macros. |
| `alp:primaryKeyType` | Primary key macro | `"uuid"` vs `"integer"` | Selects `uuid_primary_key/1` or `integer_primary_key/1`. |
| `alp:resourceDomain` | `use Ash.Resource, domain: ...` | `alp:SupportDeskDomain` | Resolves domain module association. |

### SPARQL Gate: `gates/010_resource.rq`
```sparql
PREFIX alp: <http://seanchatmangpt.github.io/packs/ash-lifecycle-pack#>
SELECT DISTINCT ?resource_name ?resource_module ?data_layer ?primary_key_name ?primary_key_type ?domain_module WHERE {
  ?resource a alp:Resource ; alp:resourceName ?resource_name ; alp:resourceModule ?resource_module ;
            alp:dataLayer ?data_layer ; alp:primaryKeyName ?primary_key_name ;
            alp:primaryKeyType ?primary_key_type ; alp:resourceDomain ?domain .
  ?domain alp:domainModule ?domain_module .
} ORDER BY ?resource_name
```

---

## 2. Generating Attributes & Types

Attributes are modeled as `alp:Attribute` individuals linked to a resource via `alp:attributeOf`.

### SPARQL Gate: `gates/020_attributes.rq`
```sparql
PREFIX alp: <http://seanchatmangpt.github.io/packs/ash-lifecycle-pack#>
SELECT ?resource_name ?attribute_order ?attribute_name ?attribute_type ?attribute_allow_nil ?attribute_default WHERE {
  ?attr a alp:Attribute ; alp:attributeOf ?resource ;
        alp:attributeOrder ?attribute_order ; alp:attributeName ?attribute_name ;
        alp:attributeType ?attribute_type ; alp:attributeAllowNil ?attribute_allow_nil .
  ?resource alp:resourceName ?resource_name .
  OPTIONAL { ?attr alp:attributeDefault ?attribute_default }
} ORDER BY ?resource_name ?attribute_order
```

### Template Logic (`templates/resource.ex.eex`)
```elixir
  attributes do
<%= if primary_key_type == "uuid" do %>    uuid_primary_key(:<%= primary_key_name %>)
<% else %>    integer_primary_key(:<%= primary_key_name %>)
<% end %>
<% resource_attributes =
     attributes
     |> Enum.filter(fn a -> a["resource_name"] == resource_name end)
     |> Enum.sort_by(fn a -> a["attribute_order"] end) %>
<%= for a <- resource_attributes do %>    attribute :<%= a["attribute_name"] %>, :<%= a["attribute_type"] %> do
      allow_nil?(<%= a["attribute_allow_nil"] %>)
      public?(true)
<%= if a["attribute_default"] not in [nil, ""] do %>      default(<%= a["attribute_default"] %>)
<% end %>    end

<% end %>  end
```

### Generated Elixir Output
```elixir
  attributes do
    uuid_primary_key(:id)
    attribute :subject, :string do
      allow_nil?(false)
      public?(true)
    end

    attribute :status, :atom do
      allow_nil?(false)
      public?(true)
      default(:open)
    end

    attribute :assignee, :string do
      allow_nil?(true)
      public?(true)
    end
  end
```

---

## 3. Relationships: `belongs_to` vs. `has_many`

In RDF, relationships connect two resources (`alp:relationshipSource` and `alp:relationshipTarget`).

### Critical Invariant: Foreign Key Placement
A critical bug caught during E2E verification (`lifecycle_test.ex:204-220`) established the following rule:
- For `belongs_to`, the foreign key lives on the **source** resource -> emit `source_attribute(:<foreign_key>)` and `attribute_writable?(true)`.
- For `has_many`, the foreign key lives on the **destination** resource -> emit `destination_attribute(:<foreign_key>)`.

### Template Implementation (`templates/resource.ex.eex`)
```elixir
  relationships do
<%= for r <- relationships, r["source_resource_name"] == resource_name do %>    <%= r["relationship_kind"] %> :<%= r["relationship_name"] %>, <%= r["target_resource_module"] %> do
<%= if r["relationship_kind"] == "belongs_to" do %>      attribute_writable?(true)
      source_attribute(:<%= r["foreign_key"] %>)
<% else %>      destination_attribute(:<%= r["foreign_key"] %>)
<% end %>    end

<% end %>  end
```

---

## 4. Multi-File Generation via `for_each`

`templates/resource.ex.eex` uses the frontmatter header:
```yaml
---
to: "lib/support_desk/support/<%= String.downcase(resource_name) %>.ex"
for_each: resource
mode: file
---
```
When `mix ggen_igniter.sync` runs, it evaluates the `resource` gate query and iterates over every distinct resource, outputting an independent file for each (e.g. `lib/support_desk/support/ticket.ex` and `lib/support_desk/support/customer.ex`).

---

## 5. Destructive Evolution and Stale Artifacts

When an attribute or resource is renamed or deleted in the ontology:
1. **Attribute Rename (`ontology_v3_rename.ttl`)**: In `mode: file`, the entire resource module is re-rendered. The old attribute (`assignee`) disappears and the new attribute (`assigned_to`) is emitted.
2. **Resource Rename/Removal (`ontology_v9` / `ontology_v10`)**: 
   - Under default `--on-stale refuse`, the system refuses if unreferenced artifacts are detected in the manifest.
   - Under `--on-stale prune`, `GgenIgniter.Manifest.prune!/1` removes the orphaned `.ex` file from disk.
