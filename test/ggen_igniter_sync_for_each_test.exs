defmodule GgenIgniter.SyncForEachTest do
  use ExUnit.Case, async: false

  @moduletag :integration

  test "mix ggen_igniter.sync --for-each writes one real file per row, path rendered per row" do
    out_dir =
      Path.join(
        System.tmp_dir!(),
        "ggen_igniter_for_each_test_#{System.unique_integer([:positive])}"
      )

    # `System.unique_integer/1` restarts from low values on every fresh BEAM
    # instance (every `mix test` invocation), so two separate test runs can
    # collide on the exact same tmp path if this directory is never cleaned
    # up -- real, observed flake (a stale directory from an earlier run made
    # this test see "unchanged" content instead of a fresh "wrote"). Clean up
    # for real, every run.
    File.rm_rf!(out_dir)
    on_exit(fn -> File.rm_rf!(out_dir) end)

    out_template = Path.join(out_dir, "<%= module_name %>.ex")

    args = [
      "ggen_igniter.sync",
      # Pinned to sparql: asserts real file paths/module names/generated
      # Elixir content built from module_name/field_name -- oxigraph's raw,
      # quoted N-Triples-style term strings (the real, disclosed shape
      # difference the sync task's own moduledoc documents) aren't what this
      # --for-each fan-out mechanics test is about.
      "--engine",
      "sparql",
      "--ontology",
      "test/fixtures/for_each_ontology.ttl",
      "--query",
      "modules=test/fixtures/modules.rq",
      "--for-each",
      "modules",
      "--template",
      "test/fixtures/for_each_module.ex.eex",
      "--out",
      out_template,
      # v26.9.2 (workstream B): `--for-each` now routes through
      # `GgenIgniter.Reactors.ReconcileReactor.run/1`, which enforces the
      # SAME authorized-project-root/`:verify` requirements every other
      # reactor-routed write in this codebase already does -- `--out` here
      # resolves outside the repo root (a real tmp dir), so `--manifest-dir`
      # scopes the authorized root to it and `--verify-cwd` keeps `:verify`'s
      # real `mix compile` pointed at the real repo root. Before v26.9.2,
      # `--for-each` always ran via the inline `run_pipeline!/3` pipeline,
      # which has neither an authorized-root check nor a `:verify` step, so
      # neither flag was needed here.
      "--manifest-dir",
      out_dir,
      "--verify-cwd",
      File.cwd!()
    ]

    {output, exit_code} = System.cmd("mix", args, cd: File.cwd!(), stderr_to_stdout: true)

    assert exit_code == 0, "mix ggen_igniter.sync --for-each failed:\n#{output}"

    alpha_path = Path.join(out_dir, "Multi.Alpha.ex")
    beta_path = Path.join(out_dir, "Multi.Beta.ex")
    gamma_path = Path.join(out_dir, "Multi.Gamma.ex")

    # Real multi-row fan-out: exactly the three rows in the fixture's `modules`
    # query, as three real separate files on disk -- not one aggregated file.
    assert File.exists?(alpha_path)
    assert File.exists?(beta_path)
    assert File.exists?(gamma_path)

    alpha_content = File.read!(alpha_path)
    beta_content = File.read!(beta_path)
    gamma_content = File.read!(gamma_path)

    assert {:defmodule, _, _} = Code.string_to_quoted!(alpha_content)
    assert {:defmodule, _, _} = Code.string_to_quoted!(beta_content)
    assert {:defmodule, _, _} = Code.string_to_quoted!(gamma_content)

    assert alpha_content =~ "defmodule Multi.Alpha do"
    assert alpha_content =~ ~s(def field_name, do: "alpha_field")

    assert beta_content =~ "defmodule Multi.Beta do"
    assert beta_content =~ ~s(def field_name, do: "beta_field")

    assert gamma_content =~ "defmodule Multi.Gamma do"
    assert gamma_content =~ ~s(def field_name, do: "gamma_field")

    # Each row's own file must not leak another row's binding into it.
    refute alpha_content =~ "beta_field"
    refute alpha_content =~ "gamma_field"
  end

  test "mix ggen_igniter.sync without --for-each still writes exactly one static file (unchanged behavior)" do
    # `root_dir` (passed as `--manifest-dir`) wraps `out_dir` as its own
    # subdirectory -- kept DISTINCT from `out_dir` itself so this run's
    # `<manifest-dir>/.ggen_igniter/manifest.json` bookkeeping lands
    # alongside `out_dir`, never INSIDE it, which would otherwise break this
    # test's own "exactly one file" `File.ls!(out_dir)` assertion below.
    root_dir =
      Path.join(
        System.tmp_dir!(),
        "ggen_igniter_no_for_each_test_root_#{System.unique_integer([:positive])}"
      )

    out_dir = Path.join(root_dir, "output")

    # Same real cross-run tmp-dir-collision flake as the --for-each test
    # above (`System.unique_integer/1` restarts every fresh BEAM instance) --
    # clean up for real, every run.
    File.rm_rf!(root_dir)
    on_exit(fn -> File.rm_rf!(root_dir) end)

    out_path = Path.join(out_dir, "resource.ex")

    args = [
      "ggen_igniter.sync",
      # Pinned to sparql: asserts real generated Elixir content (parses it
      # via Code.string_to_quoted!/1) built directly from ontology literal
      # values -- oxigraph (the default since v26.8.27) returns typed
      # literals as raw, datatype-annotated N-Triples-style term strings
      # (e.g. `"true"^^<...#boolean>`) which is not valid Elixir when
      # interpolated straight into generated source the way this fixture
      # template does; this is a real, disclosed engine-shape difference
      # (see the sync task's own moduledoc and `GgenIgniter.Query`'s), not
      # something this "unchanged static-output behavior" test is about.
      "--engine",
      "sparql",
      "--ontology",
      "test/fixtures/audit_trail_ontology.ttl",
      "--query",
      "spec=test/fixtures/spec.rq",
      "--query",
      "sections=test/fixtures/sections.rq",
      "--query",
      "entities=test/fixtures/entities.rq",
      "--query",
      "fields=test/fixtures/fields.rq",
      "--template",
      "test/fixtures/extension.ex.eex",
      "--out",
      out_path,
      # `out_path` lives outside the repo root (a real, unique tmp dir this
      # test creates and removes itself) -- `--manifest-dir` scopes
      # `GgenIgniter.ArtifactIdentity.within_root?/2`'s authorized-project-root
      # check to `root_dir` (which contains `out_dir`) instead of the
      # default `File.cwd!()`, and `--verify-cwd` keeps `:verify`'s real
      # `mix compile` pointed at the real repo root instead of the bare (no
      # `mix.exs`) tmp dir.
      "--manifest-dir",
      root_dir,
      "--verify-cwd",
      File.cwd!()
    ]

    {output, exit_code} = System.cmd("mix", args, cd: File.cwd!(), stderr_to_stdout: true)

    assert exit_code == 0, "mix ggen_igniter.sync failed:\n#{output}"
    assert output =~ "ggen_igniter: wrote #{out_path}"

    assert File.exists?(out_path)
    content = File.read!(out_path)
    assert {:defmodule, _, _} = Code.string_to_quoted!(content)
    assert content =~ "defmodule AuditTrail.Resource do"

    # Exactly one file -- no sibling files were created alongside it.
    assert File.ls!(out_dir) == ["resource.ex"]
  end

  test "mix ggen_igniter.sync --for-each with many rows appends a real outcome-count summary without dropping per-file detail" do
    # DX regression test (2026-08-28): a `--for-each` fan-out with several
    # rows used to produce one undifferentiated `"; "`-joined notice line
    # with no summary at all -- real, observed with the 8-row
    # `for_each_ontology_8.ttl`/`modules_8.rq` fixture pair. This asserts the
    # real appended summary's counts against real, independently-observable
    # outcomes (file mtimes/existence before and after a second run with
    # `--unless-exists`), not a hardcoded expectation.
    # `root_dir` wraps `out_dir` -- kept DISTINCT so `--manifest-dir`'s own
    # `.ggen_igniter/` bookkeeping never lands inside `out_dir` itself,
    # which would break this test's own `File.ls!(out_dir)` exact-count
    # assertions below.
    root_dir =
      Path.join(
        System.tmp_dir!(),
        "ggen_igniter_for_each_summary_test_#{System.unique_integer([:positive])}"
      )

    out_dir = Path.join(root_dir, "output")

    File.rm_rf!(root_dir)
    on_exit(fn -> File.rm_rf!(root_dir) end)

    out_template = Path.join(out_dir, "<%= module_name %>.ex")

    base_args = [
      "ggen_igniter.sync",
      "--engine",
      "sparql",
      "--ontology",
      "test/fixtures/for_each_ontology_8.ttl",
      "--query",
      "modules=test/fixtures/modules_8.rq",
      "--for-each",
      "modules",
      "--template",
      "test/fixtures/for_each_module.ex.eex",
      "--out",
      out_template,
      # v26.9.2 (workstream B): see the earlier test in this file for why
      # `--manifest-dir`/`--verify-cwd` are now required for `--for-each`.
      "--manifest-dir",
      root_dir,
      "--verify-cwd",
      File.cwd!()
    ]

    # First run: every one of the 8 rows is a genuine fresh write.
    {first_output, first_exit} =
      System.cmd("mix", base_args, cd: File.cwd!(), stderr_to_stdout: true)

    assert first_exit == 0, "first sync run failed:\n#{first_output}"
    assert first_output =~ "-- summary: wrote 8"

    # Real ground truth: exactly 8 files landed on disk.
    written_files = File.ls!(out_dir)
    assert length(written_files) == 8

    # Delete two of the eight real files, so a second `--unless-exists` run
    # has a REAL, independently-verifiable mix of outcomes: 2 real fresh
    # writes (the deleted ones) and 6 real `--unless-exists` skips (the ones
    # still present).
    deleted = Enum.take(Enum.sort(written_files), 2)
    for f <- deleted, do: File.rm!(Path.join(out_dir, f))
    assert length(File.ls!(out_dir)) == 6

    {second_output, second_exit} =
      System.cmd("mix", base_args ++ ["--unless-exists"], cd: File.cwd!(), stderr_to_stdout: true)

    assert second_exit == 0, "second sync run failed:\n#{second_output}"

    # The real summary's counts must match the real, independently-observed
    # outcome: 2 files genuinely re-written, 6 genuinely left alone.
    assert second_output =~ "-- summary: wrote 2, skipped 6"

    # Per-file detail must still be present alongside the summary -- the
    # summary is additive, not a replacement.
    for f <- deleted do
      module = Path.rootname(f)
      assert second_output =~ "wrote #{Path.join(out_dir, module)}.ex"
    end

    for f <- written_files -- deleted do
      module = Path.rootname(f)

      assert second_output =~
               "skipped (unless_exists, already exists): #{Path.join(out_dir, module)}.ex"
    end

    # Real ground truth after the second run: all 8 files present again.
    assert length(File.ls!(out_dir)) == 8
  end

  test "mix ggen_igniter.sync --for-each with an undeclared query name fails closed" do
    args = [
      "ggen_igniter.sync",
      "--ontology",
      "test/fixtures/for_each_ontology.ttl",
      "--query",
      "modules=test/fixtures/modules.rq",
      "--for-each",
      "not_a_declared_query",
      "--template",
      "test/fixtures/for_each_module.ex.eex",
      "--out",
      Path.join(System.tmp_dir!(), "should_not_be_written_<%= module_name %>.ex")
    ]

    {output, exit_code} = System.cmd("mix", args, cd: File.cwd!(), stderr_to_stdout: true)

    refute exit_code == 0
    assert output =~ "not_a_declared_query"
  end
end
