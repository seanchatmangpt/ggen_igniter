defmodule GgenIgniterFortune5ReadyTaskTest do
  @moduledoc """
  Chicago-style, real-collaborator, state-based end-to-end tests for
  `mix ggen_igniter.fortune5_ready` (GGEN-1807,
  `docs/jira/v26.9.1/05-FORTUNE5-READY-MIX-TASK-AND-E2E-TEST.md`) -- the
  assembled pipeline over tickets 01 (`GgenIgniter.SchemaDispatch`), 02
  (`GgenIgniter.GgenToml.IO`), 03 (`GgenIgniter.Bundle`), and 04
  (`GgenIgniter.SyncShellout`/`GateVerify`/`SyncVerify`).

  No `Mock`/`mock(`/`patch(`/`monkeypatch` anywhere in this file. The task
  is invoked for real via `Igniter.compose_task/3` against a real
  `%Igniter{}` (`Igniter.Test.test_project/1`, this app's own real
  igniter-mix-task test machinery, same as
  `test/ggen_igniter_install_task_test.exs`) -- but this task's own
  side-effectful work (`ggen.toml` write-back, the `ggen sync run`
  subprocess) targets a real **external scratch project fixture**, not the
  in-memory igniter project, per the ticket's own scoping: a minimal
  `mix.exs` is not enough on its own to exercise the target-project
  pipeline, so every scratch fixture below is a real directory tree
  written to disk via `System.tmp_dir!()` (mountable by this machine's
  `ggen` -> `docker run -v $PWD:/workspace` wrapper -- confirmed by hand in
  `test/ggen_igniter_sync_shellout_test.exs`: `/tmp` itself is NOT shared
  into the container on this machine, but `System.tmp_dir!()` resolves to
  `~/.cache/tmp`, which is), read back with real `File.read!/1` after the
  task runs, and re-parsed with the real `GgenIgniter.SchemaDispatch.load/1`
  pipeline (never a hand-typed string asserted against in memory).

  The three real end-to-end cases required by the ticket:

    1. Frontmatter (`[templates].dir`, `[packs]` table-of-tables) schema --
       the schema real consumers like beam4pm actually use, exercised
       first and by default.
    2. DeclarativeRules (`[[generation.rules]]` non-empty, `[[packs]]`
       array-of-tables) schema -- proves dispatch genuinely branches on
       ticket 01's classifier rather than hard-coding the Frontmatter
       default.
    3. A negative case -- a real gate failure -- proving the task reports
       failure (`Igniter.add_issue/2`, no success notice) rather than
       reporting partial success as success.

  A real `ggen` binary is required for the sync-shellout steps in every
  case (skipped with a named, visible reason when `ggen` is not on `PATH`
  -- never silently substituted with a mock, per
  `~/.claude/rules/testing-chicago-style.md`'s worked example).
  """

  use ExUnit.Case, async: false
  import Igniter.Test

  @bundle_path Path.join(__DIR__, "fixtures/fortune5_ready/bundle.json")
  @pack_dir Path.join(__DIR__, "fixtures/fortune5_ready/pack")

  defp scratch_project_dir(tag) do
    Path.join(
      System.tmp_dir!(),
      "gi05_fortune5_ready_#{tag}_#{System.unique_integer([:positive])}"
    )
  end

  defp run_task!(scratch_dir, extra_argv \\ []) do
    argv = ["--path", scratch_dir, "--bundle-path", @bundle_path] ++ extra_argv

    test_project()
    |> Igniter.compose_task("ggen_igniter.fortune5_ready", argv)
  end

  @ontology_with_thing """
  @prefix ex: <https://ggen-igniter.dev/ontology/gi05-fortune5#> .
  ex:t1 a ex:Thing .
  """

  @ontology_without_thing """
  @prefix ex: <https://ggen-igniter.dev/ontology/gi05-fortune5#> .
  ex:t1 a ex:NotAThing .
  """

  # `ggen sync run` fully resolves every `[packs]`/`[[packs]]` entry it
  # sees, whether or not any generation rule actually references it --
  # confirmed by hand against the real binary: a bare empty directory
  # fails `FM-PACK-002` ("pack.toml unreadable"), and a real pack root
  # requires `pack.toml` + `ontology.ttl` + at least one `templates/*.tmpl`
  # file (`~/ggen/crates/ggen-engine/src/pack.rs`'s own moduledoc). Every
  # pack path this fixture declares, including the bundle's own
  # `fixture-pack-a`/`fixture-pack-b` path_hints, is therefore a real,
  # minimal, fully-valid pack root under the scratch project.
  defp vendor_pack_dirs!(dir) do
    Enum.each(
      ["vendor/already-installed", "vendor/fixture-pack-a", "vendor/fixture-pack-b"],
      fn rel ->
        pack_root = Path.join(dir, rel)
        File.mkdir_p!(Path.join(pack_root, "templates"))

        File.write!(Path.join(pack_root, "pack.toml"), """
        [pack]
        name = "#{Path.basename(rel)}"
        version = "0.1.0"
        description = "GI-05 fixture pack"
        """)

        File.write!(Path.join(pack_root, "ontology.ttl"), "")

        File.write!(Path.join(pack_root, "templates/noop.tmpl"), """
        ---
        to: "__pack_noop__/#{Path.basename(rel)}.txt"
        ---
        noop
        """)
      end
    )
  end

  defp write_frontmatter_project!(dir, ontology_ttl) do
    File.mkdir_p!(Path.join(dir, "templates"))
    vendor_pack_dirs!(dir)

    File.write!(Path.join(dir, "ggen.toml"), """
    [project]
    name = "gi05-frontmatter-fixture"

    [ontology]
    source = "ontology.ttl"

    [packs]
    already-installed = { path = "vendor/already-installed" }

    [templates]
    dir = "templates"
    """)

    File.write!(Path.join(dir, "ontology.ttl"), ontology_ttl)

    File.write!(Path.join(dir, "templates/hello.tmpl"), """
    ---
    to: "hello.txt"
    ---
    hello-frontmatter
    """)
  end

  defp write_declarative_project!(dir, ontology_ttl) do
    File.mkdir_p!(Path.join(dir, "templates"))
    vendor_pack_dirs!(dir)

    File.write!(Path.join(dir, "ggen.toml"), """
    [project]
    name = "gi05-declarative-fixture"
    version = "0.1.0"

    [ontology]
    source = "ontology.ttl"

    [generation]
    output_dir = "."

    [[generation.rules]]
    name = "hello"
    query = { inline = \"\"\"
    PREFIX ex: <https://ggen-igniter.dev/ontology/gi05-fortune5#>
    SELECT ?s WHERE { ?s a ex:Thing . } ORDER BY ?s
    \"\"\" }
    template = { file = "templates/hello.tera" }
    output_file = "hello.txt"
    mode = "Overwrite"

    [[packs]]
    name = "already-installed"
    path = "vendor/already-installed"
    """)

    File.write!(Path.join(dir, "ontology.ttl"), ontology_ttl)

    File.write!(Path.join(dir, "templates/hello.tera"), """
    {% for row in sparql_results %}{{ row["s"] }}
    {% endfor %}
    """)
  end

  describe "Frontmatter schema end-to-end (case 1)" do
    if System.find_executable("ggen") do
      test "merges the bundle into [packs], syncs for real, and re-running is idempotent" do
        dir = scratch_project_dir("frontmatter")
        write_frontmatter_project!(dir, @ontology_with_thing)
        on_exit(fn -> File.rm_rf!(dir) end)

        igniter = run_task!(dir)

        assert igniter.issues == []
        assert Enum.any?(igniter.notices, &(&1 =~ "succeeded"))
        assert Enum.any?(igniter.notices, &(&1 =~ "fixture-pack-a"))
        assert Enum.any?(igniter.notices, &(&1 =~ "fixture-pack-b"))
        # The pre-existing entry was already installed -- not re-reported as newly added.
        refute Enum.any?(igniter.notices, &(&1 =~ "already-installed"))

        # Real post-run state on disk, re-parsed via the real pipeline --
        # never a hand-typed string compared in memory.
        assert {:frontmatter, config} = GgenIgniter.SchemaDispatch.load(dir)
        assert Map.has_key?(config.packs, "fixture-pack-a")
        assert Map.has_key?(config.packs, "fixture-pack-b")
        assert Map.has_key?(config.packs, "already-installed")
        assert map_size(config.packs) == 3

        # Real file `ggen sync run` produced, present on disk.
        assert File.exists?(Path.join(dir, "hello.txt"))
        assert File.read!(Path.join(dir, "hello.txt")) =~ "hello-frontmatter"

        content_after_first_run = File.read!(Path.join(dir, "ggen.toml"))

        # Idempotency: a second run against the same fixture is a real no-op
        # merge -- byte-identical ggen.toml, no duplicate pack entries.
        igniter2 = run_task!(dir)
        assert igniter2.issues == []
        assert Enum.any?(igniter2.notices, &(&1 =~ "packs added: (none)"))

        content_after_second_run = File.read!(Path.join(dir, "ggen.toml"))
        assert content_after_second_run == content_after_first_run

        assert {:frontmatter, config2} = GgenIgniter.SchemaDispatch.load(dir)
        assert map_size(config2.packs) == 3
      end
    else
      test "SKIPPED: Frontmatter schema end-to-end -- no `ggen` binary on PATH" do
        IO.puts(
          "SKIPPED: \"Frontmatter schema end-to-end\" -- no `ggen` binary on PATH " <>
            "(named, visible skip, no mock substitution)."
        )
      end
    end
  end

  # GI-08 fixture: models beam4pm's real ggen.toml `[packs]` shape exactly,
  # including the real `# gh-terraform-pack: investigated 2026-08-30, NOT
  # wired -- ...` decline-rationale comment block that sits directly after
  # the `[packs]` entries and before `[templates]` (mirrored verbatim from
  # `/Users/sac/beam4pm/ggen.toml`'s real text) -- the exact shape
  # `GgenToml.IO.serialize!/1`'s moduledoc discloses as silently dropped,
  # and `splice_added_packs!/2` (GI-07) plus this ticket's live wiring (GI-08)
  # exist specifically to preserve.
  @gh_terraform_pack_decline_comment """
  # gh-terraform-pack: investigated 2026-08-30, NOT wired -- ships unscoped
  # reference-repo instance data that hard-collides (family "repository") or
  # pollutes (families "milestones"/"labels") any second consumer's output.
  # See the "gh-terraform-pack consumption -- INVESTIGATED AND DECLINED"
  # comment block in ontology.ttl for the full, confirmed finding.\
  """

  defp write_frontmatter_project_with_comment!(dir, ontology_ttl) do
    File.mkdir_p!(Path.join(dir, "templates"))
    vendor_pack_dirs!(dir)

    File.write!(Path.join(dir, "ggen.toml"), """
    [project]
    name = "gi08-comment-preservation-fixture"

    [ontology]
    source = "ontology.ttl"

    [packs]
    already-installed = { path = "vendor/already-installed" }
    #{@gh_terraform_pack_decline_comment}

    [templates]
    dir = "templates"
    """)

    File.write!(Path.join(dir, "ontology.ttl"), ontology_ttl)

    File.write!(Path.join(dir, "templates/hello.tmpl"), """
    ---
    to: "hello.txt"
    ---
    hello-frontmatter
    """)
  end

  describe "GI-08: live splice wiring preserves comments through the real mix task" do
    if System.find_executable("ggen") do
      test "a real hand-written decline comment (modeled on beam4pm's gh-terraform-pack block) survives byte-for-byte outside the touched region, and re-running is idempotent" do
        dir = scratch_project_dir("gi08_comment")
        write_frontmatter_project_with_comment!(dir, @ontology_with_thing)
        on_exit(fn -> File.rm_rf!(dir) end)

        original = File.read!(Path.join(dir, "ggen.toml"))

        igniter = run_task!(dir)

        assert igniter.issues == []
        assert Enum.any?(igniter.notices, &(&1 =~ "succeeded"))
        assert Enum.any?(igniter.notices, &(&1 =~ "fixture-pack-a"))
        assert Enum.any?(igniter.notices, &(&1 =~ "fixture-pack-b"))

        after_first_run = File.read!(Path.join(dir, "ggen.toml"))

        # (a) The decline comment block survives byte-for-byte -- present
        # verbatim in the post-run file, not dropped by a lossy re-render.
        assert after_first_run =~ @gh_terraform_pack_decline_comment

        # Everything outside the touched [packs]-entries region is
        # byte-for-byte identical to the original: every original line
        # still appears, in the same relative order (a real subsequence
        # check), and the only new lines are the 2 newly-merged pack
        # entries.
        original_lines = String.split(original, "\n")
        after_lines = String.split(after_first_run, "\n")
        assert is_subsequence?(original_lines, after_lines)
        assert length(after_lines) == length(original_lines) + 2

        assert "fixture-pack-a = { path = \"vendor/fixture-pack-a\" }" in after_lines
        assert "fixture-pack-b = { path = \"vendor/fixture-pack-b\" }" in after_lines

        # The pre-existing entry keeps its original position (no
        # alphabetical Map-based reorder -- unlike the old serialize!/1
        # full-re-render path this ticket replaces for the frontmatter
        # schema).
        already_installed_idx =
          Enum.find_index(
            after_lines,
            &(&1 == "already-installed = { path = \"vendor/already-installed\" }")
          )

        assert Enum.at(after_lines, already_installed_idx + 1) ==
                 "fixture-pack-a = { path = \"vendor/fixture-pack-a\" }"

        assert Enum.at(after_lines, already_installed_idx + 2) ==
                 "fixture-pack-b = { path = \"vendor/fixture-pack-b\" }"

        assert Enum.at(after_lines, already_installed_idx + 3) =~
                 "gh-terraform-pack: investigated"

        # Real post-run state re-parsed via the real pipeline.
        assert {:frontmatter, config} = GgenIgniter.SchemaDispatch.load(dir)
        assert map_size(config.packs) == 3

        # (b) Idempotency: running the task a second time against the
        # already-wired file is a true no-op diff -- byte-identical
        # ggen.toml, comment block still intact.
        igniter2 = run_task!(dir)
        assert igniter2.issues == []
        assert Enum.any?(igniter2.notices, &(&1 =~ "packs added: (none)"))

        after_second_run = File.read!(Path.join(dir, "ggen.toml"))
        assert after_second_run == after_first_run
        assert after_second_run =~ @gh_terraform_pack_decline_comment
      end
    else
      test "SKIPPED: GI-08 comment-preservation end-to-end -- no `ggen` binary on PATH" do
        IO.puts(
          "SKIPPED: \"GI-08 comment-preservation end-to-end\" -- no `ggen` binary on PATH " <>
            "(named, visible skip, no mock substitution)."
        )
      end
    end
  end

  describe "DeclarativeRules schema end-to-end (case 2)" do
    if System.find_executable("ggen") do
      test "merges the bundle into [[packs]], syncs for real, dispatch genuinely branches" do
        dir = scratch_project_dir("declarative")
        write_declarative_project!(dir, @ontology_with_thing)
        on_exit(fn -> File.rm_rf!(dir) end)

        igniter = run_task!(dir)

        assert igniter.issues == []
        assert Enum.any?(igniter.notices, &(&1 =~ "succeeded"))
        assert Enum.any?(igniter.notices, &(&1 =~ "declarative_rules"))
        assert Enum.any?(igniter.notices, &(&1 =~ "fixture-pack-a"))
        assert Enum.any?(igniter.notices, &(&1 =~ "fixture-pack-b"))
        refute Enum.any?(igniter.notices, &(&1 =~ "already-installed"))

        assert {:declarative_rules, config} = GgenIgniter.SchemaDispatch.load(dir)
        names = Enum.map(config.packs, & &1.name)
        assert "fixture-pack-a" in names
        assert "fixture-pack-b" in names
        assert "already-installed" in names
        assert length(config.packs) == 3

        assert File.exists?(Path.join(dir, "hello.txt"))
        assert File.read!(Path.join(dir, "hello.txt")) =~ "t1"

        content_after_first_run = File.read!(Path.join(dir, "ggen.toml"))

        igniter2 = run_task!(dir)
        assert igniter2.issues == []
        assert Enum.any?(igniter2.notices, &(&1 =~ "packs added: (none)"))

        content_after_second_run = File.read!(Path.join(dir, "ggen.toml"))
        assert content_after_second_run == content_after_first_run

        assert {:declarative_rules, config2} = GgenIgniter.SchemaDispatch.load(dir)
        assert length(config2.packs) == 3
      end
    else
      test "SKIPPED: DeclarativeRules schema end-to-end -- no `ggen` binary on PATH" do
        IO.puts(
          "SKIPPED: \"DeclarativeRules schema end-to-end\" -- no `ggen` binary on PATH " <>
            "(named, visible skip, no mock substitution)."
        )
      end
    end
  end

  describe "negative case -- a real gate failure is reported as a failed run (case 3)" do
    if System.find_executable("ggen") do
      test "sync succeeds but the gate fails: task reports failure, never claims success" do
        dir = scratch_project_dir("gate_fail")
        # Ontology deliberately lacks ex:Thing -- sync itself still succeeds
        # (the frontmatter template has no RDF-dependent content), but the
        # fixture pack's own gates/010_thing_present.rq returns zero rows,
        # a real gate failure.
        write_frontmatter_project!(dir, @ontology_without_thing)
        on_exit(fn -> File.rm_rf!(dir) end)

        igniter = run_task!(dir, ["--pack-dir", @pack_dir])

        # Fail-loud: reported via a real issue, never a success notice.
        assert igniter.issues != []
        assert Enum.any?(igniter.issues, &(to_string(&1) =~ "thing_present"))
        refute Enum.any?(igniter.notices, &(&1 =~ "succeeded"))

        # The bundle merge was still written to disk for real (ggen sync
        # run needs the merged [packs] on disk to run at all) -- but the
        # run itself is not reported as a success, and the sync's own real
        # output file is unaffected by the gate outcome (sync ran before
        # the gate check, per the pipeline's own real ordering).
        assert {:frontmatter, config} = GgenIgniter.SchemaDispatch.load(dir)
        assert Map.has_key?(config.packs, "fixture-pack-a")
        assert File.exists?(Path.join(dir, "hello.txt"))
      end
    else
      test "SKIPPED: negative gate-failure case -- no `ggen` binary on PATH" do
        IO.puts(
          "SKIPPED: \"negative gate-failure case\" -- no `ggen` binary on PATH " <>
            "(named, visible skip, no mock substitution)."
        )
      end
    end
  end

  describe "mix ggen_igniter.fortune5_ready --help" do
    test "prints real usage text and exits zero" do
      {output, exit_code} =
        System.cmd("mix", ["ggen_igniter.fortune5_ready", "--help"],
          cd: File.cwd!(),
          stderr_to_stdout: true
        )

      assert exit_code == 0
      assert output =~ "mix ggen_igniter.fortune5_ready"
      assert output =~ "--path"
      assert output =~ "--pack-dir"
    end
  end

  # Same real subsequence check `test/ggen_igniter_bundle_test.exs` uses to
  # verify `splice_added_packs!/2`'s addition-only diff property -- proves
  # every original line still appears, in the same relative order, in the
  # post-run file (not just a length/count coincidence).
  defp is_subsequence?([], _list), do: true

  defp is_subsequence?([h | t], list) do
    case Enum.find_index(list, &(&1 == h)) do
      nil -> false
      idx -> is_subsequence?(t, Enum.drop(list, idx + 1))
    end
  end
end
