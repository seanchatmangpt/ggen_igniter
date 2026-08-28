defmodule GgenIgniter.DoctorInProcessTest do
  @moduledoc """
  Chicago-style, no-mocks scenario tests of `Mix.Tasks.GgenIgniter.Doctor.igniter/1`
  invoked fully IN-PROCESS (same BEAM as the test runner) via
  `Igniter.Mix.Task.configure_and_run/3` -- the exact real plumbing
  `use Igniter.Mix.Task`'s generated `run/1` calls right after argv parsing,
  minus only the outer `Mix.Task.run("compile")` prerequisite -- rather than a
  `System.cmd("mix", ...)` subprocess.

  ## Why this file exists (real, measured coverage gap)

  Every other doctor test (`test/ggen_igniter_doctor_task_test.exs`,
  `test/ggen_igniter_doctor_fix_e2e_test.exs`) runs `mix ggen_igniter.doctor`
  as a real `System.cmd` subprocess. Those prove the real CLI behavior
  end-to-end, but a subprocess is a SEPARATE BEAM/OS process from the one
  `mix coveralls`/`mix test --cover` instruments -- so every line inside
  `lib/mix/tasks/ggen_igniter.doctor.ex` those subprocess tests exercise is
  invisible to real, instrumented coverage of THIS module (confirmed via a
  real `mix coveralls` baseline run this session: 0.0% real coverage,
  168/168 relevant lines uncovered, despite the module being genuinely
  exercised by real subprocess tests). This file closes that gap by calling
  the exact same public `igniter/1` entry point in-process, so the real
  checks it runs are counted.

  ## Why only the ALL-PASSING scenarios run in-process

  `Mix.Tasks.GgenIgniter.Doctor.igniter/1` calls `System.halt(1)` directly
  (never merely raising) whenever any check comes back `:error` -- see its
  own moduledoc/source. Invoked as a real subprocess, that only kills the
  child OS process; invoked in-process (this file's whole point), it would
  kill the entire `mix test` BEAM, aborting every other test in the suite.
  So this file ONLY exercises real option combinations independently
  confirmed (via a real, fresh run of `mix ggen_igniter.doctor` against
  THIS project, read directly below) to produce zero `:error` results --
  the broken-pack / missing-`--store-id` / hex-metadata-failure `:error`
  scenarios remain correctly covered by the existing subprocess tests only,
  where a real non-zero exit code is the whole point and can't threaten the
  test runner itself.

  Every doctor check that reads/fixes real project state
  (`GgenIgniter.DoctorFixes`'s four rules, `check_version_policy`, git
  status, the NIF compile check, the hex-build check) hard-codes
  `File.cwd!()` internally rather than accepting a fixture directory
  parameter (see that module's own moduledoc: "the real consumer app doctor
  is running inside, never a test-harness scaffold") -- so, unlike
  `GgenIgniter.DoctorFixes`'s own fixture-parameterized test suite
  (`test/ggen_igniter_doctor_fixes_test.exs`), these in-process scenarios
  necessarily check/read THIS actual project's own `mix.exs`/`config/
  config.exs`/git status -- never `--fix`, so strictly read-only, never
  mutating this real checkout.
  """
  use ExUnit.Case, async: false

  import ExUnit.CaptureIO

  alias Mix.Tasks.GgenIgniter.Doctor

  # Real, in-process invocation of the real `mix ggen_igniter.doctor` Igniter
  # task -- the exact same `parse_argv/1` + `igniter/1` sequence
  # `use Igniter.Mix.Task`'s generated `run/1` performs after argv parsing
  # (`Igniter.Mix.Task.configure_and_run/3` is that shared, public plumbing),
  # mirroring `GgenIgniter.SyncControllerDelegationTest`'s own `run_sync!/1`
  # helper for the sibling `ggen_igniter.sync` task.
  defp run_doctor!(argv) do
    Igniter.new()
    |> Map.put(:task, "ggen_igniter.doctor")
    |> Igniter.Mix.Task.configure_and_run(Doctor, argv)
  end

  test "no --pack: real environment/project-hygiene checks all pass in-process, real notice added" do
    {igniter, output} =
      with_io(fn -> run_doctor!([]) end)

    assert [notice] = igniter.notices
    assert notice == "ggen_igniter.doctor: all checks passed (see output above)"

    # Real per-check lines actually printed by the real check functions --
    # this project's own real, current Elixir/OTP/dep versions, not a fixture.
    assert output =~ ~r/✔ Elixir #{Regex.escape(System.version())} \/ OTP/
    assert output =~ "✔ rdf"
    assert output =~ "igniter"

    # No --pack was given: the four pack-scoped checks (9-12) never ran.
    # (Note: the sparql-advisory warning line legitimately mentions "gate
    # queries" in prose, so this checks for the pack-check's own specific
    # "N gate quer(y|ies) found: ..." phrasing, not a bare substring.)
    refute output =~ "ontology.ttl"
    refute output =~ ~r/gate quer(y|ies) found:/

    # Real project-hygiene rule checks (GgenIgniter.DoctorFixes.default_rules/0)
    # against THIS project's own real mix.exs/config/config.exs -- read-only
    # (no --fix passed), so this assertion is a live fact about the real repo,
    # not a fixture.
    assert output =~ "igniter dependency"

    assert output =~ "config :dcatr, env: ... already present" or
             output =~ "config :dcatr, env"

    # Real NIF compile check and real oxigraph functional smoke test.
    assert output =~ ~r/(native\/ggen_graph_nif|priv\/native\/ggen_graph_nif\.so)/
    assert output =~ ~r/GgenIgniter\.Query\.Oxigraph real SELECT query.*returned \d+ row\(s\)/

    # Real, current git status of this checkout -- either clean or dirty is a
    # real fact, but the check itself must have run and reported one or the
    # other (never silently skipped, never a fabricated pass).
    assert output =~ "git clean" or output =~ ~r/git dirty \(\d+ uncommitted change\(s\)\)/
  end

  test "--pack-dir against the real sample-pack fixture: pack checks 9-12 all pass in-process" do
    {igniter, output} =
      with_io(fn -> run_doctor!(["--pack-dir", "test/fixtures/sample-pack"]) end)

    assert [notice] = igniter.notices
    assert notice == "ggen_igniter.doctor: all checks passed (see output above)"

    assert output =~ ~r/✔ ontology\.ttl parses \(\d+ triples\)/
    assert output =~ "✔ 4 gate queries found: spec, sections, entities, fields"
    assert output =~ "✔ 1 template found: extension.ex.eex"
    assert output =~ "✔ all 4 gate queries parse"
  end

  test "--hex-check runs a real mix hex.build in-process and reports real package metadata" do
    {igniter, output} = with_io(fn -> run_doctor!(["--hex-check"]) end)

    assert [notice] = igniter.notices
    assert notice == "ggen_igniter.doctor: all checks passed (see output above)"

    assert output =~ "mix hex.build succeeded and package metadata is present"
    assert output =~ "Description:"
  end

  test "without --hex-check, mix hex.build never runs (in-process, same as the subprocess behavior)" do
    {igniter, output} = with_io(fn -> run_doctor!([]) end)

    assert [_notice] = igniter.notices
    refute output =~ "hex.build"
  end
end
