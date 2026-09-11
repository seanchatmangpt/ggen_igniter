defmodule GgenIgniter.CrossPackageOntologySyncTest do
  @moduledoc """
  Chicago-style, no-mocks proof for `docs/jira/v26.9.10/
  01-CROSS-PACKAGE-ONTOLOGY-SYNC.md`: real files on disk under
  `test/fixtures/cross_package_ontology/`, real `mix ggen_igniter.sync`
  subprocesses (`System.cmd/3`, matching this repo's existing subprocess-test
  convention -- see `ggen_igniter_sync_pack_test.exs`), and one real
  `GgenIgniter.Ontology.load!/1` in-process call with a genuinely changed OS
  cwd (`File.cd!/2`) to directly exercise the cwd-relative resolution
  mechanism the ticket's "confirmed this session" finding names:
  `resolve_ontology!/1` (`lib/mix/tasks/ggen_igniter.sync.ex`) passes
  `--ontology` through verbatim, and `RDF.Turtle.read_file!/1` (reached via
  `GgenIgniter.Ontology.load!/1`) resolves a relative path against the real
  OS process cwd -- never a path baked to `ggen_igniter`'s own location.

  Fixture shape (mirrors `~/ash_ex4pm`'s real cross-package usage -- see
  `docs/integrations/ggen/cross-package-sync.md`):

  - `test/fixtures/cross_package_ontology/library/priv/ontology/` -- the
    "library" package's own packaged ontology, two variants:
    `capability.ttl` (one `admitted` capability, one `forward_declared`)
    and `capability_none_admitted.ttl` (every capability
    `forward_declared`, none `admitted`).
  - `test/fixtures/cross_package_ontology/consumer/deps/capability_lib/
    priv/ontology/` -- the SAME two files, at the path shape a real `mix
    deps.get` would produce inside a consuming project's own `deps/` tree.
  - `test/fixtures/cross_package_ontology/consumer/admitted_capabilities.rq`,
    `capability_delegate.ex.eex` -- the consumer's own query/template.
  """
  use ExUnit.Case, async: false

  @moduletag :integration

  @fixture_root "test/fixtures/cross_package_ontology"
  @consumer_root "#{@fixture_root}/consumer"
  @deps_ontology_dir "#{@consumer_root}/deps/capability_lib/priv/ontology"

  defp unique_out_dir(tag) do
    dir =
      Path.join(
        System.tmp_dir!(),
        "ggen_igniter_cross_package_#{tag}_#{System.unique_integer([:positive])}"
      )

    File.rm_rf!(dir)
    dir
  end

  defp run_sync(ontology_rel_path, out_path, manifest_dir) do
    args = [
      "ggen_igniter.sync",
      # Pinned to sparql for the same reason ggen_igniter_sync_pack_test.exs
      # pins it: real generated content asserted by literal string value,
      # and oxigraph returns typed literals as raw datatype-annotated term
      # strings -- a real, disclosed, unrelated engine-shape difference.
      "--engine",
      "sparql",
      "--ontology",
      ontology_rel_path,
      "--query",
      "admitted=#{@consumer_root}/admitted_capabilities.rq",
      "--template",
      "#{@consumer_root}/capability_delegate.ex.eex",
      "--out",
      out_path,
      "--manifest-dir",
      manifest_dir,
      "--verify-cwd",
      File.cwd!()
    ]

    System.cmd("mix", args, cd: File.cwd!(), stderr_to_stdout: true)
  end

  describe "individuals present (admitted capability) -- non-empty generated output" do
    test "mix ggen_igniter.sync resolves a deps/<library>/priv/ontology/<file>.ttl path and generates a real function" do
      out_dir = unique_out_dir("admitted")
      on_exit(fn -> File.rm_rf!(out_dir) end)
      out_path = Path.join(out_dir, "capability_delegate.ex")

      {output, exit_code} =
        run_sync("#{@deps_ontology_dir}/capability.ttl", out_path, out_dir)

      assert exit_code == 0, "mix ggen_igniter.sync failed:\n#{output}"
      assert File.exists?(out_path)

      content = File.read!(out_path)
      assert {:defmodule, _, _} = Code.string_to_quoted!(content)
      assert content =~ "defmodule CrossPackageOntology.CapabilityDelegate do"
      # `widget_plan` is `ccp:status "admitted"` in capability.ttl.
      assert content =~ "def widget_plan(), do: :ok"
      # `gadget_plan` is `ccp:status "forward_declared"` there -- must NOT
      # appear, proving the query's own admitted-only filter (not just the
      # ontology load) drove the generated content.
      refute content =~ "gadget_plan"
    end
  end

  describe "individuals not yet admitted -- empty-but-valid generated output" do
    test "mix ggen_igniter.sync generates a real, valid, empty-function-list module, matching ferroplan.ex's observed shape" do
      out_dir = unique_out_dir("none_admitted")
      on_exit(fn -> File.rm_rf!(out_dir) end)
      out_path = Path.join(out_dir, "capability_delegate.ex")

      {output, exit_code} =
        run_sync(
          "#{@deps_ontology_dir}/capability_none_admitted.ttl",
          out_path,
          out_dir
        )

      assert exit_code == 0, "mix ggen_igniter.sync failed:\n#{output}"
      assert File.exists?(out_path)

      content = File.read!(out_path)
      # Empty-but-valid: parses as real Elixir, defines the module, defines
      # no capability functions (no individual there is "admitted").
      assert {:defmodule, _, _} = Code.string_to_quoted!(content)
      assert content =~ "defmodule CrossPackageOntology.CapabilityDelegate do"
      refute content =~ "def widget_plan"
      refute content =~ "def gadget_plan"
    end
  end

  describe "the real cwd-relative resolution mechanism (no CLI, direct module call)" do
    test "GgenIgniter.Ontology.load!/1 resolves deps/capability_lib/... only when the real OS cwd is the consumer root" do
      consumer_abs = Path.expand(@consumer_root)
      relative_ontology = "deps/capability_lib/priv/ontology/capability.ttl"

      # Control: from THIS repo's own root (a different real cwd), the same
      # relative path does not exist -- proves the assertion below is
      # actually cwd-dependent, not vacuously true for any cwd.
      refute File.exists?(relative_ontology)

      # Real, actual OS process cwd change (File.cd!/2), restored afterward.
      # Real GgenIgniter.Ontology.load!/1 call -- real RDF.Turtle.read_file!
      # -> File.open!/2 resolving the relative path against the changed cwd.
      graph =
        File.cd!(consumer_abs, fn ->
          assert File.cwd!() == consumer_abs
          GgenIgniter.Ontology.load!(relative_ontology)
        end)

      assert %RDF.Graph{} = graph
      assert RDF.Graph.triple_count(graph) > 0
    end
  end

  describe "missing --ontology (direct flag, not --pack/--pack-dir)" do
    test "raises the same friendlier named error shape --pack/--pack-dir already has, naming the resolved path and real cwd" do
      out_dir = unique_out_dir("missing")
      on_exit(fn -> File.rm_rf!(out_dir) end)
      out_path = Path.join(out_dir, "capability_delegate.ex")
      missing_path = "#{@deps_ontology_dir}/does_not_exist.ttl"

      {output, exit_code} = run_sync(missing_path, out_path, out_dir)

      assert exit_code != 0
      assert output =~ "--ontology resolved ontology not found at #{missing_path}"
      assert output =~ "current working directory"
      assert output =~ "docs/integrations/ggen/cross-package-sync.md"
      refute File.exists?(out_path)
    end
  end
end
