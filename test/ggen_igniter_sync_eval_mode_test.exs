defmodule GgenIgniter.SyncEvalModeTest do
  @moduledoc """
  Chicago-style, real subprocess, no mocks: proves `mode: eval` templates
  actually execute their rendered body in-process via `Code.eval_string/2`
  (`GgenIgniter.Actuate.eval_code!/2`) instead of being written to disk --
  the user's own framing: "if the template is igniter code it is dynamically
  generated with the RDF but is then executed, not written to disk."
  """
  use ExUnit.Case, async: false

  @moduletag :integration

  test "mode: eval runs the rendered body in-process and writes nothing to disk" do
    sentinel =
      Path.join(System.tmp_dir!(), "eval_sentinel_#{System.unique_integer([:positive])}.txt")

    File.rm(sentinel)
    on_exit(fn -> File.rm(sentinel) end)

    args = [
      "ggen_igniter.sync",
      # Pinned to sparql: asserts an exact eval return value string built
      # from module_name -- oxigraph (the default since v26.8.27) returns
      # raw, quoted N-Triples-style term strings instead of sparql's
      # unwrapped native values (a real, disclosed shape difference, see the
      # sync task's own moduledoc), which isn't what this eval-mode-mechanics
      # test is about.
      "--engine",
      "sparql",
      "--ontology",
      "test/fixtures/audit_trail_ontology.ttl",
      "--query",
      "spec=test/fixtures/spec.rq",
      "--template",
      "test/fixtures/eval_mode_module.exs.eex"
    ]

    {output, exit_code} =
      System.cmd("mix", args,
        cd: File.cwd!(),
        stderr_to_stdout: true,
        env: [{"EVAL_SENTINEL_PATH", sentinel}]
      )

    assert exit_code == 0, "mix ggen_igniter.sync failed:\n#{output}"

    # Real proof of execution, not a write: the notice says "evaluated", never
    # "wrote", and the eval'd code's own real side effect (writing the
    # sentinel file with real content) actually happened.
    assert output =~
             "evaluated test/fixtures/eval_mode_module.exs.eex -> \"evaluated-audit_trail\""

    refute output =~ "wrote "

    assert File.exists?(sentinel)
    assert File.read!(sentinel) == "audit_trail"
  end

  test "mode: eval + --for-each evaluates once per row, each with that row's own bindings" do
    sentinel_dir =
      Path.join(System.tmp_dir!(), "eval_sentinel_dir_#{System.unique_integer([:positive])}")

    File.rm_rf(sentinel_dir)
    File.mkdir_p!(sentinel_dir)
    on_exit(fn -> File.rm_rf(sentinel_dir) end)

    args = [
      "ggen_igniter.sync",
      # Pinned to sparql: asserts real filenames/eval strings built from
      # module_name -- oxigraph's raw, quoted term-string shape (the real,
      # disclosed difference the sync task's own moduledoc documents) isn't
      # what this --for-each/eval-mode fan-out mechanics test is about.
      "--engine",
      "sparql",
      "--ontology",
      "test/fixtures/for_each_ontology.ttl",
      "--query",
      "modules=test/fixtures/modules.rq",
      "--for-each",
      "modules",
      "--template",
      "test/fixtures/eval_mode_for_each.exs.eex"
    ]

    {output, exit_code} =
      System.cmd("mix", args,
        cd: File.cwd!(),
        stderr_to_stdout: true,
        env: [{"EVAL_SENTINEL_DIR", sentinel_dir}]
      )

    assert exit_code == 0, "mix ggen_igniter.sync failed:\n#{output}"

    written = sentinel_dir |> File.ls!() |> Enum.sort()
    assert written == ["Multi.Alpha.txt", "Multi.Beta.txt", "Multi.Gamma.txt"]

    for name <- written do
      assert output =~ "evaluated-#{Path.rootname(name)}"
    end
  end

  test "a deliberately broken eval body raises a clear error, not a raw stacktrace dump" do
    args = [
      "ggen_igniter.sync",
      "--ontology",
      "test/fixtures/audit_trail_ontology.ttl",
      "--query",
      "spec=test/fixtures/spec.rq",
      "--template",
      "test/fixtures/eval_mode_broken.exs.eex"
    ]

    {output, exit_code} = System.cmd("mix", args, cd: File.cwd!(), stderr_to_stdout: true)

    assert exit_code != 0
    assert output =~ "mode: eval template failed to compile"
  end

  test "--dry-run with mode: eval plans without actually evaluating anything" do
    sentinel =
      Path.join(
        System.tmp_dir!(),
        "eval_sentinel_dryrun_#{System.unique_integer([:positive])}.txt"
      )

    File.rm(sentinel)
    on_exit(fn -> File.rm(sentinel) end)

    args = [
      "ggen_igniter.sync",
      "--ontology",
      "test/fixtures/audit_trail_ontology.ttl",
      "--query",
      "spec=test/fixtures/spec.rq",
      "--template",
      "test/fixtures/eval_mode_module.exs.eex",
      "--dry-run"
    ]

    {output, exit_code} =
      System.cmd("mix", args,
        cd: File.cwd!(),
        stderr_to_stdout: true,
        env: [{"EVAL_SENTINEL_PATH", sentinel}]
      )

    assert exit_code == 0, "mix ggen_igniter.sync failed:\n#{output}"
    assert output =~ "planned: evaluate test/fixtures/eval_mode_module.exs.eex (mode: eval)"
    refute File.exists?(sentinel)
  end
end
