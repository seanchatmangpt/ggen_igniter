defmodule Ex4pmFixture do
  @moduledoc """
  Chicago-style fixture loader: reads REAL bytes off disk from `~/ex4pm` (the
  research-lab umbrella whose eventual product is `~/beam4pm`) and hands them
  to `Igniter.Test.test_project/1` / bare `Sourceror.parse_string!/1` as real
  source content for `test/ggen_igniter_base_*_test.exs`.

  Why ex4pm: it is a real, differently-shaped ontology-driven umbrella project
  (`ex4pm_contracts`: RDFS ontology, SHACL shapes, WIT world, receipt JSON
  Schema) than beam4pm's `bpm:RecordType`-individuals ontology, which is the
  only ontology shape ggen_igniter's own `mix ggen_igniter.sync` has ever been
  exercised against. Using it as a fixture proves the base `igniter` codemods
  this module feeds generalize past that one shape.

  This module never writes to `~/ex4pm` -- it only calls `File.read!/1`. Every
  consumer of `files/0` feeds the result into `Igniter.Test.test_project/1`
  (an in-memory `%Igniter{}`, per `deps/igniter/lib/igniter/test.ex`) or a raw
  `Sourceror.parse_string!/1` zipper -- neither ever writes back to the real
  `~/ex4pm` working tree; there is no API in either path that does.

  If `~/ex4pm` is absent on a given machine, every test that calls `files/0`
  or `read!/1` raises `File.Error` with a message naming the missing path --
  a loud, honest failure, not a silent fallback to fabricated content.
  """

  @ex4pm_root Path.join(System.user_home!(), "ex4pm")

  @doc "Absolute path to a real file inside `~/ex4pm`."
  @spec path(String.t()) :: String.t()
  def path(relative), do: Path.join(@ex4pm_root, relative)

  @doc "Real file content read from `~/ex4pm` at `relative`."
  @spec read!(String.t()) :: String.t()
  def read!(relative), do: File.read!(path(relative))

  @doc """
  A `files:`-shaped map (relative-path => real content) built from real reads
  of ex4pm's root umbrella `mix.exs`, its `.formatter.exs`, the
  `ex4pm_contracts` sub-app (`mix.exs`, `ex4pm.ttl` ontology, `contracts.ex`,
  `test_helper.exs`), and `ex4pm_runtime`'s real `Application` callback
  module -- enough real, heterogeneous Elixir/RDF source to exercise every
  `Igniter.Code.*`/`Igniter.Project.*` capability under test, all sourced
  from files that already exist in ex4pm today (none authored for this test).
  """
  @spec files() :: %{optional(String.t()) => String.t()}
  def files do
    %{
      "mix.exs" => read!("mix.exs"),
      ".formatter.exs" => read!(".formatter.exs"),
      "apps/ex4pm_contracts/mix.exs" => read!("apps/ex4pm_contracts/mix.exs"),
      "apps/ex4pm_contracts/priv/ontology/ex4pm.ttl" =>
        read!("apps/ex4pm_contracts/priv/ontology/ex4pm.ttl"),
      "apps/ex4pm_contracts/lib/ex4pm/contracts.ex" =>
        read!("apps/ex4pm_contracts/lib/ex4pm/contracts.ex"),
      "apps/ex4pm_contracts/test/test_helper.exs" =>
        read!("apps/ex4pm_contracts/test/test_helper.exs"),
      "apps/ex4pm_runtime/lib/ex4pm/runtime/application.ex" =>
        read!("apps/ex4pm_runtime/lib/ex4pm/runtime/application.ex")
    }
  end

  @doc "Real, unparsed `Ex4pm.Contracts` module source (for bare-zipper tests)."
  @spec contracts_source() :: String.t()
  def contracts_source, do: read!("apps/ex4pm_contracts/lib/ex4pm/contracts.ex")

  @doc "Real, unparsed root umbrella `mix.exs` source (for bare-zipper tests)."
  @spec mix_exs_source() :: String.t()
  def mix_exs_source, do: read!("mix.exs")
end
