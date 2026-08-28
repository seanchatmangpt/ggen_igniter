defmodule GgenIgniter.DoctorTaskTest do
  @moduledoc """
  Chicago-style, no-mocks proof that `mix ggen_igniter.doctor` runs as a real
  subprocess and reports real pass/fail output for each checklist item --
  against `test/fixtures/sample-pack/` (all pack checks pass) and
  `test/fixtures/broken-pack/` (deliberately broken: no ontology.ttl, no
  templates/, an unparseable gate query -- exercises the real :error branches).
  """
  use ExUnit.Case, async: false

  @moduletag :integration

  test "mix ggen_igniter.doctor with no --pack only runs the environment checks and passes" do
    {output, exit_code} =
      System.cmd("mix", ["ggen_igniter.doctor"], cd: File.cwd!(), stderr_to_stdout: true)

    assert exit_code == 0, "mix ggen_igniter.doctor failed:\n#{output}"
    assert output =~ ~r/✔ Elixir .* \/ OTP/
    assert output =~ "✔ rdf"
    refute output =~ "ontology.ttl"
  end

  test "mix ggen_igniter.doctor --pack-dir against a real valid pack passes every pack check" do
    {output, exit_code} =
      System.cmd("mix", ["ggen_igniter.doctor", "--pack-dir", "test/fixtures/sample-pack"],
        cd: File.cwd!(),
        stderr_to_stdout: true
      )

    assert exit_code == 0, "mix ggen_igniter.doctor failed:\n#{output}"
    assert output =~ ~r/✔ ontology\.ttl parses \(\d+ triples\)/
    assert output =~ "✔ 4 gate queries found: spec, sections, entities, fields"
    assert output =~ "✔ 1 template found: extension.ex.eex"
    assert output =~ "✔ all 4 gate queries parse"
    assert output =~ "ggen_igniter.doctor: all checks passed"
  end

  test "mix ggen_igniter.doctor --pack-dir against a real broken pack fails with real per-check errors" do
    {output, exit_code} =
      System.cmd("mix", ["ggen_igniter.doctor", "--pack-dir", "test/fixtures/broken-pack"],
        cd: File.cwd!(),
        stderr_to_stdout: true
      )

    refute exit_code == 0, "expected a non-zero exit for the broken pack, got 0:\n#{output}"
    assert output =~ "✘ ontology.ttl missing at test/fixtures/broken-pack/ontology.ttl"
    assert output =~ "✘ no *.eex/*.tmpl files in test/fixtures/broken-pack/templates"
    assert output =~ ~r/✘ bad \(test\/fixtures\/broken-pack\/gates\/010_bad\.rq\) failed to parse/
    assert output =~ "one or more checks failed"
  end

  test "mix ggen_igniter.doctor --engine qlever without --store-id fails the reachability check" do
    {output, exit_code} =
      System.cmd(
        "mix",
        ["ggen_igniter.doctor", "--engine", "qlever", "--pack-dir", "test/fixtures/sample-pack"],
        cd: File.cwd!(),
        stderr_to_stdout: true
      )

    refute exit_code == 0, "expected a non-zero exit without --store-id, got 0:\n#{output}"
    assert output =~ "--store-id is missing"
  end

  test "mix ggen_igniter.doctor reports the real NIF compile check and oxigraph smoke test" do
    {output, exit_code} =
      System.cmd("mix", ["ggen_igniter.doctor"], cd: File.cwd!(), stderr_to_stdout: true)

    assert exit_code == 0, "mix ggen_igniter.doctor failed:\n#{output}"
    assert output =~ ~r/✔ (native\/ggen_graph_nif|priv\/native\/ggen_graph_nif\.so)/
    assert output =~ ~r/✔ GgenIgniter\.Query\.Oxigraph real SELECT query.*returned \d+ row\(s\)/
  end

  test "mix ggen_igniter.doctor --hex-check runs a real mix hex.build and checks package metadata" do
    {output, exit_code} =
      System.cmd("mix", ["ggen_igniter.doctor", "--hex-check"],
        cd: File.cwd!(),
        stderr_to_stdout: true
      )

    assert output =~ "mix hex.build"
    assert exit_code == 0, "mix ggen_igniter.doctor --hex-check failed unexpectedly:\n#{output}"
  end

  test "mix ggen_igniter.doctor without --hex-check never runs mix hex.build" do
    {output, exit_code} =
      System.cmd("mix", ["ggen_igniter.doctor"], cd: File.cwd!(), stderr_to_stdout: true)

    assert exit_code == 0, "mix ggen_igniter.doctor failed:\n#{output}"
    refute output =~ "hex.build"
  end

  test "mix ggen_igniter.doctor's check_version_policy reports the REAL current state of " <>
         "this project's own mix.exs version vs. CHANGELOG.md's top entry" do
    # Ground truth, read fresh from the real files on disk (Chicago-style: no
    # mocked/assumed content) -- this project's own real, observed versioning
    # convention is "mix.exs's version: literal mirrors CHANGELOG.md's topmost
    # `## vX` entry heading" (there are no git tags at all in this repo's real
    # history: `git tag --list` returns empty).
    mix_exs_source = File.read!(Path.join(File.cwd!(), "mix.exs"))
    [_, mix_version] = Regex.run(~r/version:\s*"([^"]+)"/, mix_exs_source)

    changelog_source = File.read!(Path.join(File.cwd!(), "CHANGELOG.md"))
    [_, changelog_version] = Regex.run(~r/^##\s+v(\S+)/m, changelog_source)

    {output, exit_code} =
      System.cmd("mix", ["ggen_igniter.doctor"], cd: File.cwd!(), stderr_to_stdout: true)

    assert exit_code == 0, "mix ggen_igniter.doctor failed:\n#{output}"

    if mix_version == changelog_version do
      assert output =~
               ~r/✔ mix\.exs version #{Regex.escape(inspect(mix_version))} matches CHANGELOG\.md's top entry \(## v#{Regex.escape(changelog_version)}\) -- MATCH/
    else
      assert output =~
               ~r/⚠ MISMATCH: mix\.exs version #{Regex.escape(inspect(mix_version))} but CHANGELOG\.md's top entry \(## v#{Regex.escape(changelog_version)}\) says it should be #{Regex.escape(inspect(changelog_version))}/
    end
  end

  test "mix ggen_igniter.doctor --json emits exactly one valid JSON document with nothing " <>
         "trailing on the all-checks-passed path" do
    # Deliberately NOT stderr_to_stdout here: strict single-document JSON
    # parsing is a stdout-only contract, and this repo's mix.exs currently
    # emits an unrelated `preferred_cli_env` deprecation warning on stderr
    # that would otherwise corrupt this test's own stdout-line-count check
    # without reflecting the real Igniter-footer-on-stdout bug under test.
    {output, exit_code} =
      System.cmd("mix", ["ggen_igniter.doctor", "--json"], cd: File.cwd!())

    assert exit_code == 0, "mix ggen_igniter.doctor --json failed:\n#{output}"

    lines = output |> String.split("\n", trim: true)
    assert length(lines) == 1, "expected exactly one line of stdout, got:\n#{output}"

    payload = Jason.decode!(hd(lines))
    assert payload["ok"] == true
    assert payload["exit_code"] == 0
    assert is_list(payload["checks"])
    assert payload["checks"] != []

    # A real subprocess-level regression test for the specific bug this
    # closes: Igniter's own "No proposed content changes!" footer must never
    # follow the JSON document on stdout.
    refute output =~ "No proposed content changes"
    refute output =~ "Igniter:"
  end

  test "mix ggen_igniter.doctor --json emits exactly one valid JSON document with real " <>
         "findings when checks fail" do
    # See the all-pass test above for why stderr is not merged here.
    {output, exit_code} =
      System.cmd(
        "mix",
        ["ggen_igniter.doctor", "--pack-dir", "test/fixtures/broken-pack", "--json"],
        cd: File.cwd!()
      )

    refute exit_code == 0, "expected a non-zero exit for the broken pack, got 0:\n#{output}"

    lines = output |> String.split("\n", trim: true)
    assert length(lines) == 1, "expected exactly one line of stdout, got:\n#{output}"

    payload = Jason.decode!(hd(lines))
    assert payload["ok"] == false
    assert payload["exit_code"] == 1
    assert Enum.any?(payload["checks"], fn c -> c["status"] == "error" end)

    refute output =~ "No proposed content changes"
    refute output =~ "Igniter:"
  end

  test "mix ggen_igniter.doctor --json output parses via a real external python3 json.tool " <>
         "subprocess as exactly one document (all-pass path)" do
    # See the all-pass test above for why stderr is not merged here.
    {output, exit_code} =
      System.cmd("mix", ["ggen_igniter.doctor", "--json"], cd: File.cwd!())

    assert exit_code == 0, "mix ggen_igniter.doctor --json failed:\n#{output}"

    tmp_path =
      Path.join(System.tmp_dir!(), "doctor_json_#{System.unique_integer([:positive])}.json")

    File.write!(tmp_path, output)
    on_exit(fn -> File.rm(tmp_path) end)

    case System.find_executable("python3") do
      nil ->
        :ok

      python3 ->
        {py_output, py_exit} =
          System.cmd(python3, ["-m", "json.tool", tmp_path], stderr_to_stdout: true)

        assert py_exit == 0,
               "python3 -m json.tool rejected the --json output as invalid/extra-data JSON:\n#{py_output}"
    end
  end

  test "GgenIgniter.DoctorFixes.check_version_policy/1 matches this project's real current " <>
         "mix.exs/CHANGELOG.md state directly (no subprocess)" do
    project_dir = File.cwd!()

    mix_exs_source = File.read!(Path.join(project_dir, "mix.exs"))
    [_, mix_version] = Regex.run(~r/version:\s*"([^"]+)"/, mix_exs_source)

    changelog_source = File.read!(Path.join(project_dir, "CHANGELOG.md"))
    [_, changelog_version] = Regex.run(~r/^##\s+v(\S+)/m, changelog_source)

    result = GgenIgniter.DoctorFixes.check_version_policy(project_dir)

    if mix_version == changelog_version do
      assert {:ok, msg} = result
      assert msg =~ "MATCH"
    else
      assert {:fixable, msg} = result
      assert msg =~ "MISMATCH"
    end
  end
end
