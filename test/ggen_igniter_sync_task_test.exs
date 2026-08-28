defmodule GgenIgniter.SyncTaskTest do
  use ExUnit.Case, async: false

  @moduletag :integration

  test "mix ggen_igniter.sync runs end-to-end as a real subprocess and writes a real file" do
    out_dir =
      Path.join(System.tmp_dir!(), "ggen_igniter_sync_test_#{System.unique_integer([:positive])}")

    File.rm_rf!(out_dir)
    on_exit(fn -> File.rm_rf!(out_dir) end)

    out_path = Path.join(out_dir, "resource.ex")

    args = [
      "ggen_igniter.sync",
      # Pinned to sparql: this test parses the written file as real Elixir
      # (Code.string_to_quoted!/1) built directly from ontology literal
      # values -- oxigraph (the default since v26.8.27) returns typed
      # literals as raw, datatype-annotated N-Triples-style term strings,
      # which is not valid Elixir when interpolated straight into generated
      # source the way this fixture template does. Real, disclosed
      # engine-shape difference (see the sync task's own moduledoc), not
      # something this basic end-to-end smoke test is about.
      "--engine",
      "sparql",
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
      out_path,
      # `out_path` lives outside the repo root (a real, unique tmp dir this
      # test creates and removes itself) -- `--manifest-dir` scopes
      # `GgenIgniter.ArtifactIdentity.within_root?/2`'s authorized-project-root
      # check to that same tmp dir instead of the default `File.cwd!()`, and
      # `--verify-cwd` keeps `:verify`'s real `mix compile` pointed at the
      # real repo root instead of the bare (no `mix.exs`) tmp dir.
      "--manifest-dir",
      out_dir,
      "--verify-cwd",
      File.cwd!()
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
