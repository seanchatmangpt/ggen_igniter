defmodule GgenIgniter.SemanticJiraTargetPackTest do
  @moduledoc """
  Chicago-style proof for lane G2's two-layer `sj:targetPack` law and the
  `pack_digest` receipt stamp.

  Everything runs the real machinery against real fixtures on the real
  filesystem: the real SHACL validator over a real temp-ontology override,
  the real admission kernel, real fixture packs (symlink escape, chmod-000
  unreadable file), the real `ReconcileReactor` pipeline over a real tmp
  Mix project, and the real `mix ggen_igniter.sync` subprocess. No mocks,
  no interaction assertions.

  Mutants named by the lane contract, each killed by a named test:

    * drop the SHACL row -> the "inside the declared vocabulary" test
      (sh:closed refuses an undeclared predicate);
    * add `target_pack` to `@definition_fields` -> the definition_digest
      law test;
    * nil-stamp -> the receipt stamp tests.
  """

  # async: false -- real ReconcileReactor runs (the compensation-telemetry
  # ETS table is global; see ggen_igniter_finalize_evidence_ordering_test.exs)
  # and real fixture packs under priv/ggen/ (cwd-relative pack resolution).
  use ExUnit.Case, async: false

  @moduletag :integration
  @moduletag timeout: 900_000

  alias GgenIgniter.PackLock
  alias GgenIgniter.Reactors.ReconcileReactor
  alias GgenIgniter.Receipt
  alias GgenIgniter.SemanticJira
  alias GgenIgniter.SemanticJira.Shacl
  alias GgenIgniter.SemanticJira.TargetPack

  @ontology_path "priv/ggen/semantic-jira-pack/ontology.ttl"
  @shapes_path "priv/ggen/semantic-jira-pack/shapes/work-order.shacl.ttl"
  @sj_base "https://ggen-igniter.dev/ontology/semantic-jira#"
  @sj_mvp @sj_base <> "semantic-jira-mvp"
  @origin_authority @sj_base <> "objective-code-work-authority"

  # -- SHACL: the optional targetPack row --------------------------------------

  describe "SHACL WorkOrderShape sj:targetPack row" do
    @dogfood_base_sha "sj:baseSha \"d84da1419a6945c6a8a64b8f6cdca9d0b2c9e0f3\" ;"

    test "an sj:targetPack triple is inside the declared WorkOrder vocabulary" do
      conforms =
        @ontology_path
        |> File.read!()
        |> replace_once(
          @dogfood_base_sha,
          @dogfood_base_sha <> " sj:targetPack \"demo-pack\" ;"
        )
        |> validate_override!()

      assert conforms.conforms, "violations:\n#{inspect(conforms.violations, pretty: true)}"
    end

    test "a malformed pack name violates sh:pattern" do
      report =
        @ontology_path
        |> File.read!()
        |> replace_once(
          @dogfood_base_sha,
          @dogfood_base_sha <> " sj:targetPack \"Demo Pack\" ;"
        )
        |> validate_override!()

      refute report.conforms

      violation = fetch_violation!(report, constraint: :pattern, path: @sj_base <> "targetPack")
      assert violation.focus_node == @sj_mvp
      assert violation.value == "Demo Pack"
    end

    test "a second sj:targetPack triple violates sh:maxCount" do
      report =
        @ontology_path
        |> File.read!()
        |> replace_once(
          @dogfood_base_sha,
          @dogfood_base_sha <> " sj:targetPack \"demo-pack\" ; sj:targetPack \"other-pack\" ;"
        )
        |> validate_override!()

      refute report.conforms

      violation = fetch_violation!(report, constraint: :max_count, path: @sj_base <> "targetPack")
      assert violation.focus_node == @sj_mvp
    end
  end

  # -- Admission: FORMAT only ---------------------------------------------------

  describe "admission FORMAT law" do
    test "a well-formed target_pack admits and normalizes onto the map" do
      assert {:ok, admitted} =
               sample_work_order(%{"target_pack" => "demo-pack"})
               |> SemanticJira.admit_work_order()

      assert admitted["target_pack"] == "demo-pack"
    end

    test "an absent target_pack admits with a nil default" do
      assert {:ok, admitted} = sample_work_order() |> SemanticJira.admit_work_order()
      assert admitted["target_pack"] == nil
    end

    test "a malformed target_pack refuses with the typed reason" do
      assert {:error, {:refused_work_order, {:invalid_target_pack, "Demo Pack"}}} =
               sample_work_order(%{"target_pack" => "Demo Pack"})
               |> SemanticJira.admit_work_order()
    end

    test "a non-string target_pack refuses with the typed reason" do
      assert {:error, {:refused_work_order, {:invalid_target_pack, 42}}} =
               sample_work_order(%{"target_pack" => 42}) |> SemanticJira.admit_work_order()
    end

    test "definition_digest law: digest identical with and without target_pack" do
      with_pack = sample_work_order(%{"target_pack" => "demo-pack"})
      without = sample_work_order()

      assert {:ok, d1} = SemanticJira.definition_digest(with_pack)
      assert {:ok, d2} = SemanticJira.definition_digest(without)
      assert d1 == d2, "target_pack must never enter @definition_fields"
    end
  end

  # -- enforce!/2: real fixture packs -------------------------------------------

  describe "TargetPack.enforce!/2" do
    test "the vacuous no-op (no target_pack on any row) returns an empty stamp map" do
      assert %{} = TargetPack.enforce!([{"spec", [%{"id" => "SJ-1"}]}])
    end

    test "an unknown pack raises the typed refusal naming pack and work order" do
      assert_raise ArgumentError, ~r/REFUSED:TARGET_PACK_UNKNOWN/, fn ->
        TargetPack.enforce!([
          {"spec", [%{"id" => "SJ-001", "target_pack" => "no_such_pack_g2"}]}
        ])
      end
    end

    test "the refusal names the exact pack and work order id" do
      message =
        try do
          TargetPack.enforce!([
            {"spec", [%{"id" => "SJ-777", "target_pack" => "no_such_pack_g2"}]}
          ])

          nil
        rescue
          e in ArgumentError -> e.message
        end

      assert message =~ ~s(pack="no_such_pack_g2")
      assert message =~ ~s(work_order="SJ-777")
    end

    test "a happy path returns the pack name -> PackLock digest map" do
      {name, pack_dir} = write_priv_pack!()

      assert %{^name => digest} =
               TargetPack.enforce!([
                 {"spec", [%{"id" => "SJ-1", "target_pack" => name}]}
               ])

      assert {:ok, ^digest} = PackLock.digest_checked(pack_dir)
    end

    test "a symlink to a file outside the pack refuses PACK_SYMLINK_ESCAPE" do
      {name, pack_dir} = write_priv_pack!()
      outside = Path.join(tmp_dir!("tp_escape"), "secret.txt")
      File.write!(outside, "outside")
      File.ln_s!(outside, Path.join(pack_dir, "escape.txt"))

      assert_raise ArgumentError, ~r/REFUSED:PACK_SYMLINK_ESCAPE/, fn ->
        TargetPack.enforce!([{"spec", [%{"id" => "SJ-1", "target_pack" => name}]}])
      end
    end

    test "an unreadable file refuses PACK_FILE_UNREADABLE" do
      {name, pack_dir} = write_priv_pack!()
      sealed = Path.join(pack_dir, "sealed.txt")
      File.write!(sealed, "sealed")
      File.chmod!(sealed, 0o000)
      on_exit(fn -> File.chmod(sealed, 0o755) end)

      assert_raise ArgumentError, ~r/REFUSED:PACK_FILE_UNREADABLE/, fn ->
        TargetPack.enforce!([{"spec", [%{"id" => "SJ-1", "target_pack" => name}]}])
      end
    end
  end

  # -- Receipt stamping: real reactor runs --------------------------------------

  describe "receipt pack stamp (finalize_evidence)" do
    test "a pack run stamps pack_name + pack_digest onto the persisted receipt" do
      pack_dir = tmp_core_pack!("receipt_stamp")
      project_dir = new_mix_project!()

      assert {:ok, receipt} = ReconcileReactor.run(reactor_opts(pack_dir, project_dir))
      assert receipt.standing == :alive

      assert receipt.pack_name == Path.basename(pack_dir)
      assert {:ok, expected} = PackLock.digest_checked(pack_dir)
      assert receipt.pack_digest == expected

      assert [persisted] = Receipt.read_all!(project_dir)
      assert persisted["pack_name"] == Path.basename(pack_dir)
      assert persisted["pack_digest"] == expected
    end

    test "a packless run omits both keys from the persisted receipt (byte-compat)" do
      fixtures = scratch_dir!()
      ontology_path = write_ontology!(fixtures)
      query_path = write_query!(fixtures)
      template_path = write_template!(fixtures)
      project_dir = new_mix_project!()

      opts = [
        engine: "sparql",
        ontology: ontology_path,
        query: "spec=#{query_path}",
        template: template_path,
        out: Path.join(project_dir, "lib/gamma.ex"),
        manifest_dir: project_dir,
        verify_cwd: File.cwd!()
      ]

      assert {:ok, receipt} = ReconcileReactor.run(opts)
      assert receipt.standing == :alive
      assert receipt.pack_name == nil
      assert receipt.pack_digest == nil

      assert [persisted] = Receipt.read_all!(project_dir)
      refute Map.has_key?(persisted, "pack_name")
      refute Map.has_key?(persisted, "pack_digest")
    end

    test "an old receipt chain still verifies through reconstruct_standing" do
      pack_dir = tmp_core_pack!("receipt_chain")
      project_dir = new_mix_project!()

      assert {:ok, first} = ReconcileReactor.run(reactor_opts(pack_dir, project_dir))
      assert {:ok, _second} = ReconcileReactor.run(reactor_opts(pack_dir, project_dir))

      assert {:ok, %{receipt: last, receipt_count: 2}} =
               Receipt.reconstruct_standing(project_dir, first.recipe_key)

      assert last["pack_name"] == Path.basename(pack_dir)
      assert {:ok, last["pack_digest"]} == PackLock.digest_checked(pack_dir)
    end
  end

  # -- Sync subprocess: refusal before dispatch writes zero files ---------------

  describe "sync subprocess refusal (unknown target pack)" do
    test "unknown target_pack exits non-zero, writes nothing, appends no receipt" do
      root = scratch_dir!()
      head = ghead!()
      ontology_path = write_tp_ontology!(root, head, "no_such_pack_g2")
      query_path = write_tp_query!(root)
      template_path = write_tp_template!(root)
      out_path = Path.join(root, "out/wo.ex")

      # The real marker file whose mtime must survive the refused run.
      marker = Path.join(root, "marker.txt")
      File.write!(marker, "marker")
      marker_before = stat_marker(marker)

      args = [
        "ggen_igniter.sync",
        "--ontology",
        ontology_path,
        "--query",
        "spec=#{query_path}",
        "--template",
        template_path,
        "--out",
        out_path,
        "--manifest-dir",
        root,
        "--verify-cwd",
        File.cwd!(),
        "--verify-base-sha"
      ]

      {out, code} = System.cmd("mix", args, cd: File.cwd!(), stderr_to_stdout: true)

      refute code == 0, "expected non-zero exit, got #{code}:\n#{out}"
      assert out =~ "REFUSED:TARGET_PACK_UNKNOWN"
      assert out =~ "no_such_pack_g2"

      # zero writes: no output file, no manifest, no receipt line.
      refute File.exists?(out_path)
      refute File.exists?(Path.join(root, ".ggen_igniter/manifest.json"))
      refute File.exists?(Path.join(root, ".ggen_igniter/receipts"))

      # marker-file mtime check: the real marker file this project carries
      # is byte- and mtime-identical after the refused run.
      assert File.exists?(marker)
      assert stat_marker(marker) == marker_before
    end
  end

  # -- helpers -------------------------------------------------------------------

  defp ghead! do
    {sha, 0} = System.cmd("git", ["rev-parse", "HEAD"], cd: File.cwd!(), stderr_to_stdout: true)
    String.trim_trailing(sha)
  end

  defp stat_marker(path) do
    %{size: size, mtime: mtime} = File.stat!(path, time: :posix)
    {size, mtime}
  end

  defp tmp_dir!(tag) do
    dir =
      Path.join(
        System.tmp_dir!(),
        "ggen_igniter_tp_test_#{tag}_#{System.unique_integer([:positive])}"
      )

    File.rm_rf!(dir)
    File.mkdir_p!(dir)
    on_exit(fn -> File.rm_rf!(dir) end)
    dir
  end

  defp scratch_dir! do
    dir = tmp_dir!("project")
    dir = RealDir.real_dir!(dir)
    dir
  end

  # A real pack directory resolved the way the production law resolves it:
  # cwd-relative `priv/ggen/<name>` (`Pack.resolve_dir!([pack: name])`).
  # Cleaned up in on_exit so the canonical checkout is left untouched.
  defp write_priv_pack! do
    name = "tp_g2_#{System.unique_integer([:positive])}"
    pack_dir = Path.join(["priv", "ggen", name])
    File.mkdir_p!(pack_dir)
    File.write!(Path.join(pack_dir, "witness.txt"), "target pack witness\n")
    on_exit(fn -> File.rm_rf!(pack_dir) end)
    {name, pack_dir}
  end

  # A real admitted Core-profile pack in a tmp dir (explicit --pack-dir),
  # following test/ggen_igniter_pack_manifest_admission_test.exs' fixture.
  defp tmp_core_pack!(tag) do
    dir = tmp_dir!("pack_#{tag}")
    File.mkdir_p!(Path.join(dir, "gates"))
    File.mkdir_p!(Path.join(dir, "templates"))

    File.write!(Path.join(dir, "pack.toml"), """
    [pack]
    name = "#{Path.basename(dir)}"
    version = "1.0.0"
    description = "Lane G2 receipt-stamp witness pack."
    """)

    File.write!(Path.join(dir, "ontology.ttl"), """
    @prefix gp: <https://ggen.dev/ns/pack#> .
    @prefix ex: <http://example.org/tp#> .

    <urn:ggen:pack:#{Path.basename(dir)}>
        a gp:Pack ;
        gp:name "#{Path.basename(dir)}" ;
        gp:version "1.0.0" ;
        gp:profile gp:Core1 .

    ex:Gamma ex:moduleName "TpFixture.Gamma" ; ex:greeting "hello_from_tp_pack" .
    """)

    File.write!(Path.join([dir, "gates", "010_message.rq"]), """
    PREFIX ex: <http://example.org/tp#>
    SELECT ?module_name ?greeting WHERE {
      ex:Gamma ex:moduleName ?module_name ; ex:greeting ?greeting .
    }
    """)

    File.write!(Path.join([dir, "templates", "out.ex.eex"]), """
    defmodule <%= module_name %> do
      def greeting, do: "<%= greeting %>"
    end
    """)

    dir
  end

  defp reactor_opts(pack_dir, work_dir) do
    [
      pack_dir: pack_dir,
      out: Path.join(work_dir, "lib/gamma.ex"),
      manifest_dir: work_dir,
      engine: "sparql",
      verify_cwd: File.cwd!()
    ]
  end

  defp new_mix_project! do
    dir = scratch_dir!()
    File.mkdir_p!(Path.join(dir, "lib"))
    app = "tp_fixture_#{System.unique_integer([:positive])}"

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
      ex:moduleName "GgenIgniterTpFixture.Gamma" ;
      ex:greeting "hello_from_tp_packless" .
    """)

    path
  end

  defp write_query!(dir) do
    path = Path.join(dir, "spec.rq")

    File.write!(path, """
    PREFIX ex: <http://example.org/rr#>
    SELECT ?module_name ?greeting WHERE {
      ex:Gamma ex:moduleName ?module_name ; ex:greeting ?greeting .
    }
    """)

    path
  end

  defp write_template!(dir) do
    path = Path.join(dir, "valid.ex.eex")

    File.write!(path, """
    defmodule <%= module_name %> do
      def greeting, do: "<%= greeting %>"
    end
    """)

    path
  end

  # A one-row WorkOrder ontology naming `pack` as its sj:targetPack, plus
  # the gate query that surfaces it -- the exact shape the sync task's
  # materialized rows carry into `TargetPack.enforce!/2`.
  defp write_tp_ontology!(dir, head, pack) do
    path = Path.join(dir, "wo.ttl")

    File.write!(path, """
    @prefix sj: <#{@sj_base}> .
    @prefix dcterms: <http://purl.org/dc/terms/> .

    sj:wo-tp-refusal a sj:WorkOrder ;
      dcterms:identifier "SJ-TP-REFUSAL" ;
      dcterms:title "Target pack refusal witness" ;
      sj:baseSha "#{head}" ;
      sj:targetPack "#{pack}" .
    """)

    path
  end

  defp write_tp_query!(dir) do
    path = Path.join(dir, "wo.rq")

    File.write!(path, """
    PREFIX sj: <#{@sj_base}>
    PREFIX dcterms: <http://purl.org/dc/terms/>
    SELECT ?id ?base_sha ?target_pack
    WHERE {
      ?work_order a sj:WorkOrder .
      OPTIONAL { ?work_order dcterms:identifier ?id . }
      OPTIONAL { ?work_order sj:baseSha ?base_sha . }
      OPTIONAL { ?work_order sj:targetPack ?target_pack . }
    }
    """)

    path
  end

  defp write_tp_template!(dir) do
    path = Path.join(dir, "wo.ex.eex")
    File.write!(path, "# generated from SJ-TP order\n")
    path
  end

  defp sample_work_order(overrides \\ %{}) do
    Map.merge(
      %{
        "identity" => "SJ-TP-001",
        "title" => "Target pack FORMAT witness",
        "description" => "Exercise the FORMAT/WORLD split without granting authority.",
        "subject" => "urn:subject:tp",
        "repository" => "seanchatmangpt/ggen_igniter",
        "base_sha" => String.duplicate("a", 40),
        "standing" => "UNKNOWN",
        "evidence_ceiling" => "repository-local",
        "promotion_rule" => "exact subject and independent evidence",
        "replay_identity" => "semantic-jira:tp:1",
        "dependencies" => [],
        "required_courts" => ["court:tp"],
        "required_evidence" => ["source", "verification"],
        "acceptance" => ["acceptance:tp"],
        "falsifiers" => ["falsifier:tp"],
        "projections" => SemanticJira.projection_types(),
        "required_receipt_classes" => ["verification"],
        "path_scope" => ["lib/ggen_igniter"],
        "authority_requirement" => "NONE",
        "origin_authority" => @origin_authority,
        "replay_required" => false
      },
      overrides
    )
  end

  defp replace_once(source, pattern, replacement) when is_binary(pattern) do
    String.replace(source, pattern, replacement, global: false)
  end

  defp validate_override!(source) do
    path =
      Path.join(
        System.tmp_dir!(),
        "ggen_igniter_tp_shacl_#{System.unique_integer([:positive])}.ttl"
      )

    File.write!(path, source)
    on_exit(fn -> File.rm_rf!(path) end)
    Shacl.validate_file(path, @shapes_path)
  end

  defp violation(report, opts) do
    Enum.find(report.violations, fn v ->
      Enum.all?(opts, fn {key, value} -> Map.get(v, key) == value end)
    end)
  end

  defp fetch_violation!(report, opts) do
    case violation(report, opts) do
      nil ->
        flunk(
          "no violation matching #{inspect(opts)} in:\n#{inspect(report.violations, pretty: true)}"
        )

      violation ->
        violation
    end
  end
end
