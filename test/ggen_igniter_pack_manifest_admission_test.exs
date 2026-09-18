defmodule GgenIgniter.PackManifestAdmissionTest do
  @moduledoc """
  RFC-GPACK-001 §7/§8/§10/§12.1/§86.1-2/§89 admission witnesses for
  `GgenIgniter.Pack.parse_manifest/1`, `GgenIgniter.Pack.declared_profile/1`,
  and `GgenIgniter.Pack.admit_pack_manifest/2`, plus the real-pipeline
  enforcement witnesses through `GgenIgniter.Reactors.ReconcileReactor`
  (`run/1` and the read-only `plan/1`).

  Chicago-style, no mocks: every pack below is a real directory on disk with
  a real `pack.toml` (strict `Toml.decode`), a real `ontology.ttl` (real
  `RDF.Turtle` parse via `GgenIgniter.Ontology.load!/1`), a real gate query,
  and a real template. The ticket's five required witnesses:

    1. Core pack, matching identities -> admitted
    2. Core pack, manifest name != gp:name -> REFUSED:PACK_IDENTITY_MISMATCH
    3. Core pack, unknown [pack] key -> REFUSED:PACK_MANIFEST_INVALID
    4. Legacy pack without pack.toml -> unchanged behavior (compat witness)
    5. Inversion witness on the mismatch test (prove the guard can fail)

  plus pipeline-level witnesses that the `:admit_pack` reactor step and
  `plan/1` really enforce (a guard that is never reached on the real path is
  vacuous in a different way -- §79).
  """

  use ExUnit.Case, async: false

  alias GgenIgniter.{Ontology, Pack}
  alias GgenIgniter.Pack.Manifest
  alias GgenIgniter.Reactors.ReconcileReactor

  @gp "https://ggen.dev/ns/pack#"

  # -- fixture builders -------------------------------------------------------

  defp tmp_pack_dir(tag) do
    dir =
      Path.join(
        System.tmp_dir!(),
        "ggen_igniter_pack_manifest_admission_test_#{tag}_#{System.unique_integer([:positive])}"
      )

    File.rm_rf!(dir)
    File.mkdir_p!(Path.join(dir, "gates"))
    File.mkdir_p!(Path.join(dir, "templates"))
    on_exit(fn -> File.rm_rf!(dir) end)
    dir
  end

  defp strict_manifest(name, opts \\ []) do
    version = Keyword.get(opts, :version, "1.0.0")
    description = Keyword.get(opts, :description, "Core witness pack.")

    """
    [pack]
    name = "#{name}"
    version = "#{version}"
    description = "#{description}"
    """
  end

  defp core_ontology(graph_name, profile) do
    """
    @prefix gp: <#{@gp}> .

    <urn:ggen:pack:#{graph_name}>
        a gp:Pack ;
        gp:name "#{graph_name}" ;
        gp:version "1.0.0" ;
        gp:profile gp:#{profile} .
    """
  end

  defp write_core_pack(dir, opts \\ []) do
    manifest = Keyword.get(opts, :manifest, strict_manifest("core-manifest-pack"))

    ontology =
      Keyword.get(
        opts,
        :ontology,
        core_ontology(Keyword.get(opts, :graph_name, "core-manifest-pack"), "Core1")
      )

    File.write!(Path.join(dir, "pack.toml"), manifest)
    File.write!(Path.join(dir, "ontology.ttl"), ontology)

    File.write!(Path.join([dir, "gates", "010_message.rq"]), """
    PREFIX ex: <https://example.org/hello#>

    SELECT ?message
    WHERE {
      ex:Hello ex:message ?message .
    }
    """)

    File.write!(Path.join([dir, "templates", "out.txt.eex"]), "static witness body\n")
    dir
  end

  defp load_graph(dir), do: Ontology.load!(Path.join(dir, "ontology.ttl"))

  # -- §7.1 strict manifest parsing ------------------------------------------

  describe "parse_manifest/1 (RFC-GPACK-001 §7.1)" do
    test "parses a valid [pack] table into a Manifest struct" do
      dir = write_core_pack(tmp_pack_dir("parse_ok"))
      assert {:ok, %Manifest{} = m} = Pack.parse_manifest(dir)

      assert %{name: "core-manifest-pack", version: "1.0.0", description: "Core witness pack."} =
               Map.from_struct(m)
    end

    test "returns :absent when no pack.toml exists" do
      dir = tmp_pack_dir("parse_absent")
      assert Pack.parse_manifest(dir) == :absent
    end

    test "refuses invalid TOML (real broken-pack fixture)" do
      assert {:refused, {:pack_manifest_invalid, [diagnostic: d]}} =
               Pack.parse_manifest("test/fixtures/broken-pack")

      assert d =~ "not valid TOML"
    end

    test "refuses a legacy-shaped manifest with no [pack] table (real sample-pack fixture)" do
      assert {:refused, {:pack_manifest_invalid, [diagnostic: d]}} =
               Pack.parse_manifest("test/fixtures/sample-pack")

      assert d =~ "no [pack] table"
    end

    test "refuses a missing required key" do
      dir = tmp_pack_dir("parse_missing")

      File.write!(
        Path.join(dir, "pack.toml"),
        "[pack]\nname = \"x\"\nversion = \"1.0.0\"\n"
      )

      assert {:refused, {:pack_manifest_invalid, [diagnostic: d]}} = Pack.parse_manifest(dir)
      assert d =~ "missing required [pack] key"
      assert d =~ ~s("description")
    end

    test "refuses a non-string value" do
      dir = tmp_pack_dir("parse_nonstring")

      File.write!(
        Path.join(dir, "pack.toml"),
        "[pack]\nname = \"x\"\nversion = 3\ndescription = \"d\"\n"
      )

      assert {:refused, {:pack_manifest_invalid, [diagnostic: d]}} = Pack.parse_manifest(dir)
      assert d =~ "must be a string"
    end
  end

  # -- §10 profile detection --------------------------------------------------

  describe "declared_profile/1 (RFC-GPACK-001 §10)" do
    test "detects gp:Core1 as core" do
      dir = write_core_pack(tmp_pack_dir("profile_core1"))
      assert Pack.declared_profile(load_graph(dir)) == {:core, @gp <> "Core1"}
    end

    test "detects gp:Portable1 as core (Core-family per ticket scope)" do
      dir =
        write_core_pack(tmp_pack_dir("profile_portable1"),
          ontology: core_ontology("core-manifest-pack", "Portable1")
        )

      assert Pack.declared_profile(load_graph(dir)) == {:core, @gp <> "Portable1"}
    end

    test "a graph with no gp:profile is legacy" do
      dir = tmp_pack_dir("profile_legacy")

      File.write!(Path.join(dir, "ontology.ttl"), """
      @prefix gp: <#{@gp}> .

      <urn:ggen:pack:legacy-pack>
          a gp:Pack ;
          gp:name "legacy-pack" .
      """)

      assert Pack.declared_profile(load_graph(dir)) == :legacy
    end

    test "works over an RDF.Dataset (named-graph quads as well as triples)" do
      dataset =
        RDF.Dataset.new()
        |> RDF.Dataset.add(
          {RDF.iri("urn:ggen:pack:dq"), RDF.iri(@gp <> "profile"), RDF.iri(@gp <> "Core1")}
        )

      assert Pack.declared_profile(dataset) == {:core, @gp <> "Core1"}
    end
  end

  # -- §8 identity correspondence + §86.1-2/§89 profile-conditional admission --

  describe "admit_pack_manifest/2 (RFC-GPACK-001 §8, §86.1-2, §89)" do
    @tag :ticket_witness_1
    test "ticket witness 1: Core pack with matching identities is admitted" do
      dir = write_core_pack(tmp_pack_dir("admit_match"))
      assert Pack.admit_pack_manifest(dir, load_graph(dir)) == :ok
    end

    @tag :ticket_witness_2
    test "ticket witness 2: Core pack with manifest name != gp:name is REFUSED:PACK_IDENTITY_MISMATCH" do
      dir =
        write_core_pack(tmp_pack_dir("admit_mismatch"),
          manifest: strict_manifest("manifest-name"),
          ontology: core_ontology("graph-name", "Core1")
        )

      graph = load_graph(dir)

      assert {:refused, {:pack_identity_mismatch, [diagnostic: d]}} =
               Pack.admit_pack_manifest(dir, graph)

      # The typed refusal identifier's referent, not mutable prose, is what the
      # diagnostic must pin (§16): exactly which graph identity disagreed with
      # exactly which manifest identity, under which normative relation.
      assert d =~ ~s(gp:name ["graph-name"])
      assert d =~ ~s([pack].name "manifest-name")
      assert d =~ "RFC-GPACK-001 §8"
    end

    @tag :ticket_witness_3
    test "ticket witness 3: Core pack with an unknown [pack] key is REFUSED:PACK_MANIFEST_INVALID" do
      manifest = """
      [pack]
      name = "core-manifest-pack"
      version = "1.0.0"
      description = "Core witness pack."
      homepage = "https://example.org/pack"
      """

      dir = write_core_pack(tmp_pack_dir("admit_unknown_key"), manifest: manifest)

      assert {:refused, {:pack_manifest_invalid, [diagnostic: d]}} =
               Pack.admit_pack_manifest(dir, load_graph(dir))

      assert d =~ "unknown key(s) inside [pack]"
      assert d =~ ~s("homepage")
    end

    test "a Core pack with NO pack.toml is REFUSED:PACK_MANIFEST_MISSING (§12.1/§86.1: REQUIRED)" do
      dir = tmp_pack_dir("admit_missing_manifest")

      File.write!(
        Path.join(dir, "ontology.ttl"),
        core_ontology("core-manifest-pack", "Core1")
      )

      assert {:refused, {:pack_manifest_missing, [diagnostic: d]}} =
               Pack.admit_pack_manifest(dir, load_graph(dir))

      assert d =~ "no pack.toml"
      assert d =~ "Core1"
    end

    test "a Core pack whose graph declares no gp:name fails closed as a mismatch (recorded)" do
      ontology = """
      @prefix gp: <#{@gp}> .

      <urn:ggen:pack:nameless>
          a gp:Pack ;
          gp:profile gp:Core1 .
      """

      dir = write_core_pack(tmp_pack_dir("admit_no_graph_name"), ontology: ontology)

      assert {:refused, {:pack_identity_mismatch, [diagnostic: d]}} =
               Pack.admit_pack_manifest(dir, load_graph(dir))

      assert d =~ "declares no gp:name"
    end

    test "a Core pack with a SECOND, disagreeing gp:name refuses (no silent first-match)" do
      ontology = """
      @prefix gp: <#{@gp}> .

      <urn:ggen:pack:a>
          a gp:Pack ;
          gp:name "core-manifest-pack" ;
          gp:profile gp:Core1 .

      <urn:ggen:pack:b>
          a gp:Pack ;
          gp:name "other-name" ;
          gp:profile gp:Core1 .
      """

      dir = write_core_pack(tmp_pack_dir("admit_two_names"), ontology: ontology)

      assert {:refused, {:pack_identity_mismatch, [diagnostic: _]}} =
               Pack.admit_pack_manifest(dir, load_graph(dir))
    end

    @tag :ticket_witness_4
    test "ticket witness 4: legacy pack without pack.toml keeps today's behavior (compat witness)" do
      dir = tmp_pack_dir("admit_legacy_no_manifest")

      # No gp:profile, no pack.toml, and (byte-compat is the point) not even a
      # gp:name -- a legacy pack must pass through WITHOUT any new refusal,
      # because the legacy path never reads the manifest at all (§86.2/§89).
      File.write!(Path.join(dir, "ontology.ttl"), """
      @prefix aex: <http://seanchatmangpt.github.io/packs/ash-extension-core#> .

      aex:Something a aex:AshExtensionSpec ; aex:packageName "audit_trail" .
      """)

      File.write!(Path.join([dir, "gates", "010_x.rq"]), "SELECT ?x WHERE { ?x ?y ?z }")
      assert Pack.admit_pack_manifest(dir, load_graph(dir)) == :ok
    end

    test "legacy pack keeps today's behavior even with a NONCONFORMING pack.toml present" do
      # The real sample-pack fixture: no gp:profile in its graph, and a
      # legacy-shaped pack.toml (top-level keys, no [pack] table) that the
      # strict §7.1 parser would refuse -- but a legacy pack must never reach
      # that parser (§86.2: legacy = optional-manifest, zero new refusals).
      dir = "test/fixtures/sample-pack"

      assert Pack.declared_profile(load_graph(dir)) == :legacy
      assert Pack.admit_pack_manifest(dir, load_graph(dir)) == :ok
    end

    test "nil pack_dir (no --pack/--pack-dir given) is admitted without reading anything" do
      assert Pack.admit_pack_manifest(nil, %RDF.Graph{}) == :ok
    end
  end

  # -- §79: the mismatch guard is load-bearing (inversion witness) -------------

  describe "inversion witness (RFC-GPACK-001 §79: a guard that cannot fail is vacuous)" do
    @tag :ticket_witness_5
    test "ticket witness 5: removing ONLY the Core-profile routing removes ONLY the refusal" do
      dir =
        write_core_pack(tmp_pack_dir("inversion"),
          manifest: strict_manifest("manifest-name"),
          ontology: core_ontology("graph-name", "Core1")
        )

      graph = load_graph(dir)

      # The guard genuinely fires on this subject...
      assert {:refused, {:pack_identity_mismatch, [diagnostic: _]}} =
               Pack.admit_pack_manifest(dir, graph)

      # ...and NOTHING ELSE does: the manifest itself is §7.1-valid, so the
      # refusal is attributable SOLELY to the identity-correspondence gate.
      assert {:ok, %Manifest{name: "manifest-name"}} = Pack.parse_manifest(dir)

      # Sabotage (§79): delete the ONE fact the guard routes on -- the
      # gp:profile triple -- keeping everything else identical (same gp:name
      # "graph-name", same pack dir, same pack.toml). The subject is then
      # admitted: if the guard (or its Core-profile classification, i.e. the
      # RFC-GPACK-001 change itself) were deleted, this exact pack would sail
      # through and ticket-witness-2 above would fail. The guard is
      # load-bearing, not vacuous.
      sabotaged_ttl = """
      @prefix gp: <#{@gp}> .

      <urn:ggen:pack:graph-name>
          a gp:Pack ;
          gp:name "graph-name" ;
          gp:version "1.0.0" .
      """

      sabotaged_path = Path.join(dir, "ontology_legacy.ttl")
      File.write!(sabotaged_path, sabotaged_ttl)
      legacy_graph = Ontology.load!(sabotaged_path)

      assert Pack.declared_profile(legacy_graph) == :legacy
      assert :ok = Pack.admit_pack_manifest(dir, legacy_graph)
    end
  end

  # -- real-pipeline enforcement (the unit gate must be ON the sync path) ------

  @out_filename "out.txt"

  defp reactor_opts(pack_dir, work_dir) do
    [
      pack_dir: pack_dir,
      out: Path.join(work_dir, @out_filename),
      manifest_dir: work_dir,
      engine: "sparql",
      # `:verify` runs a real `mix compile --warnings-as-errors` subprocess;
      # point it at this repo (already compiled) instead of the bare tmp dir.
      verify_cwd: File.cwd!()
    ]
  end

  defp tmp_work_dir(tag) do
    dir =
      Path.join(
        System.tmp_dir!(),
        "ggen_igniter_pack_manifest_work_#{tag}_#{System.unique_integer([:positive])}"
      )

    File.rm_rf!(dir)
    File.mkdir_p!(dir)
    on_exit(fn -> File.rm_rf!(dir) end)
    dir
  end

  describe "ReconcileReactor.run/1 pipeline enforcement (RFC-GPACK-001 §86.1)" do
    test "a Core pack with mismatched identity refuses BEFORE any actuation, as :refused" do
      pack_dir =
        write_core_pack(tmp_pack_dir("run_mismatch"),
          manifest: strict_manifest("manifest-name"),
          ontology: core_ontology("graph-name", "Core1")
        )

      work_dir = tmp_work_dir("run_mismatch")

      assert {:error, receipt} = ReconcileReactor.run(reactor_opts(pack_dir, work_dir))
      assert receipt.standing == :refused
      assert receipt.reason =~ "REFUSED:PACK_IDENTITY_MISMATCH"
      refute File.exists?(Path.join(work_dir, @out_filename))
    end

    test "a Core pack with matching identities syncs end-to-end (admitted, :alive)" do
      pack_dir = write_core_pack(tmp_pack_dir("run_match"))
      work_dir = tmp_work_dir("run_match")

      assert {:ok, receipt} = ReconcileReactor.run(reactor_opts(pack_dir, work_dir))
      assert receipt.standing == :alive
      assert File.read!(Path.join(work_dir, @out_filename)) == "static witness body\n"
    end
  end

  describe "ReconcileReactor.plan/1 enforcement (read-only resolve-time admission)" do
    test "a Core pack with mismatched identity refuses with the typed reason" do
      pack_dir =
        write_core_pack(tmp_pack_dir("plan_mismatch"),
          manifest: strict_manifest("manifest-name"),
          ontology: core_ontology("graph-name", "Core1")
        )

      assert {:error, {:refused_pack_manifest, :pack_identity_mismatch, diagnostic}} =
               ReconcileReactor.plan(reactor_opts(pack_dir, tmp_work_dir("plan_mismatch")))

      assert diagnostic =~ "graph-name"
      assert diagnostic =~ "manifest-name"
    end

    test "a Core pack with matching identities still plans (admission passes through)" do
      pack_dir = write_core_pack(tmp_pack_dir("plan_match"))

      assert {:ok, [_pending]} =
               ReconcileReactor.plan(reactor_opts(pack_dir, tmp_work_dir("plan_match")))
    end

    test "a LEGACY pack still plans unchanged (byte-compat through the real pipeline)" do
      assert {:ok, [_pending]} =
               ReconcileReactor.plan(
                 reactor_opts("test/fixtures/sample-pack", tmp_work_dir("plan_legacy"))
               )
    end
  end
end
