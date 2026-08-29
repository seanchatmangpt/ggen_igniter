defmodule GgenIgniterCliTasksQuirksTest do
  @moduledoc """
  Chicago-style: real subprocesses only (`System.cmd("mix", [...])` against
  this actual project's built `mix` executable and real task modules -- no
  mocking of `Mix.Task`/`System.cmd`/stdout).

  Regression coverage, parametrized over every real `mix ggen_igniter.*` task,
  for the two `Igniter.Mix.Task` base-class quirks documented in
  `lib/mix/tasks/CLAUDE.md`'s "Known Igniter.Mix.Task base-class quirks"
  section and already fixed for real in commits `6c2f109` and `b184d907`:

    1. `--help` vs `-h` must produce equivalently concise output (never the
       raw Igniter/Mix moduledoc dump) for every task.
    2. A `--json` success path must emit exactly one valid JSON document with
       nothing trailing (no Igniter "No proposed content changes!" footer).

  Adding a 5th task later means adding one entry to `@tasks` below (and, if it
  supports `--json`, one entry to `@json_capable_tasks`) -- no new test logic.
  """
  use ExUnit.Case, async: true

  # Every real `mix ggen_igniter.*` task, with the minimal extra argv each one
  # needs alongside `--help`/`-h` to reach its own help-and-halt branch without
  # tripping an unrelated "missing required arg" error first. `--help`/`-h` are
  # checked before any other validation in all four tasks (see
  # `lib/mix/tasks/CLAUDE.md`), so no task actually needs extra args here today
  # -- the field exists so a future 5th task with different plumbing (e.g. a
  # required positional argument checked before its own `--help` handling)
  # can still be dropped into this same list without changing the test logic.
  @tasks [
    {"ggen_igniter.sync", []},
    {"ggen_igniter.plan", []},
    {"ggen_igniter.doctor", []},
    {"ggen_igniter.replay", []}
  ]

  # Tasks that support `--json`. `ggen_igniter.sync` has NO `--json` mode at
  # all (see `lib/mix/tasks/CLAUDE.md` -- its success path always calls
  # `Igniter.add_notice/2` and never needed the halt(0) fix, since the
  # corruption case this quirk covers can't arise for it), so it is
  # deliberately excluded here, not silently expected to comply.
  # `ggen_igniter.replay` also technically supports `--json` but requires a
  # real receipt file positional arg to reach a *success* path -- covered
  # separately, not lumped into this generic list, since a shared "just run
  # --json with no other args" invocation is not a meaningful success-path
  # test for it (`--json` there needs `--json` PLUS a loadable receipt to
  # prove the "no trailing bytes" contract on the meaningful branch, not just
  # its own invalid-invocation JSON branch, which is a different code path).
  @json_capable_tasks ["ggen_igniter.plan", "ggen_igniter.doctor"]

  describe "--help vs -h parity (AR-11 regression, parametrized over every real task)" do
    for {task, extra_args} <- @tasks do
      @tag task: task
      test "mix #{task} --help and -h produce equivalently concise, non-Igniter-moduledoc-dump output (#{task})" do
        task = unquote(task)
        extra_args = unquote(extra_args)

        # Deliberately NOT stderr_to_stdout: this repo's mix.exs currently
        # emits an unrelated `preferred_cli_env` deprecation warning (and,
        # under concurrent async compilation, a "Waiting for lock on the
        # build directory" message) on stderr that would otherwise corrupt
        # this test's own byte-identical stdout comparison with noise
        # unrelated to the real --help/-h parity bug under test.
        {help_output, help_exit} =
          System.cmd("mix", [task, "--help"] ++ extra_args, cd: File.cwd!())

        {h_output, h_exit} =
          System.cmd("mix", [task, "-h"] ++ extra_args, cd: File.cwd!())

        assert help_exit == 0, "mix #{task} --help exited #{help_exit}:\n#{help_output}"
        assert h_exit == 0, "mix #{task} -h exited #{h_exit}:\n#{h_output}"

        # The real, concrete signature of the AR-11 bug: Igniter's generic
        # `mix help <task>` renderer dumps the ENTIRE raw @moduledoc, which
        # for every one of these tasks is a multi-hundred-line document full
        # of "##" Markdown headers and "Example" sections well beyond a
        # concise USAGE/FLAGS block. Asserting neither form contains a
        # Markdown header line is a real, task-independent proxy for "this is
        # the concise help text, not the raw moduledoc dump" -- exercised
        # identically across all four tasks, so a 5th task regressing into
        # the raw-moduledoc branch fails the same way.
        refute help_output =~ ~r/^##\s/m,
               "mix #{task} --help printed what looks like the raw moduledoc " <>
                 "(a Markdown \"## \" header line), not concise help:\n#{help_output}"

        refute h_output =~ ~r/^##\s/m,
               "mix #{task} -h printed what looks like the raw moduledoc " <>
                 "(a Markdown \"## \" header line), not concise help:\n#{h_output}"

        # Byte-identical modulo the flag itself never appearing verbatim in
        # the body (it doesn't, for any of these four tasks' concise help
        # text) -- so a straight equality check is the real, strongest form
        # of "both forms produce the same output" this test can make.
        assert help_output == h_output,
               "mix #{task} --help and -h produced different output.\n\n" <>
                 "--help:\n#{help_output}\n\n-h:\n#{h_output}"

        # Both forms should be well under the ~184-line raw-moduledoc size
        # this bug historically produced (56 lines was the real concise size
        # observed for sync.ex in the b184d907 commit message) -- a generous
        # upper bound that would still catch a full moduledoc dump without
        # being brittle to small concise-text edits.
        line_count = help_output |> String.split("\n", trim: true) |> length()

        assert line_count < 100,
               "mix #{task} --help printed #{line_count} lines -- looks like a raw " <>
                 "moduledoc dump, not concise help:\n#{help_output}"
      end
    end
  end

  describe "--json emits exactly one valid JSON document (parametrized over --json-capable tasks)" do
    for task <- @json_capable_tasks do
      @tag task: task
      test "mix #{task} --json produces exactly one valid JSON document via a real external python3 json.tool round-trip (#{task})" do
        task = unquote(task)

        args =
          case task do
            "ggen_igniter.plan" ->
              [
                "--pack-dir",
                "test/fixtures/sample-pack",
                "--out",
                "tmp_out/cli_quirks_plan_probe.ex",
                "--json"
              ]

            "ggen_igniter.doctor" ->
              ["--json"]
          end

        {output, exit_code} =
          System.cmd("mix", [task] ++ args, cd: File.cwd!())

        # exit codes vary by task/path (0 for a clean plan/doctor pass, 0 for
        # --help); this test's job is the single-JSON-document contract, not
        # re-asserting each task's own exit-code semantics (already covered
        # by that task's own test file).
        #
        # NOTE: "single document" does NOT mean "single line" -- `plan.ex`
        # calls `Jason.encode!(..., pretty: true)` (multi-line JSON is still
        # exactly one document), while `doctor.ex` emits compact single-line
        # JSON. The real, task-independent proxy for "exactly one document,
        # nothing trailing" is that the ENTIRE trimmed stdout decodes as one
        # JSON value with `Jason.decode/1` -- which fails outright on any
        # trailing non-JSON bytes (e.g. Igniter's own footer) appended after
        # a validly-closed document.
        trimmed_output = String.trim(output)

        assert {:ok, _decoded} = Jason.decode(trimmed_output),
               "mix #{task} #{Enum.join(args, " ")} stdout did not decode as exactly one " <>
                 "JSON document (likely trailing bytes after a valid document):\n#{output}\n" <>
                 "exit: #{exit_code}"

        refute output =~ "No proposed content changes",
               "mix #{task} #{Enum.join(args, " ")} leaked Igniter's own footer text " <>
                 "after --json output:\n#{output}"

        tmp_path =
          Path.join(
            System.tmp_dir!(),
            "cli_quirks_#{task}_#{System.unique_integer([:positive])}.json"
          )

        File.write!(tmp_path, output)
        on_exit(fn -> File.rm(tmp_path) end)

        case System.find_executable("python3") do
          nil ->
            # No python3 on this toolchain -- the in-process Jason round-trip
            # above already checked the single-document contract, just
            # without the extra external-tool confirmation.
            :ok

          python3 ->
            {py_output, py_exit} =
              System.cmd(python3, ["-m", "json.tool", tmp_path], stderr_to_stdout: true)

            assert py_exit == 0,
                   "python3 -m json.tool rejected mix #{task} --json output as invalid/" <>
                     "extra-data JSON:\n#{py_output}\n\nraw output:\n#{output}"
        end
      end
    end
  end

  test "ggen_igniter.replay is a plain Mix.Task (own OptionParser) and never had the AR-11 " <>
         "--help/-h split bug in the first place -- both forms already agree" do
    {help_output, help_exit} =
      System.cmd("mix", ["ggen_igniter.replay", "--help"], cd: File.cwd!())

    {h_output, h_exit} =
      System.cmd("mix", ["ggen_igniter.replay", "-h"], cd: File.cwd!())

    assert help_exit == 0, "mix ggen_igniter.replay --help exited #{help_exit}:\n#{help_output}"
    assert h_exit == 0, "mix ggen_igniter.replay -h exited #{h_exit}:\n#{h_output}"
    assert help_output == h_output

    refute help_output =~ ~r/^##\s/m,
           "mix ggen_igniter.replay --help printed what looks like a raw moduledoc dump:\n#{help_output}"
  end
end
