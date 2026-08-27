defmodule GgenIgniter.SyncDryRunTest do
  use ExUnit.Case, async: false

  @moduletag :integration

  defp base_args(out_path) do
    [
      "ggen_igniter.sync",
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
      out_path
    ]
  end

  test "--dry-run on a not-yet-existing target prints 'planned: write' and writes nothing" do
    out_dir =
      Path.join(
        System.tmp_dir!(),
        "ggen_igniter_dry_run_new_test_#{System.unique_integer([:positive])}"
      )

    out_path = Path.join(out_dir, "resource.ex")

    {output, exit_code} =
      System.cmd("mix", base_args(out_path) ++ ["--dry-run"],
        cd: File.cwd!(),
        stderr_to_stdout: true
      )

    assert exit_code == 0, "mix ggen_igniter.sync --dry-run failed:\n#{output}"
    assert output =~ "planned: write #{out_path}"

    # Zero actual filesystem writes: the target file, and even its parent
    # directory (never created via mkdir_p under dry-run), must not exist.
    refute File.exists?(out_path)
    refute File.dir?(out_dir)
  end

  test "--dry-run against an already-identical file prints 'planned: skip ... (unchanged)' and leaves it untouched" do
    out_dir =
      Path.join(
        System.tmp_dir!(),
        "ggen_igniter_dry_run_unchanged_test_#{System.unique_integer([:positive])}"
      )

    out_path = Path.join(out_dir, "resource.ex")

    # First, a real (non-dry-run) run to create the file for real.
    {setup_output, setup_exit} =
      System.cmd("mix", base_args(out_path), cd: File.cwd!(), stderr_to_stdout: true)

    assert setup_exit == 0, "setup real sync failed:\n#{setup_output}"
    assert File.exists?(out_path)
    original_content = File.read!(out_path)
    original_mtime = File.stat!(out_path).mtime

    # Now dry-run against the now-identical target.
    {output, exit_code} =
      System.cmd("mix", base_args(out_path) ++ ["--dry-run"],
        cd: File.cwd!(),
        stderr_to_stdout: true
      )

    assert exit_code == 0, "mix ggen_igniter.sync --dry-run failed:\n#{output}"
    assert output =~ "planned: skip #{out_path} (unchanged)"

    # File is byte-identical and untouched (mtime unchanged -- proves no
    # write syscall touched it, not just that the bytes happen to match).
    assert File.read!(out_path) == original_content
    assert File.stat!(out_path).mtime == original_mtime
  end

  test "--dry-run with --unless-exists against an existing target prints the unless_exists/skip_if line and writes nothing" do
    out_dir =
      Path.join(
        System.tmp_dir!(),
        "ggen_igniter_dry_run_unless_exists_test_#{System.unique_integer([:positive])}"
      )

    out_path = Path.join(out_dir, "resource.ex")
    File.mkdir_p!(out_dir)
    File.write!(out_path, "# pre-existing content, deliberately different from the render\n")
    original_content = File.read!(out_path)

    {output, exit_code} =
      System.cmd("mix", base_args(out_path) ++ ["--dry-run", "--unless-exists"],
        cd: File.cwd!(),
        stderr_to_stdout: true
      )

    assert exit_code == 0, "mix ggen_igniter.sync --dry-run --unless-exists failed:\n#{output}"
    assert output =~ "planned: skip #{out_path} (unless_exists/skip_if match)"

    # Zero writes: pre-existing content is completely untouched.
    assert File.read!(out_path) == original_content
  end

  test "--dry-run with --for-each plans one line per row and writes zero real files" do
    out_dir =
      Path.join(
        System.tmp_dir!(),
        "ggen_igniter_dry_run_for_each_test_#{System.unique_integer([:positive])}"
      )

    out_template = Path.join(out_dir, "<%= module_name %>.ex")

    args = [
      "ggen_igniter.sync",
      # Pinned to sparql: asserts real "planned: write <path>" lines built
      # from module_name -- oxigraph's raw, quoted N-Triples-style term
      # strings (the real, disclosed shape difference the sync task's own
      # moduledoc documents) aren't what this --dry-run/--for-each mechanics
      # test is about.
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
      "--dry-run"
    ]

    {output, exit_code} = System.cmd("mix", args, cd: File.cwd!(), stderr_to_stdout: true)

    assert exit_code == 0, "mix ggen_igniter.sync --for-each --dry-run failed:\n#{output}"

    alpha_path = Path.join(out_dir, "Multi.Alpha.ex")
    beta_path = Path.join(out_dir, "Multi.Beta.ex")
    gamma_path = Path.join(out_dir, "Multi.Gamma.ex")

    assert output =~ "planned: write #{alpha_path}"
    assert output =~ "planned: write #{beta_path}"
    assert output =~ "planned: write #{gamma_path}"

    # Real, full pipeline ran (ontology load, per-row query fan-out, template
    # render, path resolution) -- but zero files were actually written, and
    # the output directory itself was never created.
    refute File.exists?(alpha_path)
    refute File.exists?(beta_path)
    refute File.exists?(gamma_path)
    refute File.dir?(out_dir)
  end
end
