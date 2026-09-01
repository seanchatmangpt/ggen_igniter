defmodule GgenIgniter.SyncOcel2EkgPackTaskTest do
  @moduledoc """
  Chicago-style, no-mocks proof that `mix ggen_igniter.sync --pack ocel2-ekg-pack`
  manufactures a real, compiling OCEL 2.0 / Event-Knowledge-Graph-style IR module
  parameterized by `priv/ggen/ocel2-ekg-pack/ontology.ttl`'s `ekg:example_ir`
  individual, mirroring `ggen_igniter_sync_pack_test.exs`'s real-subprocess
  conventions. Asserts on the real generated Elixir source text (compiles via
  `Code.string_to_quoted!/1`, contains the expected module/function names) --
  never on mocked interactions.
  """
  use ExUnit.Case, async: false

  @moduletag :integration

  test "mix ggen_igniter.sync --pack ocel2-ekg-pack writes a real, compiling OCEL2 IR module" do
    out_dir =
      Path.join(
        System.tmp_dir!(),
        "ggen_igniter_sync_ocel2_ekg_pack_test_#{System.unique_integer([:positive])}"
      )

    File.rm_rf!(out_dir)
    on_exit(fn -> File.rm_rf!(out_dir) end)

    out_path = Path.join(out_dir, "ocel2_example.ex")

    args = [
      "ggen_igniter.sync",
      "--engine",
      "sparql",
      "--pack",
      "ocel2-ekg-pack",
      "--out",
      out_path,
      "--manifest-dir",
      out_dir,
      "--verify-cwd",
      File.cwd!()
    ]

    {output, exit_code} = System.cmd("mix", args, cd: File.cwd!(), stderr_to_stdout: true)

    assert exit_code == 0, "mix ggen_igniter.sync --pack ocel2-ekg-pack failed:\n#{output}"
    assert output =~ "ggen_igniter: wrote #{out_path}"

    assert File.exists?(out_path)
    content = File.read!(out_path)

    # Real generated Elixir must actually parse.
    assert {:__block__, _, _} = Code.string_to_quoted!(content)

    # Module names come from the ontology individual's ekg:namespace
    # ("GgenIgniter.Ocel2Example") -- not hardcoded to "Ex4pm".
    assert content =~ "defmodule GgenIgniter.Ocel2Example.AttributeChange do"
    assert content =~ "defmodule GgenIgniter.Ocel2Example.OCEL2 do"

    # The three real capabilities from the ex4pm reference implementation
    # (~/ex4pm/apps/ex4pm_core/lib/ex4pm/ocel2.ex) survive templatization.
    assert content =~ "def object_trace(%EventLog{} = log, object_id)"
    assert content =~ "def attribute_history(%EventLog{} = log, object_id, attribute_name)"
    assert content =~ "def object_relationships_for(%EventLog{} = log, object_id)"

    # Field names are also ontology-driven, not hardcoded.
    assert content =~ "object_id in &1.object_ids"
    assert content =~ "&{&1.timestamp, &1.id}"
  end
end
