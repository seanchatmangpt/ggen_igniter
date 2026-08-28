# Phoenix LiveView Integration

How `ggen_igniter`-manufactured Ash resources connect to Phoenix LiveView, how `ash_phoenix.gen.live` scaffolds UI components, and how UI code behaves across ontology evolution.

---

## 1. Generating LiveViews with `ash_phoenix.gen.live`

Once `ggen_igniter` has generated the Ash domain and resource modules, consuming applications can generate complete CRUD LiveViews using `ash_phoenix`:

```bash
mix ash_phoenix.gen.live \
  --domain SupportDesk.Support \
  --resource SupportDesk.Support.Ticket \
  --resource-plural tickets \
  --yes
```

### Generated Artifacts
`ash_phoenix.gen.live` creates:
- `lib/support_desk_web/live/ticket_live/index.ex` and `index.html.heex`
- `lib/support_desk_web/live/ticket_live/form.ex` and `form.html.heex`
- `lib/support_desk_web/live/ticket_live/show.ex` and `show.html.heex`

---

## 2. Interactive Prompts & Action Disambiguation

During CLI execution, `ash_phoenix.gen.live` may encounter ambiguities:

1. **Multi-Tenancy Prompts**: If multi-tenancy is not explicitly configured, the generator prompts the user.
2. **Ambiguous Actions**: If a resource defines multiple actions of the same type (e.g. `Ticket` has default `:update` and custom `:archive`), the generator must resolve which action to use for form submissions.

In non-interactive environments (such as CI or `test/e2e/lifecycle_test.ex:316-330`), deterministic stdin input (`"n\n"`) ensures prompts resolve predictably (e.g. resolving ambiguous update actions without blocking).

---

## 3. Router Integration

`ash_phoenix.gen.live` prints route instructions as an Igniter notice. The consumer routes are wired in `lib/support_desk_web/router.ex`:

```elixir
scope "/", SupportDeskWeb do
  pipe_through :browser

  live "/tickets", TicketLive.Index, :index
  live "/tickets/new", TicketLive.Form, :new
  live "/tickets/:id", TicketLive.Show, :show
end
```

---

## 4. UI Code Across Ontology Evolution

A fundamental aspect of `ggen_igniter` is handling breaking changes across ontology evolution:

### Breaking Attribute Rename Example (Stage 7)
1. **Initial State (Stage 6)**:
   - Ontology defines `alp:TicketAssigneeAttribute` with name `"assignee"`.
   - `ash_phoenix.gen.live` generates LiveView templates referencing `ticket.assignee` and `@ticket.assignee`.
2. **Ontology Delta (`ontology_v3_rename.ttl`)**:
   - `alp:attributeName` changes from `"assignee"` to `"assigned_to"`.
3. **Re-sync (`mix ggen_igniter.sync`)**:
   - `ticket.ex` is regenerated: `attribute :assigned_to, :string` is emitted; `attribute :assignee` is removed.
4. **Compile-Time Signal**:
   - `ggen_igniter` does not blindly rewrite downstream user-space UI code.
   - On the next `mix compile --warnings-as-errors`, the compiler halts with an error on the stale field reference:
     ```text
     == Compilation error in file lib/support_desk_web/live/ticket_live/index.ex ==
     ** (KeyError) key :assignee not found in: %SupportDesk.Support.Ticket{...}
     ```
   - This provides an immediate, compile-time fail-safe indicating that UI templates require migration to match the updated domain model.
