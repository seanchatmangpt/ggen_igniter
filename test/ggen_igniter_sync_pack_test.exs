defmodule GgenIgniter.SyncPackTaskTest do
  @moduledoc """
  Chicago-style, no-mocks proof that `mix ggen_igniter.sync --pack-dir DIR` (and
  `--pack NAME`) resolves --ontology/--query/--template from the pack
  convention and runs end-to-end as a real subprocess, mirroring
  `ggen_igniter_sync_task_test.exs`'s existing conventions.
  """
  use ExUnit.Case, async: false

  @moduletag :integration

  test "mix ggen_igniter.sync --pack-dir resolves ontology/queries/template from the pack and writes a real file" do
    out_dir =
      Path.join(
        System.tmp_dir!(),
        "ggen_igniter_sync_pack_test_#{System.unique_integer([:positive])}"
      )

    File.rm_rf!(out_dir)
    on_exit(fn -> File.rm_rf!(out_dir) end)

    out_path = Path.join(out_dir, "resource.ex")

    args = [
      "ggen_igniter.sync",
      # Pinned to sparql: asserts real generated Elixir content built from
      # ontology literal values -- oxigraph (the default since v26.8.27)
      # returns typed literals as raw, datatype-annotated N-Triples-style
      # term strings, a real, disclosed engine-shape difference (see the
      # sync task's own moduledoc), not something this --pack-dir resolution
      # test is about.
      "--engine",
      "sparql",
      "--pack-dir",
      "test/fixtures/sample-pack",
      "--out",
      out_path,
      # `out_path` lives outside the repo root (a real, unique tmp dir this
      # test creates and removes itself) -- `--manifest-dir` scopes
      # `GgenIgniter.ArtifactIdentity.within_root?/2`'s authorized-project-root
      # check to that same tmp dir instead of the default `File.cwd!()`, so
      # this legitimately-outside-cwd-but-test-owned target isn't refused as
      # a path escape. See `docs/architecture/adr/` for the guard itself.
      "--manifest-dir",
      out_dir,
      # `:verify`'s real `mix compile --warnings-as-errors` subprocess would
      # otherwise inherit `--manifest-dir` (a bare tmp dir with no
      # `mix.exs`) and fail with "Could not find a Mix.Project" -- point it
      # back at this repo's own real root.
      "--verify-cwd",
      File.cwd!()
    ]

    {output, exit_code} = System.cmd("mix", args, cd: File.cwd!(), stderr_to_stdout: true)

    assert exit_code == 0, "mix ggen_igniter.sync --pack-dir failed:\n#{output}"
    assert output =~ "ggen_igniter: wrote #{out_path}"
    assert output =~ "4 queries"

    assert File.exists?(out_path)
    content = File.read!(out_path)

    assert {:defmodule, _, _} = Code.string_to_quoted!(content)
    assert content =~ "defmodule AuditTrail.Resource do"
    assert content =~ "defmodule AuditTrail.Dsl.Event do"
  end

  test "mix ggen_igniter.sync --pack NAME resolves under priv/ggen/<name>/" do
    out_dir =
      Path.join(
        System.tmp_dir!(),
        "ggen_igniter_sync_pack_name_test_#{System.unique_integer([:positive])}"
      )

    File.rm_rf!(out_dir)
    on_exit(fn -> File.rm_rf!(out_dir) end)

    out_path = Path.join(out_dir, "resource.ex")
    pack_root = Path.join(["priv", "ggen", "doctest-pack"])

    File.mkdir_p!(Path.join(pack_root, "gates"))
    File.mkdir_p!(Path.join(pack_root, "templates"))
    File.cp!("test/fixtures/sample-pack/ontology.ttl", Path.join(pack_root, "ontology.ttl"))

    File.cp!(
      "test/fixtures/sample-pack/gates/010_spec.rq",
      Path.join([pack_root, "gates", "010_spec.rq"])
    )

    File.cp!(
      "test/fixtures/sample-pack/templates/extension.ex.eex",
      Path.join([pack_root, "templates", "extension.ex.eex"])
    )

    on_exit(fn -> File.rm_rf!(pack_root) end)

    args = [
      "ggen_igniter.sync",
      # Pinned to sparql: this test parses the written file as real Elixir
      # (Code.string_to_quoted!/1) -- oxigraph (the default since v26.8.27)
      # returns typed literals as raw, datatype-annotated N-Triples-style
      # term strings, which is not valid Elixir when interpolated directly
      # into generated source; a real, disclosed engine-shape difference
      # (see the sync task's own moduledoc), not something this --pack NAME
      # resolution test is about.
      "--engine",
      "sparql",
      "--pack",
      "doctest-pack",
      # `spec` alone doesn't provide the `sections`/`entities`/`fields`
      # bindings the fixture template also references -- add them explicitly
      # to prove pack-derived and explicit --query flags compose (pack first,
      # explicit appended, per the resolution order the pack module documents).
      "--query",
      "sections=test/fixtures/sample-pack/gates/020_sections.rq",
      "--query",
      "entities=test/fixtures/sample-pack/gates/030_entities.rq",
      "--query",
      "fields=test/fixtures/sample-pack/gates/040_fields.rq",
      "--out",
      out_path,
      # See the `--pack-dir` test above: `out_path` is outside the repo
      # root, so `--manifest-dir` scopes the within-root guard to this
      # test's own tmp dir, and `--verify-cwd` keeps `:verify`'s real `mix
      # compile` pointed at the real repo root instead.
      "--manifest-dir",
      out_dir,
      "--verify-cwd",
      File.cwd!()
    ]

    {output, exit_code} = System.cmd("mix", args, cd: File.cwd!(), stderr_to_stdout: true)

    assert exit_code == 0, "mix ggen_igniter.sync --pack failed:\n#{output}"
    assert File.exists?(out_path)
    assert Code.string_to_quoted!(File.read!(out_path))
  end

  test "mix ggen_igniter.sync with no ontology/query/template/pack fails with a clear error" do
    out_path =
      Path.join(
        System.tmp_dir!(),
        "ggen_igniter_sync_pack_missing_#{System.unique_integer([:positive])}.ex"
      )

    {output, exit_code} =
      System.cmd("mix", ["ggen_igniter.sync", "--out", out_path],
        cd: File.cwd!(),
        stderr_to_stdout: true
      )

    refute exit_code == 0
    # `Mix.Tasks.GgenIgniter.Sync.run_via_reactor/3` (the path this repo
    # always routes through since sync started defaulting to the Reactor
    # pipeline) resolves `--template` before `--ontology` -- it needs the
    # template up front to check for frontmatter/`for_each` and decide
    # delegability -- so with NEITHER flag present, "--template is
    # required" is the real first error now, not "--ontology is required"
    # (the old direct `run_pipeline!/3`'s ontology-first order). Both are
    # equally "a clear error"; this test's job is proving *a* clear error
    # occurs with zero flags, not asserting a specific validation order.
    assert output =~ "--template is required"
  end
end
