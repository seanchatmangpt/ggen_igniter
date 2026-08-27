defmodule GgenIgniter.SyncForEachTest do
  use ExUnit.Case, async: false

  @moduletag :integration

  test "mix ggen_igniter.sync --for-each writes one real file per row, path rendered per row" do
    out_dir =
      Path.join(
        System.tmp_dir!(),
        "ggen_igniter_for_each_test_#{System.unique_integer([:positive])}"
      )

    # `System.unique_integer/1` restarts from low values on every fresh BEAM
    # instance (every `mix test` invocation), so two separate test runs can
    # collide on the exact same tmp path if this directory is never cleaned
    # up -- real, observed flake (a stale directory from an earlier run made
    # this test see "unchanged" content instead of a fresh "wrote"). Clean up
    # for real, every run.
    on_exit(fn -> File.rm_rf!(out_dir) end)

    out_template = Path.join(out_dir, "<%= module_name %>.ex")

    args = [
      "ggen_igniter.sync",
      # Pinned to sparql: asserts real file paths/module names/generated
      # Elixir content built from module_name/field_name -- oxigraph's raw,
      # quoted N-Triples-style term strings (the real, disclosed shape
      # difference the sync task's own moduledoc documents) aren't what this
      # --for-each fan-out mechanics test is about.
      "--engine",
      "sparql",
      "--ontology",
      "test/fixtures/for_each_ontology.ttl",
      "--query",
      "modules=test/fixtures/modules.rq",
      "--for-each",
      "modules",
      "--template",
      "test/fixtures/for_each_module.ex.eex",
      "--out",
      out_template
    ]

    {output, exit_code} = System.cmd("mix", args, cd: File.cwd!(), stderr_to_stdout: true)

    assert exit_code == 0, "mix ggen_igniter.sync --for-each failed:\n#{output}"

    alpha_path = Path.join(out_dir, "Multi.Alpha.ex")
    beta_path = Path.join(out_dir, "Multi.Beta.ex")
    gamma_path = Path.join(out_dir, "Multi.Gamma.ex")

    # Real multi-row fan-out: exactly the three rows in the fixture's `modules`
    # query, as three real separate files on disk -- not one aggregated file.
    assert File.exists?(alpha_path)
    assert File.exists?(beta_path)
    assert File.exists?(gamma_path)

    alpha_content = File.read!(alpha_path)
    beta_content = File.read!(beta_path)
    gamma_content = File.read!(gamma_path)

    assert {:defmodule, _, _} = Code.string_to_quoted!(alpha_content)
    assert {:defmodule, _, _} = Code.string_to_quoted!(beta_content)
    assert {:defmodule, _, _} = Code.string_to_quoted!(gamma_content)

    assert alpha_content =~ "defmodule Multi.Alpha do"
    assert alpha_content =~ ~s(def field_name, do: "alpha_field")

    assert beta_content =~ "defmodule Multi.Beta do"
    assert beta_content =~ ~s(def field_name, do: "beta_field")

    assert gamma_content =~ "defmodule Multi.Gamma do"
    assert gamma_content =~ ~s(def field_name, do: "gamma_field")

    # Each row's own file must not leak another row's binding into it.
    refute alpha_content =~ "beta_field"
    refute alpha_content =~ "gamma_field"
  end

  test "mix ggen_igniter.sync without --for-each still writes exactly one static file (unchanged behavior)" do
    out_dir =
      Path.join(
        System.tmp_dir!(),
        "ggen_igniter_no_for_each_test_#{System.unique_integer([:positive])}"
      )

    # Same real cross-run tmp-dir-collision flake as the --for-each test
    # above (`System.unique_integer/1` restarts every fresh BEAM instance) --
    # clean up for real, every run.
    on_exit(fn -> File.rm_rf!(out_dir) end)

    out_path = Path.join(out_dir, "resource.ex")

    args = [
      "ggen_igniter.sync",
      # Pinned to sparql: asserts real generated Elixir content (parses it
      # via Code.string_to_quoted!/1) built directly from ontology literal
      # values -- oxigraph (the default since v26.8.27) returns typed
      # literals as raw, datatype-annotated N-Triples-style term strings
      # (e.g. `"true"^^<...#boolean>`) which is not valid Elixir when
      # interpolated straight into generated source the way this fixture
      # template does; this is a real, disclosed engine-shape difference
      # (see the sync task's own moduledoc and `GgenIgniter.Query`'s), not
      # something this "unchanged static-output behavior" test is about.
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
      out_path
    ]

    {output, exit_code} = System.cmd("mix", args, cd: File.cwd!(), stderr_to_stdout: true)

    assert exit_code == 0, "mix ggen_igniter.sync failed:\n#{output}"
    assert output =~ "ggen_igniter: wrote #{out_path}"

    assert File.exists?(out_path)
    content = File.read!(out_path)
    assert {:defmodule, _, _} = Code.string_to_quoted!(content)
    assert content =~ "defmodule AuditTrail.Resource do"

    # Exactly one file -- no sibling files were created alongside it.
    assert File.ls!(out_dir) == ["resource.ex"]
  end

  test "mix ggen_igniter.sync --for-each with an undeclared query name fails closed" do
    args = [
      "ggen_igniter.sync",
      "--ontology",
      "test/fixtures/for_each_ontology.ttl",
      "--query",
      "modules=test/fixtures/modules.rq",
      "--for-each",
      "not_a_declared_query",
      "--template",
      "test/fixtures/for_each_module.ex.eex",
      "--out",
      Path.join(System.tmp_dir!(), "should_not_be_written_<%= module_name %>.ex")
    ]

    {output, exit_code} = System.cmd("mix", args, cd: File.cwd!(), stderr_to_stdout: true)

    refute exit_code == 0
    assert output =~ "not_a_declared_query"
  end
end
