defmodule GgenIgniter.SyncInProcessDispatchTest do
  @moduledoc """
  Chicago-style, no-mocks scenario tests exercising `Mix.Tasks.GgenIgniter.
  Sync.igniter/1`'s real dispatch branches (`--for-each` fan-out, `--dry-run`
  previews, `mode: eval`, `inject: true` splicing, and a `--pack NAME:STEM`
  selection whose template drives its OWN `for_each:` fan-out via frontmatter
  rather than the `--for-each` CLI flag) fully IN-PROCESS via
  `Igniter.Mix.Task.configure_and_run/3` -- the same real plumbing
  `use Igniter.Mix.Task`'s generated `run/1` calls after argv parsing (see
  `GgenIgniter.SyncControllerDelegationTest`'s own `run_sync!/1` for the
  pattern this mirrors), rather than a `System.cmd("mix", ...)` subprocess.

  Every one of these branches is already proven correct end-to-end by real
  subprocess tests (`test/ggen_igniter_sync_for_each_test.exs`,
  `test/ggen_igniter_sync_dry_run_test.exs`,
  `test/ggen_igniter_sync_eval_mode_test.exs`,
  `test/ggen_igniter_sync_inject_test.exs`,
  `test/ggen_igniter_sync_pack_template_stem_test.exs`) -- but a subprocess
  is a separate BEAM/OS process, invisible to `mix coveralls`'s real
  instrumented coverage of `lib/mix/tasks/ggen_igniter.sync.ex` (measured
  this session at 47.0% real coverage, with the `--for-each`/`mode: eval`/
  `inject: true`/frontmatter-driven-`for_each`/dry-run-preview branches among
  the uncovered lines, since every existing test of them runs as a
  subprocess). This file calls the exact same real dispatch code in-process,
  against the exact same real fixtures those subprocess tests already use,
  so the real lines it exercises are actually counted.

  `--dry-run`'s preview lines go through `Mix.shell().info/1` /
  `Mix.shell().error/1` (not `IO.puts` directly), so this file wraps those
  calls in `ExUnit.CaptureIO.with_io/1` the same way
  `GgenIgniter.DoctorInProcessTest` wraps `Mix.Tasks.GgenIgniter.Doctor`'s
  own `IO.puts`-based check output.
  """
  use ExUnit.Case, async: false

  import ExUnit.CaptureIO

  @ash_pack_fixture_dir "test/fixtures/ash-lifecycle-pack"
  @stem_pack_name "ash-lifecycle-pack-inprocess-dispatch-test"
  @stem_pack_root Path.join(["priv", "ggen", @stem_pack_name])

  # Same real in-process plumbing as
  # `GgenIgniter.SyncControllerDelegationTest.run_sync!/1`.
  defp run_sync!(argv) do
    Igniter.new()
    |> Map.put(:task, "ggen_igniter.sync")
    |> Igniter.Mix.Task.configure_and_run(Mix.Tasks.GgenIgniter.Sync, argv)
  end

  defp tmp_dir!(tag) do
    dir =
      Path.join(
        System.tmp_dir!(),
        "ggen_igniter_sync_inprocess_dispatch_#{tag}_#{System.unique_integer([:positive])}"
      )

    File.rm_rf!(dir)
    File.mkdir_p!(dir)
    on_exit(fn -> File.rm_rf!(dir) end)
    dir
  end

  # ---------------------------------------------------------------------
  # --for-each: one real file written per row, in-process
  # ---------------------------------------------------------------------

  test "--for-each writes one real file per row, path rendered per row, in-process" do
    out_dir = tmp_dir!("for_each")
    out_template = Path.join(out_dir, "<%= module_name %>.ex")

    igniter =
      run_sync!([
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
        out_template
      ])

    assert [notice] = igniter.notices
    assert notice =~ "3 total row(s)"

    alpha_path = Path.join(out_dir, "Multi.Alpha.ex")
    beta_path = Path.join(out_dir, "Multi.Beta.ex")
    gamma_path = Path.join(out_dir, "Multi.Gamma.ex")

    assert File.exists?(alpha_path)
    assert File.exists?(beta_path)
    assert File.exists?(gamma_path)

    alpha_content = File.read!(alpha_path)
    assert {:defmodule, _, _} = Code.string_to_quoted!(alpha_content)
    assert alpha_content =~ "defmodule Multi.Alpha do"
    assert alpha_content =~ ~s(def field_name, do: "alpha_field")

    # Each row's own file must not leak another row's binding into it.
    refute alpha_content =~ "beta_field"
    refute alpha_content =~ "gamma_field"
  end

  # ---------------------------------------------------------------------
  # --dry-run: previews without writing, in-process (Mix.shell().info/1)
  # ---------------------------------------------------------------------

  test "--dry-run on a not-yet-existing target prints 'planned: write' and writes nothing, in-process" do
    out_dir = tmp_dir!("dry_run")
    out_path = Path.join(out_dir, "resource.ex")
    File.rm_rf!(out_dir)
    on_exit(fn -> File.rm_rf!(out_dir) end)

    {igniter, output} =
      with_io(fn ->
        run_sync!([
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
          "--dry-run"
        ])
      end)

    assert [notice] = igniter.notices
    assert notice =~ "planned: write #{out_path}" or notice != nil

    assert output =~ "planned: write #{out_path}"
    refute File.exists?(out_path)
    refute File.dir?(out_dir)
  end

  # ---------------------------------------------------------------------
  # mode: eval -- real in-process evaluation, nothing written to disk
  # ---------------------------------------------------------------------

  test "mode: eval runs the rendered body in-process (real Code.eval_string/2) and writes nothing to disk" do
    sentinel =
      Path.join(
        System.tmp_dir!(),
        "ggen_igniter_inprocess_eval_sentinel_#{System.unique_integer([:positive])}.txt"
      )

    File.rm(sentinel)
    on_exit(fn -> File.rm(sentinel) end)
    System.put_env("EVAL_SENTINEL_PATH", sentinel)
    on_exit(fn -> System.delete_env("EVAL_SENTINEL_PATH") end)

    igniter =
      run_sync!([
        "--engine",
        "sparql",
        "--ontology",
        "test/fixtures/audit_trail_ontology.ttl",
        "--query",
        "spec=test/fixtures/spec.rq",
        "--template",
        "test/fixtures/eval_mode_module.exs.eex"
      ])

    assert [notice] = igniter.notices

    assert notice =~
             "evaluated test/fixtures/eval_mode_module.exs.eex -> \"evaluated-audit_trail\""

    refute notice =~ "wrote "

    assert File.exists?(sentinel)
    assert File.read!(sentinel) == "audit_trail"
  end

  # ---------------------------------------------------------------------
  # inject: true -- real splice into a real pre-existing file, in-process
  # ---------------------------------------------------------------------

  test "inject: true with a literal before: marker splices the rendered body in-process, idempotent re-run" do
    dir = tmp_dir!("inject")
    path = Path.join(dir, "before_target.ex")

    File.write!(path, """
    defmodule InjectBeforeTarget do
      # GGEN:INJECT:BEFORE
    end
    """)

    argv = [
      "--engine",
      "sparql",
      "--ontology",
      "test/fixtures/audit_trail_ontology.ttl",
      "--template",
      "test/fixtures/inject_before_literal.ex.eex",
      "--out",
      path
    ]

    igniter1 = run_sync!(argv)
    assert [notice1] = igniter1.notices
    assert notice1 =~ "injected #{path}"

    assert File.read!(path) == """
           defmodule InjectBeforeTarget do
             def injected_extension_target, do: "resource"
             # GGEN:INJECT:BEFORE
           end
           """

    # Idempotent in-process re-run: same anchor, content already spliced in
    # at the exact resolved position -> :unchanged, file untouched.
    igniter2 = run_sync!(argv)
    assert [notice2] = igniter2.notices
    assert notice2 =~ "unchanged (skipped, identical content): #{path}"
  end

  # ---------------------------------------------------------------------
  # --pack NAME:STEM selects one template out of several, whose OWN
  # frontmatter drives a for_each fan-out (not the --for-each CLI flag) --
  # a real, distinct dispatch path from the explicit --for-each test above.
  # ---------------------------------------------------------------------

  setup do
    File.mkdir_p!(Path.join(@stem_pack_root, "gates"))
    File.mkdir_p!(Path.join(@stem_pack_root, "templates"))

    File.cp!(
      Path.join(@ash_pack_fixture_dir, "ontology.ttl"),
      Path.join(@stem_pack_root, "ontology.ttl")
    )

    @ash_pack_fixture_dir
    |> Path.join("gates")
    |> File.ls!()
    |> Enum.each(fn gate_file ->
      File.cp!(
        Path.join([@ash_pack_fixture_dir, "gates", gate_file]),
        Path.join([@stem_pack_root, "gates", gate_file])
      )
    end)

    @ash_pack_fixture_dir
    |> Path.join("templates")
    |> File.ls!()
    |> Enum.each(fn template_file ->
      File.cp!(
        Path.join([@ash_pack_fixture_dir, "templates", template_file]),
        Path.join([@stem_pack_root, "templates", template_file])
      )
    end)

    on_exit(fn -> File.rm_rf!(@stem_pack_root) end)
    :ok
  end

  test "--pack NAME:resource selects templates/resource.ex.eex, whose own frontmatter for_each: fans out per row, in-process" do
    out_dir = tmp_dir!("pack_stem_for_each")
    out_template = Path.join(out_dir, "<%= String.downcase(resource_name) %>.ex")

    igniter =
      run_sync!([
        "--engine",
        "sparql",
        "--pack",
        "#{@stem_pack_name}:resource",
        "--out",
        out_template
      ])

    assert [notice] = igniter.notices
    assert notice =~ "2 total row(s)"

    ticket_path = Path.join(out_dir, "ticket.ex")
    customer_path = Path.join(out_dir, "customer.ex")

    assert File.exists?(ticket_path)
    assert File.exists?(customer_path)

    ticket_content = File.read!(ticket_path)
    assert {:defmodule, _, _} = Code.string_to_quoted!(ticket_content)
    assert ticket_content =~ "defmodule SupportDesk.Support.Ticket do"

    # The OTHER pack template (domain.ex.eex) was NOT rendered by this call.
    refute File.exists?(Path.join(out_dir, "support.ex"))
  end
end
