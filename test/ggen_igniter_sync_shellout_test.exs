defmodule GgenIgniterSyncShelloutTest do
  @moduledoc """
  Real-collaborator, state-based tests for `GgenIgniter.SyncShellout`
  (GGEN-1805), `GgenIgniter.GateVerify` (GGEN-1806), and their orchestrator
  `GgenIgniter.SyncVerify`
  (`docs/jira/v26.9.1/04-SYNC-SHELLOUT-AND-VERIFY.md`).

  No `Mock`/`mock(`/`patch(`/`monkeypatch` anywhere in this file. Real
  `System.cmd/3` shellouts to a real, external `ggen` binary (skipped with a
  named, visible reason when it is not on `PATH` -- never silently
  substituted with a mock, per the global `testing-chicago-style.md` rule),
  real scratch consumer-project fixtures built under `System.tmp_dir!()`
  (mountable by this machine's `ggen` -> `docker run -v $PWD:/workspace`
  wrapper -- confirmed by hand: `/tmp` itself is NOT shared into the
  container on this machine, but `System.tmp_dir!()` resolves to
  `~/.cache/tmp`, which is), real `.rq` gate files under
  `test/fixtures/sync_verify/pack/gates/`, and real RDF.Graph loading +
  real SPARQL execution (`GgenIgniter.Ontology.load!/1` +
  `GgenIgniter.Query.run/2`) for the gate-verification assertions.
  """
  use ExUnit.Case, async: false

  @pack_dir Path.join(__DIR__, "fixtures/sync_verify/pack")

  defp scratch_project_dir(tag) do
    Path.join(System.tmp_dir!(), "gi04_sync_shellout_#{tag}_#{System.unique_integer([:positive])}")
  end

  defp write_project!(dir, ontology_ttl) do
    File.mkdir_p!(Path.join(dir, "templates"))

    File.write!(Path.join(dir, "ggen.toml"), """
    [project]
    name = "gi04-fixture"
    version = "0.1.0"

    [ontology]
    source = "ontology.ttl"

    [generation]
    output_dir = "."

    [[generation.rules]]
    name = "hello"
    query = { inline = \"\"\"
    PREFIX ex: <https://ggen-igniter.dev/ontology/gi04-sync-verify#>
    SELECT ?label WHERE { ?s a ex:Thing ; ex:label ?label . } ORDER BY ?label
    \"\"\" }
    template = { file = "templates/hello.tera" }
    output_file = "hello.txt"
    mode = "Overwrite"
    """)

    File.write!(Path.join(dir, "ontology.ttl"), ontology_ttl)

    File.write!(Path.join(dir, "templates/hello.tera"), """
    {% for row in sparql_results %}{{ row["label"] }}
    {% endfor %}
    """)
  end

  @ontology_with_required """
  @prefix ex: <https://ggen-igniter.dev/ontology/gi04-sync-verify#> .
  ex:t1 a ex:Thing ; ex:label "hello-world" .
  ex:rf1 a ex:RequiredField .
  """

  @ontology_without_required """
  @prefix ex: <https://ggen-igniter.dev/ontology/gi04-sync-verify#> .
  ex:t1 a ex:Thing ; ex:label "hello-world" .
  """

  describe "GgenIgniter.SyncShellout.run/2 (GGEN-1805)" do
    @describetag :integration

    test "chained-failure gating: upstream_ok?: false never invokes the subprocess" do
      dir = scratch_project_dir("gate")
      write_project!(dir, @ontology_without_required)
      on_exit(fn -> File.rm_rf!(dir) end)

      assert GgenIgniter.SyncShellout.run(dir, upstream_ok?: false) == {:error, :upstream_failed}

      # Real, observable state signal: the pipeline's real output file was
      # never written, because the subprocess was never invoked.
      refute File.exists?(Path.join(dir, "hello.txt"))
    end

    test "real invocation and capture against a real ggen binary, pinned to the fixture's own cwd" do
      if System.find_executable("ggen") do
        dir = scratch_project_dir("real")
        write_project!(dir, @ontology_with_required)
        on_exit(fn -> File.rm_rf!(dir) end)

        assert {:ok, output} = GgenIgniter.SyncShellout.run(dir)
        assert output =~ "hello.txt"

        # Proves cd: genuinely pinned execution to the fixture project root,
        # not this test's own process cwd -- the real output file exists at
        # the fixture path and nowhere else.
        assert File.exists?(Path.join(dir, "hello.txt"))
        assert File.read!(Path.join(dir, "hello.txt")) =~ "hello-world"
        refute File.exists?(Path.join(File.cwd!(), "hello.txt"))
      else
        IO.puts(
          "SKIPPED: \"real invocation and capture against a real ggen binary\" -- " <>
            "no `ggen` binary on PATH (named, visible skip, no mock substitution)."
        )
      end
    end

    test "a real nonzero exit (malformed ggen.toml) is surfaced as a typed error, not swallowed" do
      if System.find_executable("ggen") do
        dir = scratch_project_dir("broken")
        File.mkdir_p!(dir)
        on_exit(fn -> File.rm_rf!(dir) end)

        # Deliberately malformed: [project] table present but no
        # project.version -- confirmed by hand (see this ticket's own
        # investigation) to make the real ggen binary refuse with
        # FM-CONFIG-101 (ambiguous schema) and a nonzero exit code.
        File.write!(Path.join(dir, "ggen.toml"), """
        [project]
        name = "gi04-broken-fixture"

        [ontology]
        source = "ontology.ttl"

        [generation]
        output_dir = "."

        [[generation.rules]]
        name = "hello"
        query = { inline = "SELECT * WHERE { ?s ?p ?o }" }
        template = { file = "templates/hello.tera" }
        output_file = "hello.txt"
        """)

        File.write!(Path.join(dir, "ontology.ttl"), @ontology_with_required)

        assert {:error, {code, output}} = GgenIgniter.SyncShellout.run(dir)
        assert is_integer(code)
        assert code != 0
        assert output =~ "config error" or output =~ "CONFIG"
        refute File.exists?(Path.join(dir, "hello.txt"))
      else
        IO.puts(
          "SKIPPED: \"a real nonzero exit is surfaced as a typed error\" -- " <>
            "no `ggen` binary on PATH (named, visible skip, no mock substitution)."
        )
      end
    end
  end

  describe "GgenIgniter.GateVerify.run/2 (GGEN-1806)" do
    test "per-gate results: both fixture gates pass against an ontology containing both required shapes" do
      dir = scratch_project_dir("gates_pass")
      File.mkdir_p!(dir)
      on_exit(fn -> File.rm_rf!(dir) end)
      ontology_path = Path.join(dir, "ontology.ttl")
      File.write!(ontology_path, @ontology_with_required)

      assert {:ok, results} = GgenIgniter.GateVerify.run(@pack_dir, ontology_path)

      assert results == [
               {"thing_present", :pass},
               {"required_field_present", :pass}
             ]
    end

    test "named refusal on a broken gate: the specific failed gate is named, not a generic error" do
      dir = scratch_project_dir("gates_fail")
      File.mkdir_p!(dir)
      on_exit(fn -> File.rm_rf!(dir) end)
      ontology_path = Path.join(dir, "ontology.ttl")
      File.write!(ontology_path, @ontology_without_required)

      assert GgenIgniter.GateVerify.run(@pack_dir, ontology_path) ==
               {:error, {:gate_failed, "required_field_present"}}
    end
  end

  describe "GgenIgniter.SyncVerify.run/3 -- orchestrator (distinguishable success levels)" do
    test "upstream gating refusal propagates unchanged, gates never run" do
      dir = scratch_project_dir("orchestrator_gated")
      write_project!(dir, @ontology_with_required)
      on_exit(fn -> File.rm_rf!(dir) end)

      assert GgenIgniter.SyncVerify.run(dir, @pack_dir, upstream_ok?: false) ==
               {:error, :upstream_failed}
    end

    if System.find_executable("ggen") do
      test "generated-and-gate-verified is a distinct, pattern-matchable success from generated-only" do
        dir = scratch_project_dir("orchestrator_ok")
        write_project!(dir, @ontology_with_required)
        on_exit(fn -> File.rm_rf!(dir) end)

        assert {:ok, %{sync: sync_output, gates: gate_results}} =
                 GgenIgniter.SyncVerify.run(dir, @pack_dir)

        assert is_binary(sync_output)
        assert gate_results == [
                 {"thing_present", :pass},
                 {"required_field_present", :pass}
               ]
      end

      test "a sync success followed by a gate failure is distinguishable from a sync failure" do
        dir = scratch_project_dir("orchestrator_gate_fail")
        write_project!(dir, @ontology_without_required)
        on_exit(fn -> File.rm_rf!(dir) end)

        assert GgenIgniter.SyncVerify.run(dir, @pack_dir) ==
                 {:error, {:gate_failed, "required_field_present"}}
      end
    end
  end
end
