defmodule Mix.Tasks.GgenIgniter.HandAuthoredTaskTest do
  @moduledoc """
  Chicago-style tests for `mix ggen_igniter.hand_authored` (see
  `lib/mix/tasks/ggen_igniter.hand_authored.ex`): real `System.cmd("mix", ...)`
  subprocesses against ONE real, freshly-scaffolded consumer project (built
  once in `setup_all`, `mix deps.get` + compile included -- the same cost
  model as `ggen_igniter_doctor_fix_e2e_test.exs`), whose ontology.ttl and
  admitted files are really written and really re-read by the task on every
  invocation. No mocks anywhere: the pack vocabulary is a real fixture pack
  (small ceilings so the ceiling law is reachable), the SPARQL law queries
  really run through the real oxigraph NIF, sha256 is really computed over
  real bytes, and every refusal is observed through the subprocess's real
  exit code + typed `REFUSED_*` line.

  The render leg is deliberately exercised with `--no-render` here (the
  scratch consumer has no ggen.toml; the render's force-scaffold + `ggen sync
  run` + restore procedure is proven on the real beam4pm consumer, see the
  task's moduledoc and WAVE-RECEIPT).
  """
  use ExUnit.Case, async: false

  @moduletag :integration
  # Real `mix deps.get` + a real path-dependency compile of ggen_igniter
  # itself (including the Rust oxigraph NIF) -- genuinely slow, once per run.
  @moduletag timeout: 900_000

  @ggen_igniter_path Path.expand("..", __DIR__)

  @gate_050 ~s|# MESSAGE: every bpm:HandAuthoredSource must carry bpm:sourcePath, bpm:authorshipKind, bpm:authorizingPrincipal, bpm:admissionReason, bpm:acceptanceCommand and bpm:admittedAtCommit, and every one whose bpm:AuthorshipKind counts as debt must also carry bpm:contentSha256, bpm:admissionExpires and bpm:sunsetPlan; any row is a refusal.
PREFIX bpm: <https://ggen.dev/ontology/beam-process-model#>
SELECT ?subject ?missing WHERE {
  {
    ?subject a bpm:HandAuthoredSource .
    VALUES ?missing { bpm:sourcePath bpm:authorshipKind bpm:authorizingPrincipal bpm:admissionReason bpm:acceptanceCommand bpm:admittedAtCommit }
  } UNION {
    ?subject a bpm:HandAuthoredSource ;
             bpm:authorshipKind ?kind .
    ?kind bpm:countsAsDebt "true" .
    VALUES ?missing { bpm:contentSha256 bpm:admissionExpires bpm:sunsetPlan }
  }
  FILTER NOT EXISTS { ?subject ?missing ?value }
}
ORDER BY ?subject ?missing|

  @gate_060 ~s|# MESSAGE: every bpm:HandAuthoredSource must name an admitted bpm:AuthorshipKind and no two individuals may admit the same bpm:sourcePath; any row is a refusal.
PREFIX bpm: <https://ggen.dev/ontology/beam-process-model#>
SELECT ?subject ?problem WHERE {
  {
    ?subject a bpm:HandAuthoredSource ;
             bpm:authorshipKind ?kind .
    FILTER NOT EXISTS {
      ?kind a bpm:AuthorshipKind ;
            bpm:authorshipKindName ?kind_name ;
            bpm:countsAsDebt ?counts_as_debt ;
            bpm:debtCeiling ?ceiling .
    }
    BIND("authorship_kind_not_admitted" AS ?problem)
  } UNION {
    ?subject a bpm:HandAuthoredSource ;
             bpm:sourcePath ?path .
    ?other a bpm:HandAuthoredSource ;
           bpm:sourcePath ?path .
    FILTER (?other != ?subject)
    BIND("duplicate_source_path" AS ?problem)
  }
}
ORDER BY ?subject ?problem|

  @gate_070 ~s|# MESSAGE: the number of bpm:HandAuthoredSource individuals naming one bpm:AuthorshipKind must not exceed that kind's bpm:debtCeiling; any row is a refusal.
PREFIX bpm: <https://ggen.dev/ontology/beam-process-model#>
SELECT ?kind ?ceiling (COUNT(?subject) AS ?admitted) WHERE {
  ?subject a bpm:HandAuthoredSource ;
           bpm:authorshipKind ?kind .
  ?kind bpm:debtCeiling ?ceiling .
}
GROUP BY ?kind ?ceiling
HAVING (COUNT(?subject) > ?ceiling)
ORDER BY ?kind|

  @pack_ontology """
  @prefix bpm: <https://ggen.dev/ontology/beam-process-model#> .
  @prefix rdf: <http://www.w3.org/1999/02/22-rdf-syntax-ns#> .
  @prefix rdfs: <http://www.w3.org/2000/01/rdf-schema#> .
  @prefix xsd: <http://www.w3.org/2001/XMLSchema#> .

  bpm:AuthorshipKind a rdfs:Class .
  bpm:authorshipKindName a rdf:Property ; rdfs:domain bpm:AuthorshipKind ; rdfs:range xsd:string .
  bpm:authorshipKindDoc a rdf:Property ; rdfs:domain bpm:AuthorshipKind ; rdfs:range xsd:string .
  bpm:countsAsDebt a rdf:Property ; rdfs:domain bpm:AuthorshipKind ; rdfs:range xsd:string .
  bpm:debtCeiling a rdf:Property ; rdfs:domain bpm:AuthorshipKind ; rdfs:range xsd:integer .
  bpm:HandAuthoredSource a rdfs:Class .
  bpm:sourcePath a rdf:Property ; rdfs:domain bpm:HandAuthoredSource ; rdfs:range xsd:string .
  bpm:authorshipKind a rdf:Property ; rdfs:domain bpm:HandAuthoredSource ; rdfs:range bpm:AuthorshipKind .
  bpm:authorizingPrincipal a rdf:Property ; rdfs:domain bpm:HandAuthoredSource ; rdfs:range xsd:string .
  bpm:admissionReason a rdf:Property ; rdfs:domain bpm:HandAuthoredSource ; rdfs:range xsd:string .
  bpm:acceptanceCommand a rdf:Property ; rdfs:domain bpm:HandAuthoredSource ; rdfs:range xsd:string .
  bpm:acceptancePrerequisite a rdf:Property ; rdfs:domain bpm:HandAuthoredSource ; rdfs:range xsd:string .
  bpm:contentSha256 a rdf:Property ; rdfs:domain bpm:HandAuthoredSource ; rdfs:range xsd:string .
  bpm:admittedAtCommit a rdf:Property ; rdfs:domain bpm:HandAuthoredSource ; rdfs:range xsd:string .
  bpm:admissionExpires a rdf:Property ; rdfs:domain bpm:HandAuthoredSource ; rdfs:range xsd:string .
  bpm:sunsetPlan a rdf:Property ; rdfs:domain bpm:HandAuthoredSource ; rdfs:range xsd:string .

  bpm:AuthorshipKind_hand_authored_qualification a bpm:AuthorshipKind ;
      bpm:authorshipKindName "hand_authored_qualification" ;
      bpm:countsAsDebt "true" ;
      bpm:debtCeiling 2 ;
      bpm:authorshipKindDoc "Test fixture kind: debt, ceiling 2." .

  bpm:AuthorshipKind_native_engine_facade a bpm:AuthorshipKind ;
      bpm:authorshipKindName "native_engine_facade" ;
      bpm:countsAsDebt "true" ;
      bpm:debtCeiling 1 ;
      bpm:authorshipKindDoc "Test fixture kind: debt, ceiling 1." .

  bpm:AuthorshipKind_reference_evidence a bpm:AuthorshipKind ;
      bpm:authorshipKindName "reference_evidence" ;
      bpm:countsAsDebt "false" ;
      bpm:debtCeiling 4 ;
      bpm:authorshipKindDoc "Test fixture kind: not debt." .
  """

  # The seed consumer graph admits ONE file up front (lib/seed.ex, the
  # qualification kind at 1/2) so every graph-law query has something real to
  # chew on from the first invocation. The seed is a COMPLETE debt row --
  # including the real sha256 of the seed file's bytes -- so the graph is
  # lawful (0 gate rows) before any test plants a violation; every test's
  # `setup` resets the ontology to exactly this state.
  defp seed_ontology(seed_sha) do
    """
    @prefix bpm: <https://ggen.dev/ontology/beam-process-model#> .
    @prefix bap: <https://ggen.dev/projects/scratch#> .

    bap:hand_authored_lib_seed a bpm:HandAuthoredSource ;
        bpm:sourcePath "lib/seed.ex" ;
        bpm:authorshipKind bpm:AuthorshipKind_hand_authored_qualification ;
        bpm:authorizingPrincipal "Test seed principal" ;
        bpm:admissionReason "Seed admission so the graph is never empty." ;
        bpm:acceptanceCommand "true" ;
        bpm:contentSha256 "#{seed_sha}" ;
        bpm:admittedAtCommit "seed000" ;
        bpm:admissionExpires "2099-12-31" ;
        bpm:sunsetPlan "Retire with the fixture." .
    """
  end

  setup_all do
    dir =
      Path.join(
        System.tmp_dir!(),
        "ggen_igniter_hand_authored_task_#{System.unique_integer([:positive])}"
      )

    File.rm_rf!(dir)
    File.mkdir_p!(Path.join(dir, "lib"))
    File.mkdir_p!(Path.join(dir, "test/support"))
    File.mkdir_p!(Path.join(dir, "docs/reference"))
    File.mkdir_p!(Path.join(dir, "pack/gates"))

    File.write!(Path.join(dir, "mix.exs"), """
    defmodule ScratchConsumer.MixProject do
      use Mix.Project

      def project do
        [
          app: :scratch_consumer,
          version: "0.1.0",
          elixir: "~> 1.17",
          deps: [{:ggen_igniter, path: #{@ggen_igniter_path |> inspect()}}]
        ]
      end
    end
    """)

    File.write!(Path.join(dir, "pack/ontology.ttl"), @pack_ontology)

    File.write!(
      Path.join(dir, "pack/gates/050_hand_authored_source_required.rq"),
      @gate_050 <> "\n"
    )

    File.write!(
      Path.join(dir, "pack/gates/060_hand_authored_source_kind_admitted.rq"),
      @gate_060 <> "\n"
    )

    File.write!(
      Path.join(dir, "pack/gates/070_hand_authored_source_ceiling.rq"),
      @gate_070 <> "\n"
    )

    File.write!(Path.join(dir, "lib/seed.ex"), """
    defmodule Scratch.Seed do
      def hi, do: :hi
    end
    """)

    # The seed admission carries the REAL sha256 of the seed file's bytes, so
    # the seed graph is genuinely lawful (0 gate rows), not lawful-by-fiat.
    seed_sha =
      :crypto.hash(:sha256, File.read!(Path.join(dir, "lib/seed.ex")))
      |> Base.encode16(case: :lower)

    reset_ontology!(dir, seed_sha)

    cmd!("mix", ["deps.get"], cd: dir)
    cmd!("mix", ["compile"], cd: dir)

    on_exit(fn -> File.rm_rf!(dir) end)

    {:ok, dir: dir, seed_sha: seed_sha}
  end

  defp reset_ontology!(dir, seed_sha) do
    File.write!(Path.join(dir, "ontology.ttl"), seed_ontology(seed_sha))
  end

  defp write_file!(dir, rel, content) do
    path = Path.join(dir, rel)
    File.mkdir_p!(Path.dirname(path))
    File.write!(path, content)
    rel
  end

  defp cmd!(command, args, opts) do
    {output, status} = System.cmd(command, args, Keyword.merge([stderr_to_stdout: true], opts))
    {output, status}
  end

  defp run_task(dir, args) do
    # Every invocation names the fixture pack explicitly: the task's default
    # pack location is the reference consumer's vendored path, which the
    # scratch consumer deliberately does not have.
    cmd!("mix", ["ggen_igniter.hand_authored" | args ++ ["--pack-dir", "pack"]], cd: dir)
  end

  defp admit_args(overrides) do
    # An even-length [flag, value, ...] pairs list; overrides may drop a
    # default flag-pair ({:drop, "--file"}) or append raw args (a bare flag
    # string, or a {flag, value} pair). --no-render is appended AFTER the
    # reduce (never inside the pairs list) so a dropped pair can never
    # misalign it.
    base = [
      "--file",
      "test/admitted_test.exs",
      "--kind",
      "hand_authored_qualification",
      "--principal",
      "Test principal",
      "--reason",
      "Test reason",
      "--acceptance-command",
      "true",
      "--admitted-at-commit",
      "test0001",
      "--sunset-plan",
      "Test sunset plan",
      "--expires",
      "2099-12-31"
    ]

    {pairs, extra} =
      Enum.reduce(overrides, {base, []}, fn
        {:drop, flag}, {pairs, extra} ->
          index = Enum.find_index(pairs, &(&1 == flag))

          if index do
            {pairs |> List.delete_at(index + 1) |> List.delete_at(index), extra}
          else
            {pairs, extra}
          end

        {flag, value}, {pairs, extra} when is_binary(flag) and is_binary(value) ->
          {pairs, extra ++ [flag, value]}

        flag, {pairs, extra} when is_binary(flag) ->
          {pairs, extra ++ [flag]}
      end)

    pairs ++ extra ++ ["--no-render"]
  end

  setup %{dir: dir} = ctx do
    # A fresh ontology per test: every graph-law count starts from the same
    # seed state, so ceiling / duplicate arithmetic is deterministic.
    reset_ontology!(dir, ctx.seed_sha)

    write_file!(
      dir,
      "test/admitted_test.exs",
      "defmodule Scratch.AdmittedTest do\n  use ExUnit.Case\n  test \"truth\", do: assert true\nend\n"
    )

    {:ok, Map.put(ctx, :ontology_path, Path.join(dir, "ontology.ttl"))}
  end

  # =========================================================================
  # admit -- happy paths
  # =========================================================================

  describe "admit happy path (debt kind)" do
    test "writes the individual with the real sha256 and reports the admission", %{
      dir: dir,
      ontology_path: ontology_path
    } do
      {output, 0} = run_task(dir, ["admit" | admit_args([])])

      assert output =~ "✔ ADMITTED: test/admitted_test.exs"
      assert output =~ "hand_authored_qualification (debt) count 2/2"
      assert output =~ "[AT CEILING]"

      expected_sha =
        :crypto.hash(:sha256, File.read!(Path.join(dir, "test/admitted_test.exs")))
        |> Base.encode16(case: :lower)

      content = File.read!(ontology_path)
      assert content =~ "bpm:sourcePath \"test/admitted_test.exs\""
      assert content =~ ~s(bpm:contentSha256 "#{expected_sha}")
      assert content =~ "bpm:admittedAtCommit \"test0001\""
      assert content =~ "bpm:admissionExpires \"2099-12-31\""

      # The edited ontology still parses and the new row is queryable --
      # `list` really re-runs the pack gates over it.
      {list_output, 0} = run_task(dir, ["list"])
      assert list_output =~ "admitted: 2 (2 counted as manufacturing debt)"
      assert list_output =~ "test/admitted_test.exs"
    end

    test "inserts after the LAST existing individual, and the file stays parseable", %{
      dir: dir,
      ontology_path: ontology_path
    } do
      {_, 0} = run_task(dir, ["admit" | admit_args([])])
      content = File.read!(ontology_path)

      seed_index =
        content |> :binary.match("bap:hand_authored_lib_seed a bpm:HandAuthoredSource") |> elem(0)

      new_index = content |> :binary.match("bpm:sourcePath \"test/admitted_test.exs\"") |> elem(0)
      assert new_index > seed_index

      {list_output, 0} = run_task(dir, ["list"])
      assert list_output =~ "LIST: OK -- 2 admitted, 0 gate rows"
    end
  end

  describe "admit happy path (non-debt kind)" do
    test "emits no sha/expiry/sunset and still passes the gates", %{
      dir: dir,
      ontology_path: ontology_path
    } do
      write_file!(dir, "docs/reference/fixture.md", "# Fixture reference\n")

      {output, 0} =
        run_task(
          dir,
          [
            "admit",
            "--file",
            "docs/reference/fixture.md",
            "--kind",
            "reference_evidence",
            "--principal",
            "Test principal",
            "--reason",
            "A lawful reference doc",
            "--acceptance-command",
            "true",
            "--admitted-at-commit",
            "test0001",
            "--no-render"
          ]
        )

      assert output =~ "✔ ADMITTED: docs/reference/fixture.md"
      assert output =~ "reference_evidence (not debt)"

      content = File.read!(ontology_path)
      assert content =~ "bpm:sourcePath \"docs/reference/fixture.md\""

      # The fixture.md individual's own block carries no debt fields.
      block =
        content
        |> String.split("bpm:sourcePath \"docs/reference/fixture.md\"")
        |> List.last()
        |> String.split("\n\n")
        |> List.first()

      refute block =~ "contentSha256"
      refute block =~ "admissionExpires"
      refute block =~ "sunsetPlan"

      {list_output, 0} = run_task(dir, ["list"])
      assert list_output =~ "reference_evidence"
    end
  end

  # =========================================================================
  # admit -- typed refusals (nothing written)
  # =========================================================================

  describe "admit refusals" do
    test "REFUSED_FILE_NOT_FOUND", %{dir: dir} do
      {output, 1} =
        run_task(dir, ["admit" | admit_args([{:drop, "--file"}, "--file", "test/nope.exs"])])

      assert output =~ "REFUSED_FILE_NOT_FOUND: test/nope.exs"
    end

    test "REFUSED_MARKED_FILE", %{dir: dir} do
      write_file!(
        dir,
        "test/marked_test.exs",
        "# GENERATED by ggen from ontology.ttl. Do not edit.\ndefmodule M, do: nil\n"
      )

      {output, 1} =
        run_task(dir, [
          "admit" | admit_args([{:drop, "--file"}, "--file", "test/marked_test.exs"])
        ])

      assert output =~ "REFUSED_MARKED_FILE: test/marked_test.exs"
    end

    test "REFUSED_MISSCOPED", %{dir: dir} do
      write_file!(dir, "stray.exs", "# not under any manufactured root\n")

      {output, 1} =
        run_task(dir, ["admit" | admit_args([{:drop, "--file"}, "--file", "stray.exs"])])

      assert output =~ "REFUSED_MISSCOPED: stray.exs"
    end

    test "REFUSED_UNKNOWN_KIND", %{dir: dir} do
      {output, 1} =
        run_task(dir, ["admit" | admit_args([{:drop, "--kind"}, "--kind", "bogus_kind"])])

      assert output =~ "REFUSED_UNKNOWN_KIND"
      assert output =~ "bogus_kind"
    end

    test "REFUSED_MISSING_SUNSET_PLAN for a debt kind", %{dir: dir} do
      {output, 1} = run_task(dir, ["admit" | admit_args([{:drop, "--sunset-plan"}])])
      assert output =~ "REFUSED_MISSING_SUNSET_PLAN"
    end

    test "REFUSED_MISSING_EXPIRY for a debt kind", %{dir: dir} do
      {output, 1} = run_task(dir, ["admit" | admit_args([{:drop, "--expires"}])])
      assert output =~ "REFUSED_MISSING_EXPIRY"
    end

    test "REFUSED_INVALID_EXPIRY", %{dir: dir} do
      {output, 1} =
        run_task(dir, ["admit" | admit_args([{:drop, "--expires"}, "--expires", "31/12/2099"])])

      assert output =~ "REFUSED_INVALID_EXPIRY"
      assert output =~ "31/12/2099"
    end

    test "REFUSED_MISSING_ACCEPTANCE_COMMAND", %{dir: dir} do
      {output, 1} = run_task(dir, ["admit" | admit_args([{:drop, "--acceptance-command"}])])
      assert output =~ "REFUSED_MISSING_ACCEPTANCE_COMMAND"
    end

    test "REFUSED_DUPLICATE_SOURCE_PATH", %{dir: dir} do
      {output, 1} =
        run_task(dir, ["admit" | admit_args([{:drop, "--file"}, "--file", "lib/seed.ex"])])

      assert output =~ "REFUSED_DUPLICATE_SOURCE_PATH"
      assert output =~ "lib/seed.ex is already admitted"
    end

    test "REFUSED_CEILING_EXCEEDED: the second admission past a kind's ceiling is refused", %{
      dir: dir
    } do
      write_file!(dir, "lib/facade.ex", "defmodule Scratch.Facade, do: nil\n")

      # native_engine_facade ceiling is 1: first facade admit is lawful...
      {output1, 0} =
        run_task(
          dir,
          [
            "admit",
            "--file",
            "lib/facade.ex",
            "--kind",
            "native_engine_facade",
            "--principal",
            "Test principal",
            "--reason",
            "Test reason",
            "--acceptance-command",
            "true",
            "--sunset-plan",
            "Render from engine facts",
            "--expires",
            "2099-12-31",
            "--admitted-at-commit",
            "test0001",
            "--no-render"
          ]
        )

      assert output1 =~ "✔ ADMITTED: lib/facade.ex"

      # ...the second is gate-070 refused before anything is written.
      write_file!(dir, "lib/facade2.ex", "defmodule Scratch.Facade2, do: nil\n")

      {output2, 1} =
        run_task(
          dir,
          [
            "admit",
            "--file",
            "lib/facade2.ex",
            "--kind",
            "native_engine_facade",
            "--principal",
            "Test principal",
            "--reason",
            "Test reason",
            "--acceptance-command",
            "true",
            "--sunset-plan",
            "Render from engine facts",
            "--expires",
            "2099-12-31",
            "--admitted-at-commit",
            "test0001",
            "--no-render"
          ]
        )

      assert output2 =~ "REFUSED_CEILING_EXCEEDED"
      assert output2 =~ "would hold 2 admitted files against its bpm:debtCeiling 1"
    end

    test "REFUSED_MISSING_FIELD for a missing principal", %{dir: dir} do
      {output, 1} = run_task(dir, ["admit" | admit_args([{:drop, "--principal"}])])
      assert output =~ "REFUSED_MISSING_FIELD"
      assert output =~ "bpm:authorizingPrincipal"
    end
  end

  # =========================================================================
  # admit -- invalid invocation
  # =========================================================================

  describe "invalid invocation" do
    test "exits 2 with no verb", %{dir: dir} do
      # No --pack-dir injection here: this invocation has no flags at all, so
      # the verb extractor sees the bare (empty) positional list.
      {output, 2} = cmd!("mix", ["ggen_igniter.hand_authored"], cd: dir)
      assert output =~ "no verb given"
    end

    test "exits 2 on an unknown verb", %{dir: dir} do
      {output, 2} = run_task(dir, ["frobnicate"])
      assert output =~ "unknown verb"
    end

    test "exits 2 on an unknown flag", %{dir: dir} do
      {output, 2} = run_task(dir, ["list", "--bogus-flag"])
      assert output =~ "unknown flag"
    end

    test "exits 2 when admit omits --kind", %{dir: dir} do
      {output, 2} = run_task(dir, ["admit" | admit_args([{:drop, "--kind"}])])
      assert output =~ "admit requires --kind"
    end
  end

  # =========================================================================
  # admit -- dry run
  # =========================================================================

  # =========================================================================
  # no-trailing-newline ontology (real falsifier found by the beam4pm replay)
  # =========================================================================

  # The reference consumer's own ontology.ttl does NOT end in a trailing
  # newline. The first admit writes fine, but the file then ends on the new
  # block's terminating "." with nothing after it; the SECOND admit must
  # still anchor correctly (this used to crash insert_individual/2 with a
  # MatchError, observed for real during the v26.9.18 replay).
  test "two sequential admits against a file with no trailing newline", %{
    dir: dir,
    ontology_path: ontology_path
  } do
    File.write!(
      ontology_path,
      String.trim_trailing(seed_ontology("seed_sha_placeholder_value_not_verified"), "\n")
    )

    {output1, 0} = run_task(dir, ["admit" | admit_args([])])
    assert output1 =~ "✔ ADMITTED: test/admitted_test.exs"

    write_file!(dir, "lib/second.ex", "defmodule Scratch.Second, do: nil\n")

    {output2, 0} =
      run_task(
        dir,
        [
          "admit",
          "--file",
          "lib/second.ex",
          "--kind",
          "reference_evidence",
          "--principal",
          "Test principal",
          "--reason",
          "Second admission",
          "--acceptance-command",
          "true",
          "--admitted-at-commit",
          "test0002",
          "--no-render"
        ]
      )

    assert output2 =~ "✔ ADMITTED: lib/second.ex"

    {list_output, 0} = run_task(dir, ["list"])
    assert list_output =~ "LIST: OK -- 3 admitted, 0 gate rows"
    assert File.read!(ontology_path) =~ "bpm:sourcePath \"lib/second.ex\""
  end

  test "admit --dry-run validates for real and writes nothing", %{
    dir: dir,
    ontology_path: ontology_path
  } do
    before = File.read!(ontology_path)

    {output, 0} = run_task(dir, ["admit" | admit_args(["--dry-run"])])
    assert output =~ "DRY-RUN: no files written, nothing rendered"
    assert output =~ "would append bap:hand_authored_test_admitted_test_exs"
    assert File.read!(ontology_path) == before
  end

  # =========================================================================
  # list
  # =========================================================================

  describe "list" do
    test "reports the seeded graph as lawful (0 gate rows)", %{dir: dir} do
      {output, 0} = run_task(dir, ["list"])
      assert output =~ "admitted: 1 (1 counted as manufacturing debt)"
      assert output =~ "hand_authored_qualification"
      assert output =~ "050_hand_authored_source_required"
      assert output =~ "LIST: OK -- 1 admitted, 0 gate rows"
    end

    test "exits 1 when the graph itself violates gate 050", %{
      dir: dir,
      ontology_path: ontology_path,
      seed_sha: seed_sha
    } do
      # A debt-kind individual with NO sha/expiry/sunset: gate 050 must flag it.
      bad =
        seed_ontology(seed_sha) <>
          "\n  bap:hand_authored_bad a bpm:HandAuthoredSource ;\n      bpm:sourcePath \"lib/seed.ex\" ;\n      bpm:authorshipKind bpm:AuthorshipKind_hand_authored_qualification ;\n      bpm:authorizingPrincipal \"x\" ;\n      bpm:admissionReason \"x\" ;\n      bpm:acceptanceCommand \"true\" ;\n      bpm:admittedAtCommit \"bad0000\" .\n"

      File.write!(ontology_path, bad)

      {output, 1} = run_task(dir, ["list"])
      assert output =~ "050_hand_authored_source_required"
      # Gate 050 emits one row PER MISSING PROPERTY: the planted bad
      # individual is a debt-kind admission with no contentSha256, no
      # admissionExpires and no sunsetPlan -> exactly 3 rows; the complete
      # seed individual emits none.
      assert output =~ "3 row(s)"
      assert output =~ "LIST: FAIL"
    end
  end

  # =========================================================================
  # check
  # =========================================================================

  describe "check" do
    test "passes through a passing gate script", %{dir: dir} do
      script = Path.join(dir, "passing_gate.sh")
      File.write!(script, "#!/usr/bin/env bash\necho \"GATE: PASS\"\nexit 0\n")

      {output, 0} = run_task(dir, ["check", "--gate-script", "passing_gate.sh"])
      assert output =~ "GATE: PASS"
      assert output =~ "gate PASSED (exit 0)"
    end

    test "exits with a failing gate script's own code", %{dir: dir} do
      script = Path.join(dir, "failing_gate.sh")
      File.write!(script, "#!/usr/bin/env bash\necho \"REFUSED_TEST: nope\" >&2\nexit 3\n")

      {output, 3} = run_task(dir, ["check", "--gate-script", "failing_gate.sh"])
      assert output =~ "REFUSED_TEST: nope"
      assert output =~ "gate FAILED (exit 3)"
    end

    test "refuses a missing gate script", %{dir: dir} do
      {output, 1} = run_task(dir, ["check", "--gate-script", "nope.sh"])
      assert output =~ "REFUSED_GATE_SCRIPT_NOT_FOUND"
    end
  end

  # =========================================================================
  # --no-render + TTL escaping
  # =========================================================================

  test "values with double quotes are Turtle-escaped and stay parseable", %{dir: dir} do
    {output, 0} =
      run_task(
        dir,
        [
          "admit",
          "--file",
          "test/admitted_test.exs",
          "--kind",
          "hand_authored_qualification",
          "--principal",
          "Principal with \"quotes\" and back\\slash",
          "--reason",
          "Reason \"quoted\" text",
          "--acceptance-command",
          "mix test \"quoted path\"",
          "--sunset-plan",
          "Plan with \"quotes\"",
          "--expires",
          "2099-12-31",
          "--admitted-at-commit",
          "test0001",
          "--no-render"
        ]
      )

    assert output =~ "✔ ADMITTED: test/admitted_test.exs"

    # The real proof the escaping is right: the ontology still parses and the
    # gates still run over it.
    {list_output, 0} = run_task(dir, ["list"])
    assert list_output =~ "LIST: OK -- 2 admitted, 0 gate rows"
  end
end
