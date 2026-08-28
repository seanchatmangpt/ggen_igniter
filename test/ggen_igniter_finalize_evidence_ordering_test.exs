defmodule GgenIgniter.FinalizeEvidenceOrderingTest do
  @moduledoc """
  Chicago-style, no-mocks proof of correction B on
  `GgenIgniter.Reactors.ReconcileReactor`'s `:finalize_evidence` step: the
  receipt is persisted BEFORE the manifest is promoted, and a real failure
  of the manifest-promotion step alone (receipt already durable) is
  recoverable, not silently corrupt.

  Quoting the user directly:

  > verify succeeds -> manifest advances -> receipt write fails. Now you
  > have standing state with no standing evidence.

  The real failure injected here is `GgenIgniter.Manifest.persist!/2`'s own
  temp-file write (`File.write!(tmp_path, json)`, the step immediately
  before its `File.rename!/2`): this test pre-creates `.ggen_igniter/`
  (manifest.json's real parent directory) and makes it read-only
  (`File.chmod!(dir, 0o555)`) AFTER first creating `.ggen_igniter/receipts/`
  (still writable) inside it -- so:

    * `:observe_prior_manifest`'s real read of a not-yet-existing
      `manifest.json` still succeeds (`File.read/1` on a missing path only
      needs search permission on the parent, which `0o555` grants) --
      confirmed empirically before writing this test, not assumed.
    * `GgenIgniter.Receipt.append!/2`'s real write into the already-created,
      still-writable `receipts/` subdirectory still succeeds (a
      subdirectory's own write permission governs files created inside IT,
      not its parent's) -- also confirmed empirically.
    * `GgenIgniter.Manifest.persist!/2`'s real `File.write!/2` of its temp
      file, a NEW file directly inside the now read-only `.ggen_igniter/`,
      genuinely raises `File.Error` ("permission denied") -- confirmed
      empirically: this is the real failure this test exercises, occurring
      strictly AFTER the receipt has already been durably persisted.

  No mock of `File`, `Manifest`, or `Reactor` anywhere in this file -- every
  permission effect above is a real `File.chmod!/2` on a real directory on
  the real filesystem.
  """

  use ExUnit.Case, async: false

  alias GgenIgniter.Manifest
  alias GgenIgniter.Reactors.ReconcileReactor
  alias GgenIgniter.Receipt

  defp scratch_dir! do
    dir =
      Path.join(
        System.tmp_dir!(),
        "ggen_igniter_finalize_evidence_test_#{System.unique_integer([:positive])}"
      )

    File.rm_rf!(dir)
    File.mkdir_p!(dir)
    on_exit(fn -> File.rm_rf!(dir) end)
    dir
  end

  defp new_mix_project! do
    dir = scratch_dir!()
    File.mkdir_p!(Path.join(dir, "lib"))

    app = "finalize_evidence_fixture_#{System.unique_integer([:positive])}"

    File.write!(Path.join(dir, "mix.exs"), """
    defmodule #{Macro.camelize(app)}.MixProject do
      use Mix.Project

      def project do
        [app: :#{app}, version: "0.1.0", elixir: "~> 1.14", deps: []]
      end
    end
    """)

    dir
  end

  defp write_ontology!(dir) do
    path = Path.join(dir, "ontology.ttl")

    File.write!(path, """
    @prefix ex: <http://example.org/rr#> .
    ex:Gamma a ex:Module ;
      ex:moduleName "GgenIgniterFinalizeEvidenceFixture.Gamma" ;
      ex:greeting "hello_from_gamma" .
    """)

    path
  end

  defp write_query!(dir) do
    path = Path.join(dir, "spec_gamma.rq")

    File.write!(path, """
    PREFIX ex: <http://example.org/rr#>
    SELECT ?module_name ?greeting WHERE {
      ex:Gamma ex:moduleName ?module_name ; ex:greeting ?greeting .
    }
    """)

    path
  end

  defp write_valid_template!(dir) do
    path = Path.join(dir, "valid.ex.eex")

    File.write!(path, """
    defmodule <%= module_name %> do
      def greeting, do: "<%= greeting %>"
    end
    """)

    path
  end

  describe "receipt-before-manifest ordering (correction B)" do
    test "a real manifest-rename failure leaves a durable :alive receipt and an untouched manifest path" do
      fixtures = scratch_dir!()
      ontology_path = write_ontology!(fixtures)
      query_path = write_query!(fixtures)
      template_path = write_valid_template!(fixtures)

      project_dir = new_mix_project!()
      out_path = Path.join([project_dir, "lib", "gamma.ex"])

      manifest_path = Manifest.path(project_dir)
      ggen_dir = Path.dirname(manifest_path)
      receipts_dir = Path.join(ggen_dir, "receipts")

      # -- The real failure injection: create `.ggen_igniter/receipts/`
      # (still writable) FIRST, then make `.ggen_igniter/` itself read-only
      # -- see this module's moduledoc for exactly why each of the three
      # real filesystem operations below behaves the way it does.
      File.mkdir_p!(receipts_dir)
      File.chmod!(ggen_dir, 0o555)
      on_exit(fn -> File.chmod(ggen_dir, 0o755) end)

      reconcile_opts = [
        engine: "sparql",
        ontology: ontology_path,
        query: "spec=#{query_path}",
        template: template_path,
        out: out_path,
        manifest_dir: project_dir,
        verify_cwd: project_dir
      ]

      result = ReconcileReactor.run(reconcile_opts)

      # -- The real, correct outcome: NOT a reactor failure. The files were
      # genuinely written and verified correctly; only the manifest CACHE
      # promotion failed, and that failure is caught locally rather than
      # rolling back real, good work.
      assert {:ok, receipt} = result
      assert receipt.standing == :alive

      # -- The real file this run intended to write is genuinely present
      # with the real, correct content -- not rolled back because of the
      # manifest-promotion failure.
      assert File.exists?(out_path)
      assert File.read!(out_path) =~ "hello_from_gamma"

      # -- The manifest's own target path is UNTOUCHED: still absent, never
      # corrupted into a half-written file or a stray temp file left next
      # to it (the temp-file write itself is what failed, before any
      # rename was ever attempted).
      refute File.exists?(manifest_path),
             "expected the manifest path to remain untouched (never even reached the rename) after the failed temp-file write"

      refute Path.wildcard(Path.join(ggen_dir, "manifest.json.tmp-*")) != [],
             "expected no stray temp file to be left behind by the failed manifest write"

      # -- The receipt's own metadata records the pending promotion, real
      # evidence a retry/human could act on.
      assert receipt.metadata["manifest_promotion"] =~ "pending"

      # -- THE KEY PROOF: the receipt is durable on disk RIGHT NOW, read
      # back from disk (not the in-memory struct this test already has) --
      # "receipt exists, manifest not yet promoted" is real and observable,
      # never "manifest advanced but no receipt exists to explain why".
      assert [persisted] = Receipt.read_all!(project_dir)
      assert persisted["standing"] == "alive"
      assert persisted["files"] == [out_path]
    end
  end
end
