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
    {output, exit_code} = System.cmd("mix", ["ggen_igniter.doctor"], cd: File.cwd!(), stderr_to_stdout: true)

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
      System.cmd("mix", ["ggen_igniter.doctor", "--engine", "qlever", "--pack-dir", "test/fixtures/sample-pack"],
        cd: File.cwd!(),
        stderr_to_stdout: true
      )

    refute exit_code == 0, "expected a non-zero exit without --store-id, got 0:\n#{output}"
    assert output =~ "--store-id is missing"
  end
end
