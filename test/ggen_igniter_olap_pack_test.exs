defmodule GgenIgniter.OlapPackTest do
  @moduledoc """
  Chicago-style, no-mocks proof that `priv/ggen/olap-pack` (a reusable
  manufacturing pack for OLAP-style slice/dice/roll_up/drill_down over an
  OCEL-shaped canonical event-log IR, ported from
  `~/ex4pm/apps/ex4pm_core/lib/ex4pm/core/olap.ex`) resolves via `mix
  ggen_igniter.sync --pack olap-pack` as a real subprocess and renders real,
  parseable Elixir source containing every OLAP operation.

  Real collaborators throughout: a real `mix` subprocess, the real
  `priv/ggen/olap-pack/ontology.ttl`/`gates/*.rq`/`templates/*.eex`, real
  `Code.string_to_quoted!/1` parsing of the generated output -- no mocked
  query engine, no fabricated bindings.
  """
  use ExUnit.Case, async: false

  @moduletag :integration

  test "mix ggen_igniter.sync --pack olap-pack renders real, parseable slice/dice/roll_up/drill_down source" do
    out_dir =
      Path.join(
        System.tmp_dir!(),
        "ggen_igniter_olap_pack_test_#{System.unique_integer([:positive])}"
      )

    File.rm_rf!(out_dir)
    on_exit(fn -> File.rm_rf!(out_dir) end)

    out_path = Path.join(out_dir, "olap.ex")

    args = [
      "ggen_igniter.sync",
      # Pinned to sparql for the same reason ggen_igniter_sync_pack_test.exs
      # pins it: a real, disclosed engine-shape difference in how typed
      # literals come back (oxigraph vs sparql), orthogonal to what this
      # pack-resolution/render test is checking.
      "--engine",
      "sparql",
      "--pack",
      "olap-pack",
      "--out",
      out_path,
      "--manifest-dir",
      out_dir,
      "--verify-cwd",
      File.cwd!()
    ]

    {output, exit_code} = System.cmd("mix", args, cd: File.cwd!(), stderr_to_stdout: true)

    assert exit_code == 0, "mix ggen_igniter.sync --pack olap-pack failed:\n#{output}"
    assert output =~ "ggen_igniter: wrote #{out_path}"
    assert File.exists?(out_path)

    content = File.read!(out_path)

    # Real generated source actually parses as valid Elixir.
    assert {:defmodule, _, _} = Code.string_to_quoted!(content)

    assert content =~ "defmodule Ex4pm.Core.OLAP do"
    assert content =~ "alias Ex4pm.EventLog, as: EventLog"
    assert content =~ "alias Ex4pm.Event, as: Event"

    # Every OLAP operation this pack manufactures must be present as a real
    # public function definition, not just mentioned in prose/docs.
    assert content =~ "def slice(%EventLog{} = log, dimension, value) do"

    assert content =~
             "def dice(%EventLog{} = log, filters) when is_list(filters) do"

    assert content =~
             "def roll_up(%EventLog{} = log, dimension, aggregate_fn) when is_function(aggregate_fn, 1) do"

    assert content =~
             "def drill_down(%EventLog{} = log, dimension, finer_dimension) do"
  end
end
