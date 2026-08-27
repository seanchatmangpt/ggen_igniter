defmodule GgenIgniter.SyncPackTemplateStemTest do
  @moduledoc """
  Chicago-style, no-mocks proof that `mix ggen_igniter.sync --pack
  NAME:TEMPLATE_STEM` selects one specific template out of a pack whose
  `templates/` dir has more than one file -- bypassing the "multiple
  templates found" ambiguity error `GgenIgniter.Pack.discover_template/2`
  raises for plain `--pack NAME` -- via real subprocess `mix
  ggen_igniter.sync` runs against a real copy of
  `test/fixtures/ash-lifecycle-pack/` (2 real templates:
  `templates/resource.ex.eex`, `templates/domain.ex.eex`).

  `--pack NAME` (bare) only ever resolves under `priv/ggen/<name>/` (see
  `GgenIgniter.Pack.resolve_dir!/1`), never directly against a `test/fixtures/`
  path -- so, mirroring `ggen_igniter_sync_pack_test.exs`'s own `"--pack NAME"`
  test, the fixture's real files are copied into
  `priv/ggen/ash-lifecycle-pack-stem-test/` before each test and removed via
  `on_exit` after, rather than inventing a synthetic pack.
  """
  use ExUnit.Case, async: false

  @moduletag :integration

  @fixture_dir "test/fixtures/ash-lifecycle-pack"
  @pack_name "ash-lifecycle-pack-stem-test"
  @pack_root Path.join(["priv", "ggen", @pack_name])

  setup do
    File.mkdir_p!(Path.join(@pack_root, "gates"))
    File.mkdir_p!(Path.join(@pack_root, "templates"))

    File.cp!(
      Path.join(@fixture_dir, "ontology.ttl"),
      Path.join(@pack_root, "ontology.ttl")
    )

    @fixture_dir
    |> Path.join("gates")
    |> File.ls!()
    |> Enum.each(fn gate_file ->
      File.cp!(
        Path.join([@fixture_dir, "gates", gate_file]),
        Path.join([@pack_root, "gates", gate_file])
      )
    end)

    # Real proof this fixture pack genuinely has 2 templates (the exact
    # precondition `--pack NAME:TEMPLATE_STEM` exists to disambiguate) --
    # asserted here, once, rather than assumed from the task description.
    template_files = @fixture_dir |> Path.join("templates") |> File.ls!() |> Enum.sort()
    assert template_files == ["domain.ex.eex", "resource.ex.eex"]

    Enum.each(template_files, fn template_file ->
      File.cp!(
        Path.join([@fixture_dir, "templates", template_file]),
        Path.join([@pack_root, "templates", template_file])
      )
    end)

    on_exit(fn -> File.rm_rf!(@pack_root) end)

    tmp_dir =
      Path.join(
        System.tmp_dir!(),
        "ggen_igniter_sync_pack_stem_test_#{System.unique_integer([:positive])}"
      )

    File.rm_rf!(tmp_dir)
    File.mkdir_p!(tmp_dir)
    on_exit(fn -> File.rm_rf!(tmp_dir) end)

    %{tmp_dir: tmp_dir}
  end

  test "--pack NAME:resource selects templates/resource.ex.eex specifically, even with 2 templates present",
       %{tmp_dir: tmp_dir} do
    # `resource.ex.eex`'s own frontmatter fans out one file per row of the
    # `resource` query (for_each: resource) -- override its `to:` via an
    # explicit --out EEx path template so the real written files land under
    # this test's own tmp_dir, not this repo's lib/support_desk/ tree.
    out_template = Path.join(tmp_dir, "<%= String.downcase(resource_name) %>.ex")

    args = [
      "ggen_igniter.sync",
      "--engine",
      "sparql",
      "--pack",
      "#{@pack_name}:resource",
      "--out",
      out_template
    ]

    {output, exit_code} = System.cmd("mix", args, cd: File.cwd!(), stderr_to_stdout: true)

    assert exit_code == 0,
           "mix ggen_igniter.sync --pack #{@pack_name}:resource failed:\n#{output}"

    ticket_path = Path.join(tmp_dir, "ticket.ex")
    customer_path = Path.join(tmp_dir, "customer.ex")

    assert File.exists?(ticket_path)
    assert File.exists?(customer_path)

    ticket_content = File.read!(ticket_path)
    assert {:defmodule, _, _} = Code.string_to_quoted!(ticket_content)
    assert ticket_content =~ "defmodule SupportDesk.Support.Ticket do"
    assert ticket_content =~ "attribute :subject, :string do"

    # The OTHER pack template (domain.ex.eex) was NOT rendered by this
    # invocation -- real proof the `:resource` stem selected specifically
    # resource.ex.eex, not "whichever template happened to run first".
    refute File.exists?(Path.join(tmp_dir, "support.ex"))
    refute output =~ "defmodule SupportDesk.Support do"
  end

  test "--pack NAME:domain selects templates/domain.ex.eex specifically, even with 2 templates present",
       %{tmp_dir: tmp_dir} do
    out_path = Path.join(tmp_dir, "support.ex")

    args = [
      "ggen_igniter.sync",
      "--engine",
      "sparql",
      "--pack",
      "#{@pack_name}:domain",
      "--out",
      out_path
    ]

    {output, exit_code} = System.cmd("mix", args, cd: File.cwd!(), stderr_to_stdout: true)

    assert exit_code == 0, "mix ggen_igniter.sync --pack #{@pack_name}:domain failed:\n#{output}"
    assert File.exists?(out_path)

    content = File.read!(out_path)
    assert {:defmodule, _, _} = Code.string_to_quoted!(content)
    assert content =~ "defmodule SupportDesk.Support do"
    assert content =~ "resource(SupportDesk.Support.Ticket)"
    assert content =~ "resource(SupportDesk.Support.Customer)"

    # The OTHER pack template (resource.ex.eex) was NOT rendered by this
    # invocation -- real proof the `:domain` stem selected specifically
    # domain.ex.eex, not "whichever template happened to run first".
    refute File.exists?(Path.join(tmp_dir, "ticket.ex"))
    refute File.exists?(Path.join(tmp_dir, "customer.ex"))
  end

  test "plain --pack NAME (no :TEMPLATE_STEM) still produces the exact same real ambiguity error as before" do
    args = [
      "ggen_igniter.sync",
      "--engine",
      "sparql",
      "--pack",
      @pack_name
    ]

    {output, exit_code} = System.cmd("mix", args, cd: File.cwd!(), stderr_to_stdout: true)

    refute exit_code == 0, "expected plain --pack #{@pack_name} to fail with an ambiguity error"

    assert output =~ "multiple templates found in"
    assert output =~ "#{@pack_root}/templates"
    assert output =~ "domain.ex.eex"
    assert output =~ "resource.ex.eex"
    assert output =~ "pass --template explicitly"
  end
end
