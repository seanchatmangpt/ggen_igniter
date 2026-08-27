defmodule GgenIgniter.DestructiveChangeAgent3Test do
  @moduledoc """
  Agent 3 (Destructive Change / Consequence Closure) -- proves complete
  reconciliation (or an honest, typed refusal before any partial actuation)
  for 9 destructive ontology-evolution shapes against the ash-lifecycle-pack
  fixture, run directly via real `mix ggen_igniter.sync` subprocesses against
  this repo itself (`cd: File.cwd!()`) -- NOT the full `mix e2e` Ash+Phoenix
  scaffold (Agent 2 owns that slower path). This tests the
  ontology/template/query-diff mechanics directly.

  Each case renders the SAME `test/fixtures/ash-lifecycle-pack/templates/
  resource.ex.eex` (`for_each: resource`) and/or `templates/domain.ex.eex`
  against a `--pack-dir test/fixtures/ash-lifecycle-pack` real sync run, with
  `--out` explicitly overridden to a fresh `System.tmp_dir!()` subdirectory
  per test (never `lib/` of this repo, never the scaffolded app Agent 2
  owns) -- `mode: file` for_each templates fully regenerate their output
  file from scratch every run (no AST patching), so "0 stale references"
  after a resync is a real, meaningful claim about the CURRENT render, not
  an artifact of incremental patching.

  Convention: each case first syncs the BASE `ontology.ttl` (or `ontology_v2_
  add_attribute.ttl` for the rename-attribute case, matching the real e2e's
  Stage 2 baseline) into a fresh tmp dir, confirms the retiring identifier is
  really present in that baseline output, THEN re-syncs the destructive
  variant into the SAME tmp dir and asserts on the regenerated file's real
  content -- a genuine before/after delta, not a single-shot render that
  merely never mentions the old name.

  `--engine sparql` is pinned throughout (matches `lifecycle_test.ex`'s own
  documented reasoning: oxigraph's raw N-Triples-shaped term strings are not
  what this pack's templates/assertions were authored against).
  """
  use ExUnit.Case, async: false

  @moduletag :integration

  @pack_dir "test/fixtures/ash-lifecycle-pack"
  @resource_template Path.join(@pack_dir, "templates/resource.ex.eex")
  @domain_template Path.join(@pack_dir, "templates/domain.ex.eex")

  defp tmp_dir!(tag) do
    dir =
      Path.join(
        System.tmp_dir!(),
        "ggen_igniter_agent3_#{tag}_#{System.unique_integer([:positive])}"
      )

    File.mkdir_p!(dir)
    on_exit(fn -> File.rm_rf!(dir) end)
    dir
  end

  # Runs `mix ggen_igniter.sync` as a real subprocess against THIS repo
  # (cd: File.cwd!()) using --pack-dir (so gates/*.rq are auto-discovered),
  # rendering the resource template with --for-each resource so each
  # (Ticket/Customer/whatever survives) row writes its own file under
  # `out_dir`, path derived from the row's own resource_name -- never a
  # fixed relative "lib/..." path, so nothing ever touches this repo's own
  # lib/ tree. `--manifest-dir out_dir` keeps the reconciliation manifest
  # (`GgenIgniter.Manifest`) isolated to the SAME per-test tmp dir as every
  # generated output file -- never this repo's own `.ggen_igniter/`.
  # `extra_args` lets a case pass `--on-stale prune`/`preserve` for a sync
  # whose stale-output set is expected to be non-empty (see cases 7/8 below);
  # every other case's stale set is always empty (no row's own output PATH
  # ever changes for an attribute/action/relationship/domain-association
  # rename or removal -- only a RESOURCE rename/removal changes which path a
  # row resolves to), so the default `--on-stale refuse` never fires for them.
  defp sync_resources!(ontology_path, out_dir, extra_args \\ []) do
    out_template = Path.join(out_dir, "<%= String.downcase(resource_name) %>.ex")

    args =
      [
        "ggen_igniter.sync",
        "--engine",
        "sparql",
        "--pack-dir",
        @pack_dir,
        "--ontology",
        ontology_path,
        "--template",
        @resource_template,
        "--for-each",
        "resource",
        "--out",
        out_template,
        "--manifest-dir",
        out_dir
      ] ++ extra_args

    {output, exit_code} = System.cmd("mix", args, cd: File.cwd!(), stderr_to_stdout: true)
    {output, exit_code}
  end

  defp sync_domain!(ontology_path, out_path) do
    args = [
      "ggen_igniter.sync",
      "--engine",
      "sparql",
      "--pack-dir",
      @pack_dir,
      "--ontology",
      ontology_path,
      "--template",
      @domain_template,
      "--out",
      out_path,
      "--manifest-dir",
      Path.dirname(out_path)
    ]

    {output, exit_code} = System.cmd("mix", args, cd: File.cwd!(), stderr_to_stdout: true)
    {output, exit_code}
  end

  # -- 1. Rename attribute (already partially covered by lifecycle_test.ex's
  #    Stage 7 -- verified here directly, independent of the full e2e
  #    scaffold): ontology_v2_add_attribute.ttl (assignee present) ->
  #    ontology_v3_rename.ttl (assignee -> assigned_to on the SAME
  #    alp:TicketAssigneeAttribute IRI). --------------------------------------
  test "rename attribute: assignee -> assigned_to reconciles with 0 stale references" do
    out_dir = tmp_dir!("rename_attribute")
    ticket_path = Path.join(out_dir, "ticket.ex")

    {before_output, 0} =
      sync_resources!(Path.join(@pack_dir, "ontology_v2_add_attribute.ttl"), out_dir)

    assert before_output =~ "wrote"
    before_content = File.read!(ticket_path)
    assert before_content =~ "attribute :assignee, :string do"
    assert Code.string_to_quoted!(before_content)

    {after_output, 0} = sync_resources!(Path.join(@pack_dir, "ontology_v3_rename.ttl"), out_dir)
    assert after_output =~ "wrote"

    after_content = File.read!(ticket_path)
    assert Code.string_to_quoted!(after_content)

    refute after_content =~ "assignee"
    assert after_content =~ "attribute :assigned_to, :string do"
    # Everything else survives the rename untouched.
    assert after_content =~ "attribute :priority, :atom do"
    assert after_content =~ "attribute :subject, :string do"
    assert after_content =~ "update :archive do"
  end

  # -- 2. Remove attribute: alp:TicketAssigneeAttribute deleted entirely. ----
  test "remove attribute: assignee reconciles with 0 stale references" do
    out_dir = tmp_dir!("remove_attribute")
    ticket_path = Path.join(out_dir, "ticket.ex")

    {_before_output, 0} = sync_resources!(Path.join(@pack_dir, "ontology.ttl"), out_dir)
    before_content = File.read!(ticket_path)
    assert before_content =~ "attribute :assignee, :string do"

    {after_output, 0} =
      sync_resources!(Path.join(@pack_dir, "ontology_v4_remove_attribute.ttl"), out_dir)

    assert after_output =~ "wrote"
    after_content = File.read!(ticket_path)
    assert Code.string_to_quoted!(after_content)

    refute after_content =~ "assignee"
    # Untouched siblings survive.
    assert after_content =~ "attribute :subject, :string do"
    assert after_content =~ "attribute :status, :atom do"
  end

  # -- 3. Rename action: :archive -> :close (same alp:TicketArchiveAction IRI,
  #    still an :update-type action). ----------------------------------------
  test "rename action: archive -> close reconciles with 0 stale references" do
    out_dir = tmp_dir!("rename_action")
    ticket_path = Path.join(out_dir, "ticket.ex")

    {_before_output, 0} = sync_resources!(Path.join(@pack_dir, "ontology.ttl"), out_dir)
    before_content = File.read!(ticket_path)
    assert before_content =~ "update :archive do"

    {after_output, 0} =
      sync_resources!(Path.join(@pack_dir, "ontology_v5_rename_action.ttl"), out_dir)

    assert after_output =~ "wrote"
    after_content = File.read!(ticket_path)
    assert Code.string_to_quoted!(after_content)

    refute after_content =~ "archive"
    assert after_content =~ "update :close do"
  end

  # -- 4. Remove action: alp:TicketArchiveAction deleted entirely. ----------
  test "remove action: archive reconciles with 0 stale references" do
    out_dir = tmp_dir!("remove_action")
    ticket_path = Path.join(out_dir, "ticket.ex")

    {_before_output, 0} = sync_resources!(Path.join(@pack_dir, "ontology.ttl"), out_dir)
    before_content = File.read!(ticket_path)
    assert before_content =~ "update :archive do"

    {after_output, 0} =
      sync_resources!(Path.join(@pack_dir, "ontology_v6_remove_action.ttl"), out_dir)

    assert after_output =~ "wrote"
    after_content = File.read!(ticket_path)
    assert Code.string_to_quoted!(after_content)

    refute after_content =~ "archive"
    # Default CRUD actions (folded into defaults([...])) survive untouched.
    assert after_content =~ "defaults([:create, :read, :update, :destroy])"
  end

  # -- 5. Rename relationship: belongs_to :customer -> :client (same
  #    alp:TicketBelongsToCustomer IRI). -------------------------------------
  test "rename relationship: customer -> client reconciles with 0 stale references" do
    out_dir = tmp_dir!("rename_relationship")
    ticket_path = Path.join(out_dir, "ticket.ex")

    {_before_output, 0} = sync_resources!(Path.join(@pack_dir, "ontology.ttl"), out_dir)
    before_content = File.read!(ticket_path)
    assert before_content =~ "belongs_to :customer, SupportDesk.Support.Customer do"

    {after_output, 0} =
      sync_resources!(Path.join(@pack_dir, "ontology_v7_rename_relationship.ttl"), out_dir)

    assert after_output =~ "wrote"
    after_content = File.read!(ticket_path)
    assert Code.string_to_quoted!(after_content)

    refute after_content =~ "belongs_to :customer"
    assert after_content =~ "belongs_to :client, SupportDesk.Support.Customer do"
    assert after_content =~ "source_attribute(:customer_id)"
  end

  # -- 6. Remove relationship: alp:TicketBelongsToCustomer deleted entirely. -
  test "remove relationship: belongs_to customer reconciles with 0 stale references" do
    out_dir = tmp_dir!("remove_relationship")
    ticket_path = Path.join(out_dir, "ticket.ex")

    {_before_output, 0} = sync_resources!(Path.join(@pack_dir, "ontology.ttl"), out_dir)
    before_content = File.read!(ticket_path)
    assert before_content =~ "belongs_to :customer, SupportDesk.Support.Customer do"

    {after_output, 0} =
      sync_resources!(Path.join(@pack_dir, "ontology_v8_remove_relationship.ttl"), out_dir)

    assert after_output =~ "wrote"
    after_content = File.read!(ticket_path)
    assert Code.string_to_quoted!(after_content)

    refute after_content =~ "belongs_to"
    refute after_content =~ "customer"
    # Ticket's own attributes/actions survive untouched.
    assert after_content =~ "attribute :subject, :string do"
    assert after_content =~ "update :archive do"
  end

  # -- 7. Rename resource: alp:TicketResource "Ticket" -> "Case" (SAME IRI).
  #    FIXED (was a REAL GAP): `mode: file` for_each used to have no manifest
  #    of previously-written output paths, so a resource rename produced a
  #    NEW file (out_dir/case.ex) while the OLD file (out_dir/ticket.ex) was
  #    never deleted -- a real, reproduced stale orphan. `GgenIgniter.Manifest`
  #    (wired into `Mix.Tasks.GgenIgniter.Sync`'s `igniter/1` this session)
  #    now records every prior run's real output paths keyed by
  #    (template, --out) and computes `stale = old_paths - new_paths` before
  #    writing anything new; `--on-stale prune` closes this gap for real:
  #    the stale `ticket.ex` is really deleted and the deletion is reported.
  #    (The DEFAULT `--on-stale refuse` is covered separately, directly
  #    against this same fixture, by
  #    `test/ggen_igniter_reconciliation_manifest_test.exs`.) --------------
  test "rename resource: Ticket -> Case reconciles with 0 stale references (--on-stale prune closes the old gap)" do
    out_dir = tmp_dir!("rename_resource")
    ticket_path = Path.join(out_dir, "ticket.ex")
    case_path = Path.join(out_dir, "case.ex")

    {_before_output, 0} = sync_resources!(Path.join(@pack_dir, "ontology.ttl"), out_dir)
    assert File.exists?(ticket_path)
    before_content = File.read!(ticket_path)
    assert before_content =~ "defmodule SupportDesk.Support.Ticket do"

    {after_output, 0} =
      sync_resources!(Path.join(@pack_dir, "ontology_v9_rename_resource.ttl"), out_dir, [
        "--on-stale",
        "prune"
      ])

    assert after_output =~ "wrote #{case_path}"
    assert after_output =~ "pruned: #{ticket_path}"

    # New identity is rendered correctly...
    assert File.exists?(case_path)
    case_content = File.read!(case_path)
    assert Code.string_to_quoted!(case_content)
    assert case_content =~ "defmodule SupportDesk.Support.Case do"
    # ...and all of Ticket's attributes/actions/relationships carried over
    # under the renamed module (same alp:TicketResource IRI, so this is a
    # real rename-in-place of the resource's rendered identity).
    assert case_content =~ "attribute :subject, :string do"
    assert case_content =~ "update :archive do"
    assert case_content =~ "belongs_to :customer, SupportDesk.Support.Customer do"

    # ...and the OLD file is really, mechanically gone -- 0 stale references,
    # not merely 0 stale references WITHIN the surviving files.
    refute File.exists?(ticket_path),
           "expected --on-stale prune to have really deleted the stale #{ticket_path} " <>
             "(the gap this reconciliation manifest closes)"
  end

  # -- 8. Remove resource: alp:TicketResource (whole individual) deleted.
  #    FIXED (was a REAL GAP, same class as #7): the resource query no longer
  #    yields a Ticket row at all, so no new file is written for it -- the
  #    PREVIOUSLY generated out_dir/ticket.ex is now really deleted under
  #    `--on-stale prune` instead of surviving as a silent orphan. -----------
  test "remove resource: Ticket reconciles with 0 stale references (--on-stale prune closes the old gap)" do
    out_dir = tmp_dir!("remove_resource")
    ticket_path = Path.join(out_dir, "ticket.ex")
    customer_path = Path.join(out_dir, "customer.ex")

    {_before_output, 0} = sync_resources!(Path.join(@pack_dir, "ontology.ttl"), out_dir)
    assert File.exists?(ticket_path)
    assert File.exists?(customer_path)

    {after_output, 0} =
      sync_resources!(Path.join(@pack_dir, "ontology_v10_remove_resource.ttl"), out_dir, [
        "--on-stale",
        "prune"
      ])

    # Customer (the surviving resource) is re-rendered fresh and correctly.
    assert after_output =~ "wrote #{customer_path}"
    customer_content = File.read!(customer_path)
    assert Code.string_to_quoted!(customer_content)
    assert customer_content =~ "defmodule SupportDesk.Support.Customer do"
    # ontology_v10_remove_resource.ttl removes BOTH relationship-pair rows
    # (alp:TicketBelongsToCustomer AND alp:CustomerHasManyTickets both
    # target/reference alp:TicketResource, which no longer exists), so
    # Customer's own relationships block is now genuinely empty -- not a
    # stale leftover, a correct reflection of Ticket's removal.
    refute customer_content =~ "has_many :tickets"
    assert customer_content =~ "relationships do\n  end"

    assert after_output =~ "pruned: #{ticket_path}"

    # Ticket no longer exists in the ontology at all, and its previously
    # generated file is now really, mechanically gone -- the exact gap
    # `.ggen_igniter_factory/ADVERSARIAL.md`'s "MUST FIX #3" identified,
    # closed by `GgenIgniter.Manifest` + `--on-stale prune`.
    refute File.exists?(ticket_path),
           "expected --on-stale prune to have really deleted the stale #{ticket_path} " <>
             "(the gap this reconciliation manifest closes)"
  end

  # -- 9. Change domain association: alp:TicketResource moves from
  #    alp:SupportDeskDomain to a NEW alp:BillingDomain, while
  #    alp:CustomerResource stays on alp:SupportDeskDomain. ------------------
  #
  #    Resource-level reconciliation (resource.ex.eex, for_each: resource)
  #    is clean: Ticket's own `use Ash.Resource, domain: ...` line updates to
  #    the new domain module, 0 stale references to the old one.
  #
  #    Domain-level reconciliation (domain.ex.eex) used to be a REAL GAP: the
  #    template's header used to read `<% domain_module = domain_resources |>
  #    List.first() |> Map.get("domain_module") %>`, assuming every
  #    `domain_resources` row shared ONE domain_module and folding ALL
  #    resources' `resource(...)` calls under that single first-row module --
  #    so once Ticket and Customer resolved to two DIFFERENT domain modules,
  #    the template silently produced ONE file registering Ticket under
  #    "SupportDesk.Billing" incorrectly alongside Customer.
  #
  #    FIXED: `domain.ex.eex` now declares `for_each: domains`, driven by a
  #    new `gates/055_domains.rq` (`SELECT DISTINCT ?domain_name
  #    ?domain_module` over every resource's real `alp:resourceDomain`), and
  #    each per-domain rendering filters the full `domain_resources` result
  #    down to just the rows whose own `domain_module` matches THIS render's
  #    domain. A genuinely multi-domain ontology now fans out one real
  #    `defmodule` PER real distinct domain (chosen over an admission-check
  #    refusal because the pack's own `for_each` fan-out mechanism already
  #    handles exactly this "group by a query column, one output per group"
  #    shape for `resource.ex.eex` -- reusing it here is a small, targeted
  #    change, not a new subsystem). ------------------------------------------
  test "change domain association: Ticket Support -> Billing reconciles at the resource level with 0 stale references" do
    out_dir = tmp_dir!("change_domain_resource")
    ticket_path = Path.join(out_dir, "ticket.ex")

    {_before_output, 0} = sync_resources!(Path.join(@pack_dir, "ontology.ttl"), out_dir)
    before_content = File.read!(ticket_path)
    assert before_content =~ "domain: SupportDesk.Support,"

    {after_output, 0} =
      sync_resources!(Path.join(@pack_dir, "ontology_v11_change_domain_association.ttl"), out_dir)

    assert after_output =~ "wrote #{ticket_path}"
    after_content = File.read!(ticket_path)
    assert Code.string_to_quoted!(after_content)

    refute after_content =~ "domain: SupportDesk.Support,"
    assert after_content =~ "domain: SupportDesk.Billing,"
    # Everything else about Ticket survives the domain move untouched.
    assert after_content =~ "attribute :subject, :string do"
    assert after_content =~ "update :archive do"
  end

  test "change domain association: domain.ex.eex fans out one real domain module per distinct domain (fixed, not a gap)" do
    out_dir = tmp_dir!("change_domain_domain")
    out_template = Path.join(out_dir, "<%= String.downcase(domain_name) %>.ex")
    support_path = Path.join(out_dir, "support.ex")
    billing_path = Path.join(out_dir, "billing.ex")

    # Baseline: single real domain (Support) -> exactly one domain file,
    # registering both resources correctly.
    {before_output, 0} = sync_domain!(Path.join(@pack_dir, "ontology.ttl"), out_template)
    assert before_output =~ "wrote #{support_path}"
    refute File.exists?(billing_path)

    before_content = File.read!(support_path)
    assert Code.string_to_quoted!(before_content)
    assert before_content =~ "defmodule SupportDesk.Support do"
    assert before_content =~ "resource(SupportDesk.Support.Ticket)"
    assert before_content =~ "resource(SupportDesk.Support.Customer)"

    {after_output, 0} =
      sync_domain!(
        Path.join(@pack_dir, "ontology_v11_change_domain_association.ttl"),
        out_template
      )

    # The real fix: gates/055_domains.rq now returns rows for TWO distinct
    # domains (Billing, Support), and domain.ex.eex's `for_each: domains`
    # fan-out renders BOTH as their own real files -- 0 misregistration,
    # not a silently-folded single file.
    assert after_output =~ "wrote #{billing_path}"
    assert after_output =~ "wrote #{support_path}"

    assert File.exists?(support_path)
    assert File.exists?(billing_path)

    support_content = File.read!(support_path)
    assert Code.string_to_quoted!(support_content)
    assert support_content =~ "defmodule SupportDesk.Support do"
    # Customer stayed on Support -- still registered here...
    assert support_content =~ "resource(SupportDesk.Support.Customer)"
    # ...and Ticket (moved to Billing) is NOT: no stale/misregistered entry
    # under the domain it no longer belongs to.
    refute support_content =~ "resource(SupportDesk.Support.Ticket)"

    billing_content = File.read!(billing_path)
    assert Code.string_to_quoted!(billing_content)
    assert billing_content =~ "defmodule SupportDesk.Billing do"
    # Ticket is registered under its real new domain...
    assert billing_content =~ "resource(SupportDesk.Support.Ticket)"
    # ...and Customer (which never moved) is NOT incorrectly folded in here.
    refute billing_content =~ "resource(SupportDesk.Support.Customer)"
  end
end
