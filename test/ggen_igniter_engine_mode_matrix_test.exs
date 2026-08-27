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

  ## Honest, already-documented `--engine oxigraph` divergence (not a new bug)

  `GgenIgniter.Query.Oxigraph.run/2` returns RDF literal values with their raw
  serialized quoting still attached (a string literal comes back as the
  3-character sequence `"name"`, literal quote characters embedded in the
  Elixir string) -- already documented and asserted on in
  `test/ggen_igniter_e2e_all_engines_test.exs`'s moduledoc and
  `test/ggen_igniter_oxigraph_engine_test.exs`. Every `oxigraph` test below
  asserts on that REAL quoted shape (in rendered file content, in eval'd
  string values, and even in `--for-each`-templated OUTPUT FILENAMES, since
  `--out`'s `<%= module_name %>` is rendered from the same quoted binding) --
  never on a cleaned-up shape this engine does not, today, actually produce.

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
    File.mkdir_p!(dir)
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
  # Every assertion below is on the REAL, already-documented quoted-literal
  # shape this engine produces (see moduledoc) -- never on the clean
  # `sparql`-engine shape asserted on above.

  describe "engine: oxigraph" do
    test "mode: file, for_each: absent -- writes one real file with real oxigraph literal quoting" do
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

      # Real, checked report: today's oxigraph literal quoting makes this
      # Elixir-source template's output fail to parse -- confirmed via the
      # non-raising `Code.string_to_quoted/1`, never `!/1`.
      assert {:error, _reason} = Code.string_to_quoted(content)

      assert content =~ ~s(defmodule "AuditTrail.Resource" do)
      assert content =~ ~s(Spark.Dsl.Extension for `"audit_trail"`.)
      assert content =~ ~s(defmodule "AuditTrail.Dsl.Event" do)
      assert content =~ ~s(defmodule "AuditTrail.Dsl.Projection" do)
      assert content =~ ~s(sections: [@"audit"],)
      assert content =~ ~s(transformers: ["AuditTrail.Resource".Persist],)
    end

    test "mode: file, for_each: present -- writes three distinct files, filenames AND content carrying real oxigraph quoting" do
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

      # `module_name` itself comes back quoted from the oxigraph engine, and
      # `--out`'s `<%= module_name %>` is rendered from that same binding --
      # so the real output FILENAMES carry the embedded quote characters too,
      # not just the file content. Real, observed behavior, asserted honestly.
      written = out_dir |> File.ls!() |> Enum.sort()
      assert written == [~s("Multi.Alpha".ex), ~s("Multi.Beta".ex), ~s("Multi.Gamma".ex)]

      for {name, field} <- [
            {~s("Multi.Alpha".ex), "alpha_field"},
            {~s("Multi.Beta".ex), "beta_field"},
            {~s("Multi.Gamma".ex), "gamma_field"}
          ] do
        content = File.read!(Path.join(out_dir, name))
        # The template itself already wraps `field_name` in literal quotes
        # (`do: "<%= field_name %>"`), and the oxigraph-returned value is
        # ITSELF already quoted -- so the real rendered output has the value
        # double-quoted (four literal quote characters total), not one pair.
        assert content =~ "def field_name, do: \"\"#{field}\"\""
      end
    end

    test "mode: eval, for_each: absent -- evaluates in-process with real oxigraph-quoted bindings, writes nothing to disk" do
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

      # The real returned eval value is a runtime string with an embedded
      # quote character (`package_name` itself comes back quoted from the
      # oxigraph engine -- see moduledoc); `inspect/1` is what adds the
      # backslash-escaping visible in the real notice text, so build the
      # expected notice via `inspect/1` too rather than hand-escaping it.
      real_eval_value = "evaluated-" <> ~s("audit_trail")

      assert output =~
               "ggen_igniter: evaluated test/fixtures/eval_mode_module.exs.eex -> #{inspect(real_eval_value)} (engine: oxigraph, 1 query, 1 total row(s))"

      refute output =~ "wrote "

      assert File.exists?(sentinel)
      assert File.read!(sentinel) == ~s("audit_trail")
    end

    test "mode: eval, for_each: present -- evaluates once per row with real oxigraph-quoted bindings, writes nothing to disk" do
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

      # Real observed shape: `EVAL_SENTINEL_DIR`'s per-row filename is built
      # from the SAME quoted `module_name` binding, so it carries embedded
      # quote characters exactly like the file-mode --out template does above.
      written = sentinel_dir |> File.ls!() |> Enum.sort()
      assert written == [~s("Multi.Alpha".txt), ~s("Multi.Beta".txt), ~s("Multi.Gamma".txt)]

      for {name, field} <- [
            {~s("Multi.Alpha".txt), "alpha_field"},
            {~s("Multi.Beta".txt), "beta_field"},
            {~s("Multi.Gamma".txt), "gamma_field"}
          ] do
        # Same `inspect/1`-vs-raw-value distinction as the absent-for_each
        # oxigraph eval test above: the notice text shows inspect's
        # backslash-escaped display of a value that itself contains real
        # embedded quote characters (no backslashes) -- build the expected
        # notice substring via `inspect/1`, not by hand-escaping it.
        real_eval_value = "evaluated-" <> Path.rootname(name)
        assert output =~ inspect(real_eval_value)
        assert File.read!(Path.join(sentinel_dir, name)) == ~s("#{field}")
      end
    end
  end
end
