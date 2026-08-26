defmodule GgenIgniter.SyncTaskTest do
  use ExUnit.Case, async: false

  @moduletag :integration

  test "mix ggen_igniter.sync runs end-to-end as a real subprocess and writes a real file" do
    out_dir = Path.join(System.tmp_dir!(), "ggen_igniter_sync_test_#{System.unique_integer([:positive])}")
    out_path = Path.join(out_dir, "resource.ex")

    args = [
      "ggen_igniter.sync",
      "--ontology",
      "test/fixtures/audit_trail_ontology.ttl",
      "--query",
      "spec=test/fixtures/spec.rq",
      "--query",
      "sections=test/fixtures/sections.rq",
      "--query",
      "entities=test/fixtures/entities.rq",
      "--query",
      "fields=test/fixtures/fields.rq",
      "--template",
      "test/fixtures/extension.ex.eex",
      "--out",
      out_path
    ]

    {output, exit_code} = System.cmd("mix", args, cd: File.cwd!(), stderr_to_stdout: true)

    assert exit_code == 0, "mix ggen_igniter.sync failed:\n#{output}"
    assert output =~ "ggen_igniter: wrote #{out_path}"

    assert File.exists?(out_path)
    content = File.read!(out_path)

    # Real syntax validity of what the real subprocess actually wrote to disk.
    assert {:defmodule, _, _} = Code.string_to_quoted!(content)

    assert content =~ "defmodule AuditTrail.Resource do"
    assert content =~ "defmodule AuditTrail.Dsl.Event do"
    assert content =~ "defmodule AuditTrail.Dsl.Projection do"
    assert content =~ "name: [type: :atom, required: true"
    assert content =~ "sections: [@audit],"
  after
    :ok
  end
end
