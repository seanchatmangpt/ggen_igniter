defmodule Ex4pmFixture do
  @moduledoc """
  Chicago-style fixture loader: reads REAL bytes off disk from `~/ex4pm` (the
  research-lab project whose eventual product is `~/beam4pm`) and hands them
  to `Igniter.Test.test_project/1` / bare `Sourceror.parse_string!/1` as real
  source content for `test/ggen_igniter_base_*_test.exs`.

  Why ex4pm: it is a real, differently-shaped ontology-driven project
  (RDFS ontology, SHACL shapes, WIT world, receipt JSON Schema) than
  beam4pm's `bpm:RecordType`-individuals ontology, which is the only
  ontology shape ggen_igniter's own `mix ggen_igniter.sync` has ever been
  exercised against. Using it as a fixture proves the base `igniter` codemods
  this module feeds generalize past that one shape.

  ex4pm was originally laid out as an `apps/*` umbrella and has since been
  flattened to a single top-level app (`lib/ex4pm/...`, `priv/...`,
  `test/...`); the paths below track ex4pm's current real, on-disk layout,
  not its historical umbrella shape.

  This module never writes to `~/ex4pm` -- it only calls `File.read!/1` (or,
  for the pinned umbrella-shaped files below, `git show`). Every consumer of
  `files/0` feeds the result into `Igniter.Test.test_project/1` (an in-memory
  `%Igniter{}`, per `deps/igniter/lib/igniter/test.ex`) or a raw
  `Sourceror.parse_string!/1` zipper -- neither ever writes back to the real
  `~/ex4pm` working tree; there is no API in either path that does.

  If `~/ex4pm` is absent on a given machine, every test that calls `files/0`
  or `read!/1` raises `File.Error` with a message naming the missing path --
  a loud, honest failure, not a silent fallback to fabricated content.

  `~/ex4pm` itself flattened from an umbrella into a single hex-publishable
  library at commit `725f495` ("refactor: flatten umbrella into a single
  hex-publishable library") -- its live `mix.exs` no longer has an
  `apps_path`/list-literal `deps:`, and `apps/ex4pm_contracts/` no longer
  exists at all. `mix_exs_source/0` and `contracts_source/0` below need that
  older umbrella shape specifically (a real `deps: [{...}, {...}]` list
  literal and a real `@artifacts %{...}` map), so they pin to the real git
  blob at `725f495^` (the last commit before the flatten) via `git show`
  instead of reading the live, since-restructured working tree -- still real
  content ex4pm actually had, just addressed by SHA instead of by mutable
  path, so it can't drift again the way live-`HEAD` reads already have twice
  in this repo's history (per the MixProject suite's own stale-content
  failures).
  """

  @ex4pm_root Path.join(System.user_home!(), "ex4pm")
  @ex4pm_umbrella_rev "725f495^"

  @doc "Absolute path to a real file inside `~/ex4pm`."
  @spec path(String.t()) :: String.t()
  def path(relative), do: Path.join(@ex4pm_root, relative)

  @doc "Real file content read from `~/ex4pm` at `relative`."
  @spec read!(String.t()) :: String.t()
  def read!(relative), do: File.read!(path(relative))

  @doc """
  Real file content read from `~/ex4pm`'s git history at `relative`, as of
  the pinned pre-flatten umbrella revision `#{@ex4pm_umbrella_rev}`. Used for
  fixture files whose current, live-`HEAD` shape no longer matches what the
  test exercises (see moduledoc) -- still a real historical blob via
  `git show`, not fabricated content, just pinned instead of tracking a
  working tree that has since been restructured out from under it.
  """
  @spec read_pinned!(String.t()) :: String.t()
  def read_pinned!(relative) do
    case System.cmd("git", ["show", "#{@ex4pm_umbrella_rev}:#{relative}"],
           cd: @ex4pm_root,
           stderr_to_stdout: true
         ) do
      {content, 0} ->
        content

      {output, status} ->
        raise File.Error,
          reason: :enoent,
          action: "git show #{@ex4pm_umbrella_rev}:#{relative} (exit #{status}): #{output}",
          path: path(relative)
    end
  end

  @doc """
  A `files:`-shaped map (relative-path => real content) built from real reads
  of ex4pm's real, current top-level `mix.exs`, its `.formatter.exs`, the
  `ex4pm.ttl` ontology, `contracts.ex`, `test_helper.exs`, and the real
  `Application` callback module -- enough real, heterogeneous Elixir/RDF
  source to exercise every `Igniter.Code.*`/`Igniter.Project.*` capability
  under test, all sourced from files that already exist in ex4pm today (none
  authored for this test).
  """
  @spec files() :: %{optional(String.t()) => String.t()}
  def files do
    %{
      "mix.exs" => read!("mix.exs"),
      ".formatter.exs" => read!(".formatter.exs"),
      "priv/ontology/ex4pm.ttl" => read!("priv/ontology/ex4pm.ttl"),
      "lib/ex4pm/contracts.ex" => read!("lib/ex4pm/contracts.ex"),
      "test/test_helper.exs" => read!("test/test_helper.exs"),
      "lib/ex4pm/application.ex" => read!("lib/ex4pm/application.ex")
    }
  end

  @doc """
  Real, unparsed `Ex4pm.Contracts` module source (for bare-zipper tests),
  pinned to the pre-flatten umbrella revision -- see moduledoc. The live
  `lib/ex4pm/contracts.ex` has no `@artifacts` map at all after the flatten.
  """
  @spec contracts_source() :: String.t()
  def contracts_source, do: read_pinned!("apps/ex4pm_contracts/lib/ex4pm/contracts.ex")

  @doc """
  Real, unparsed root umbrella `mix.exs` source (for bare-zipper tests),
  pinned to the pre-flatten umbrella revision -- see moduledoc. The live
  `mix.exs` extracted `deps()` into a private function and no longer has a
  list-literal `deps:` key in `project/0`.
  """
  @spec mix_exs_source() :: String.t()
  def mix_exs_source, do: read_pinned!("mix.exs")

  # --- Pinned historical ex4pm shapes -------------------------------------
  #
  # `~/ex4pm` was a real umbrella (`apps_path: "apps"`, per-app `mix.exs`
  # with inline `deps: [...]`, no `defp deps do`) through commit `650ccc8`
  # ("chore(release): bump version to 26.8.28"). Commit `725f495` ("refactor:
  # flatten umbrella into a single hex-publishable library") later collapsed
  # it into a single non-umbrella project -- so reading `~/ex4pm`'s *current*
  # mix.exs no longer exercises the umbrella/`apps_path`/inline-deps codemod
  # paths this suite targets, and drifts every time ex4pm's own version
  # bumps land, independent of any change here.
  #
  # These two files are verbatim `git show 650ccc8:mix.exs` /
  # `git show 650ccc8:apps/ex4pm_contracts/mix.exs` snapshots, checked into
  # this repo under `test/fixtures/ex4pm_pinned/` so the real umbrella shape
  # ex4pm used to have keeps being exercised without depending on `~/ex4pm`'s
  # current, unrelated-to-this-suite state. Still real, once-live project
  # source -- never hand-authored to match the library's assumptions -- just
  # pinned instead of re-read from a mutable external working tree.

  @pinned_root Path.join([__DIR__, "..", "fixtures", "ex4pm_pinned"])

  @doc "Pinned real umbrella root `mix.exs` (ex4pm @ 650ccc8, `apps_path: \"apps\"`, `version: \"26.8.28\"`)."
  @spec pinned_umbrella_mix_exs_source() :: String.t()
  def pinned_umbrella_mix_exs_source, do: File.read!(Path.join(@pinned_root, "mix.exs"))

  @doc "Pinned real sub-app `mix.exs` (ex4pm @ 650ccc8, inline `deps: [...]`, no `defp deps do`)."
  @spec pinned_contracts_mix_exs_source() :: String.t()
  def pinned_contracts_mix_exs_source,
    do: File.read!(Path.join(@pinned_root, "apps/ex4pm_contracts/mix.exs"))
end
