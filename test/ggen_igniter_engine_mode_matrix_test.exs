defmodule GgenIgniter.EngineModeMatrixTest do
  @moduledoc """
  Chicago-style, real subprocess, no mocks: exercises the real cross-product of
  `--engine` x `--mode` x `--for-each` for `mix ggen_igniter.sync`, same
  `System.cmd/3` real-subprocess pattern as
  `test/ggen_igniter_sync_frontmatter_test.exs` and
  `test/ggen_igniter_sync_eval_mode_test.exs`, against the EXISTING real
  fixtures in `test/fixtures/` (no new ontology/template fixtures invented for
  this file):

    * `audit_trail_ontology.ttl` + `spec.rq`/`entities.rq`/`sections.rq`/
      `fields.rq` + `extension.ex.eex` -- the single-row (`for_each: absent`)
      shape, same fixtures `test/ggen_igniter_e2e_all_engines_test.exs` uses.
    * `for_each_ontology.ttl` + `modules.rq` + `for_each_module.ex.eex` /
      `eval_mode_for_each.exs.eex` -- the `--for-each modules` (three rows)
      shape, same fixtures `test/ggen_igniter_sync_eval_mode_test.exs` uses.
    * `eval_mode_module.exs.eex` -- the `mode: eval` (frontmatter-driven,
      single row) shape.

  Verified fresh this session (concurrent workflows may edit this repo):
  `--engine`'s real current default in `lib/mix/tasks/ggen_igniter.sync.ex` is
  still `opts[:engine] || "sparql"` -- `{engine: sparql, oxigraph}` below are
  both explicit `--engine` flags, so that default is exercised by every
  `sparql` case without relying on it being unstated anywhere.

  ## The full {engine, mode, for_each} cross-product IS the test matrix

  `{sparql, oxigraph} x {file, eval} x {absent, present}` = 8 combinations,
  all semantically valid with these fixtures (none skipped): `mode: eval`
  never needs `--out` (`GgenIgniter.Actuate.eval_code!/2` writes nothing to
  disk), and `for_each: present` always drives via `--for-each modules` against
  `modules.rq`'s three rows -- no combination here requires forcing a
  nonsensical flag pairing.

  ## `--engine oxigraph` literal-quoting bug: FIXED at the source (real, verified)

  `GgenIgniter.Query.Oxigraph.run/2` used to return RDF literal values with
  their raw serialized quoting still attached (a string literal came back as
  the 3-character sequence `"name"`, literal quote characters embedded in
  the Elixir string) -- previously documented and asserted on in
  `test/ggen_igniter_e2e_all_engines_test.exs`'s moduledoc and
  `test/ggen_igniter_oxigraph_engine_test.exs`. This is now fixed AT THE
  SOURCE, in the Rust NIF itself (`native/ggen_graph_nif/src/oxigraph_engine.rs`'s
  `normalize_term/1`, using oxrdf's own typed accessors -- see
  `GgenIgniter.Query.Oxigraph`'s own moduledoc, "Term normalization", for the
  full rationale). Every `oxigraph` test below now asserts on that same
  clean, unwrapped shape the `sparql` engine's tests above already assert on
  (in rendered file content, in eval'd string values, and in
  `--for-each`-templated output filenames) -- verified fresh via real
  `mix ggen_igniter.sync --engine oxigraph` subprocess runs against these
  exact fixtures, not assumed from reading the fix alone.

  Row order across `--for-each` is intentionally NOT asserted on (observed to
  differ between engines/runs) -- every for-each assertion here compares a
  SORTED file/notice set, same discipline
  `test/ggen_igniter_sync_eval_mode_test.exs` already uses (`File.ls! |>
  Enum.sort()`).
  """
  use ExUnit.Case, async: false

  @moduletag :integration

  @audit_ontology "test/fixtures/audit_trail_ontology.ttl"
  @for_each_ontology "test/fixtures/for_each_ontology.ttl"

  defp run_sync(args, env \\ []) do
    System.cmd("mix", ["ggen_igniter.sync" | args],
      cd: File.cwd!(),
      stderr_to_stdout: true,
      env: env
    )
  end

  defp unique_tmp_dir(prefix) do
    dir = Path.join(System.tmp_dir!(), "#{prefix}_#{System.unique_integer([:positive])}")
    # `System.unique_integer/1` resets per-BEAM-VM, so across separate `mix
    # test` invocations this path can collide with a stale directory left
    # over from a prior run. Force a clean slate and clean up after.
    File.rm_rf!(dir)
    File.mkdir_p!(dir)
    ExUnit.Callbacks.on_exit(fn -> File.rm_rf!(dir) end)
    dir
  end

  # --- {engine: sparql} x {mode: file, eval} x {for_each: absent, present} ---

  describe "engine: sparql" do
    test "mode: file, for_each: absent -- writes one real compiling file from the audit_trail fixtures" do
      out_path = Path.join(unique_tmp_dir("matrix_sparql_file"), "resource.ex")

      {output, exit_code} =
        run_sync([
          "--engine",
          "sparql",
          "--ontology",
          @audit_ontology,
          "--query",
          "spec=test/fixtures/spec.rq",
          "--query",
          "entities=test/fixtures/entities.rq",
          "--query",
          "sections=test/fixtures/sections.rq",
          "--query",
          "fields=test/fixtures/fields.rq",
          "--template",
          "test/fixtures/extension.ex.eex",
          "--out",
          out_path
        ])

      assert exit_code == 0, "sparql/file/absent sync failed:\n#{output}"

      assert output =~
               "ggen_igniter: wrote #{out_path} (engine: sparql, 4 queries, 7 total row(s))"

      assert File.exists?(out_path)
      content = File.read!(out_path)

      assert {:defmodule, _, _} = Code.string_to_quoted!(content)
      assert content =~ "defmodule AuditTrail.Resource do"
      assert content =~ "Spark.Dsl.Extension for `audit_trail`."
      assert content =~ "defmodule AuditTrail.Dsl.Event do"
      assert content =~ "defmodule AuditTrail.Dsl.Projection do"
      assert content =~ "sections: [@audit],"
      assert content =~ "transformers: [AuditTrail.Resource.Persist],"
    end

    test "mode: file, for_each: present -- writes three distinct real files, one per modules.rq row" do
      out_dir = unique_tmp_dir("matrix_sparql_file_foreach")
      out_template = Path.join(out_dir, "<%= module_name %>.ex")

      {output, exit_code} =
        run_sync([
          "--engine",
          "sparql",
          "--ontology",
          @for_each_ontology,
          "--query",
          "modules=test/fixtures/modules.rq",
          "--for-each",
          "modules",
          "--template",
          "test/fixtures/for_each_module.ex.eex",
          "--out",
          out_template
        ])

      assert exit_code == 0, "sparql/file/present sync failed:\n#{output}"
      assert output =~ "(engine: sparql, 1 query, 3 total row(s))"

      written = out_dir |> File.ls!() |> Enum.sort()
      assert written == ["Multi.Alpha.ex", "Multi.Beta.ex", "Multi.Gamma.ex"]

      for {name, field} <- [
            {"Multi.Alpha.ex", "alpha_field"},
            {"Multi.Beta.ex", "beta_field"},
            {"Multi.Gamma.ex", "gamma_field"}
          ] do
        content = File.read!(Path.join(out_dir, name))
        assert {:defmodule, _, _} = Code.string_to_quoted!(content)
        assert content =~ "def field_name, do: \"#{field}\""
      end
    end

    test "mode: eval, for_each: absent -- evaluates the rendered body in-process, writes nothing to disk" do
      sentinel = Path.join(unique_tmp_dir("matrix_sparql_eval"), "sentinel.txt")

      {output, exit_code} =
        run_sync(
          [
            "--engine",
            "sparql",
            "--ontology",
            @audit_ontology,
            "--query",
            "spec=test/fixtures/spec.rq",
            "--template",
            "test/fixtures/eval_mode_module.exs.eex"
          ],
          [{"EVAL_SENTINEL_PATH", sentinel}]
        )

      assert exit_code == 0, "sparql/eval/absent sync failed:\n#{output}"

      assert output =~
               "ggen_igniter: evaluated test/fixtures/eval_mode_module.exs.eex -> \"evaluated-audit_trail\" (engine: sparql, 1 query, 1 total row(s))"

      refute output =~ "wrote "

      assert File.exists?(sentinel)
      assert File.read!(sentinel) == "audit_trail"
    end

    test "mode: eval, for_each: present -- evaluates once per modules.rq row, writes nothing to disk" do
      sentinel_dir = unique_tmp_dir("matrix_sparql_eval_foreach")

      {output, exit_code} =
        run_sync(
          [
            "--engine",
            "sparql",
            "--ontology",
            @for_each_ontology,
            "--query",
            "modules=test/fixtures/modules.rq",
            "--for-each",
            "modules",
            "--template",
            "test/fixtures/eval_mode_for_each.exs.eex"
          ],
          [{"EVAL_SENTINEL_DIR", sentinel_dir}]
        )

      assert exit_code == 0, "sparql/eval/present sync failed:\n#{output}"
      assert output =~ "(engine: sparql, 1 query, 3 total row(s))"
      refute output =~ "wrote "

      written = sentinel_dir |> File.ls!() |> Enum.sort()
      assert written == ["Multi.Alpha.txt", "Multi.Beta.txt", "Multi.Gamma.txt"]

      for {name, field} <- [
            {"Multi.Alpha.txt", "alpha_field"},
            {"Multi.Beta.txt", "beta_field"},
            {"Multi.Gamma.txt", "gamma_field"}
          ] do
        assert output =~ "evaluated-#{Path.rootname(name)}"
        assert File.read!(Path.join(sentinel_dir, name)) == field
      end
    end
  end

  # --- {engine: oxigraph} x {mode: file, eval} x {for_each: absent, present} ---
  #
  # Every assertion below is on the same clean, unwrapped shape the
  # `sparql`-engine tests above assert on (see moduledoc's "FIXED at the
  # source" note) -- the literal-quoting bug this engine used to have is
  # fixed, so these are no longer separately-documented-divergence
  # assertions, just the normal expected output.

  describe "engine: oxigraph" do
    test "mode: file, for_each: absent -- writes one real, compiling file (clean, unwrapped values)" do
      out_path = Path.join(unique_tmp_dir("matrix_oxigraph_file"), "resource.ex")

      {output, exit_code} =
        run_sync([
          "--engine",
          "oxigraph",
          "--ontology",
          @audit_ontology,
          "--query",
          "spec=test/fixtures/spec.rq",
          "--query",
          "entities=test/fixtures/entities.rq",
          "--query",
          "sections=test/fixtures/sections.rq",
          "--query",
          "fields=test/fixtures/fields.rq",
          "--template",
          "test/fixtures/extension.ex.eex",
          "--out",
          out_path
        ])

      assert exit_code == 0, "oxigraph/file/absent sync failed:\n#{output}"

      assert output =~
               "ggen_igniter: wrote #{out_path} (engine: oxigraph, 4 queries, 7 total row(s))"

      assert File.exists?(out_path)
      content = File.read!(out_path)

      # Real, checked report: the literal-quoting fix means this
      # Elixir-source template's output now parses cleanly -- confirmed via
      # the raising `Code.string_to_quoted!/1` (never masking a real parse
      # failure).
      assert {:defmodule, _, _} = Code.string_to_quoted!(content)

      assert content =~ "defmodule AuditTrail.Resource do"
      assert content =~ "Spark.Dsl.Extension for `audit_trail`."
      assert content =~ "defmodule AuditTrail.Dsl.Event do"
      assert content =~ "defmodule AuditTrail.Dsl.Projection do"
      assert content =~ "sections: [@audit],"
      assert content =~ "transformers: [AuditTrail.Resource.Persist],"
    end

    test "mode: file, for_each: present -- writes three distinct real files, one per modules.rq row (clean filenames and content)" do
      out_dir = unique_tmp_dir("matrix_oxigraph_file_foreach")
      out_template = Path.join(out_dir, "<%= module_name %>.ex")

      {output, exit_code} =
        run_sync([
          "--engine",
          "oxigraph",
          "--ontology",
          @for_each_ontology,
          "--query",
          "modules=test/fixtures/modules.rq",
          "--for-each",
          "modules",
          "--template",
          "test/fixtures/for_each_module.ex.eex",
          "--out",
          out_template
        ])

      assert exit_code == 0, "oxigraph/file/present sync failed:\n#{output}"
      assert output =~ "(engine: oxigraph, 1 query, 3 total row(s))"

      # `module_name` now comes back plain/unwrapped from the oxigraph
      # engine (the literal-quoting fix), so `--out`'s `<%= module_name %>`
      # renders clean output FILENAMES too -- same shape as the `sparql`
      # engine's equivalent test above.
      written = out_dir |> File.ls!() |> Enum.sort()
      assert written == ["Multi.Alpha.ex", "Multi.Beta.ex", "Multi.Gamma.ex"]

      for {name, field} <- [
            {"Multi.Alpha.ex", "alpha_field"},
            {"Multi.Beta.ex", "beta_field"},
            {"Multi.Gamma.ex", "gamma_field"}
          ] do
        content = File.read!(Path.join(out_dir, name))
        assert {:defmodule, _, _} = Code.string_to_quoted!(content)
        assert content =~ "def field_name, do: \"#{field}\""
      end
    end

    test "mode: eval, for_each: absent -- evaluates the rendered body in-process with clean bindings, writes nothing to disk" do
      sentinel = Path.join(unique_tmp_dir("matrix_oxigraph_eval"), "sentinel.txt")

      {output, exit_code} =
        run_sync(
          [
            "--engine",
            "oxigraph",
            "--ontology",
            @audit_ontology,
            "--query",
            "spec=test/fixtures/spec.rq",
            "--template",
            "test/fixtures/eval_mode_module.exs.eex"
          ],
          [{"EVAL_SENTINEL_PATH", sentinel}]
        )

      assert exit_code == 0, "oxigraph/eval/absent sync failed:\n#{output}"

      assert output =~
               "ggen_igniter: evaluated test/fixtures/eval_mode_module.exs.eex -> \"evaluated-audit_trail\" (engine: oxigraph, 1 query, 1 total row(s))"

      refute output =~ "wrote "

      assert File.exists?(sentinel)
      assert File.read!(sentinel) == "audit_trail"
    end

    test "mode: eval, for_each: present -- evaluates once per row with clean bindings, writes nothing to disk" do
      sentinel_dir = unique_tmp_dir("matrix_oxigraph_eval_foreach")

      {output, exit_code} =
        run_sync(
          [
            "--engine",
            "oxigraph",
            "--ontology",
            @for_each_ontology,
            "--query",
            "modules=test/fixtures/modules.rq",
            "--for-each",
            "modules",
            "--template",
            "test/fixtures/eval_mode_for_each.exs.eex"
          ],
          [{"EVAL_SENTINEL_DIR", sentinel_dir}]
        )

      assert exit_code == 0, "oxigraph/eval/present sync failed:\n#{output}"
      assert output =~ "(engine: oxigraph, 1 query, 3 total row(s))"
      refute output =~ "wrote "

      # `EVAL_SENTINEL_DIR`'s per-row filename is now built from the SAME
      # clean, unwrapped `module_name` binding -- same shape as the
      # file-mode `--out` template above, and as the `sparql`-engine
      # equivalent test.
      written = sentinel_dir |> File.ls!() |> Enum.sort()
      assert written == ["Multi.Alpha.txt", "Multi.Beta.txt", "Multi.Gamma.txt"]

      for {name, field} <- [
            {"Multi.Alpha.txt", "alpha_field"},
            {"Multi.Beta.txt", "beta_field"},
            {"Multi.Gamma.txt", "gamma_field"}
          ] do
        real_eval_value = "evaluated-" <> Path.rootname(name)
        assert output =~ inspect(real_eval_value)
        assert File.read!(Path.join(sentinel_dir, name)) == field
      end
    end
  end
end
