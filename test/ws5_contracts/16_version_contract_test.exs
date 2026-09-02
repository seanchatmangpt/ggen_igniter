defmodule GgenIgniter.WS5.VersionContractTest do
  @moduledoc """
  Chicago-style: reads the real `mix.exs` and `CHANGELOG.md` files on disk —
  no hardcoded version literal. Asserts the real, load-bearing invariant
  (`mix.exs`'s `version:` key follows CalVer and agrees with `CHANGELOG.md`'s
  topmost `## vX.Y.Z` heading) rather than pinning one release's exact
  string, which breaks on every version bump for no real regression (see
  `test/ggen_igniter_doctor_task_test.exs`'s `check_version_policy` test,
  which encodes this same invariant and is the actual source of truth this
  test mirrors, kept independent so a `mix ggen_igniter.doctor` regression
  and a raw `mix.exs`/CHANGELOG.md drift are each caught by a different,
  non-redundant path).
  """
  use ExUnit.Case, async: true

  test "mix.exs version: follows CalVer (YY.M[M].P) and agrees with CHANGELOG.md's top entry" do
    mix_exs = File.read!("mix.exs")
    changelog = File.read!("CHANGELOG.md")

    assert [_, mix_version] = Regex.run(~r/version:\s*"([^"]+)"/, mix_exs)

    assert mix_version =~ ~r/^\d{2}\.\d{1,2}\.\d+$/,
           "mix.exs version #{inspect(mix_version)} does not match this project's real CalVer shape YY.M[M].P"

    assert [_, changelog_top_version] = Regex.run(~r/^##\s*v([\d.]+)\s*$/m, changelog)

    assert mix_version == changelog_top_version,
           "mix.exs version #{inspect(mix_version)} must equal CHANGELOG.md's top entry " <>
             "#{inspect(changelog_top_version)} -- this project's real versioning convention " <>
             "(no git tags recorded either version independently; see " <>
             "test/ggen_igniter_doctor_task_test.exs's check_version_policy test)"

    assert mix_exs =~ ~s(source_ref: "v#{mix_version}"),
           "docs' source_ref literal must stay in sync with version: -- see mix.exs's own comment on this pairing"
  end
end
