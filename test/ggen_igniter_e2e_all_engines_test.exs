defmodule GgenIgniter.E2eAllEnginesTest do
  @moduledoc """
  Chicago-style, no-mocks, full-loop proof: for EACH `--engine` this project
  supports (`sparql`, `oxigraph`, and `qlever` when a real local QLever
  server is reachable), runs the REAL `mix ggen_igniter.sync` CLI task as a
  real subprocess (via `System.cmd/3`, same harness pattern as
  `test/ggen_igniter_sync_task_test.exs`), through the real `--pack-dir`
  convention against the real fixture pack at `test/fixtures/sample-pack`
  (`ontology.ttl -> gates/*.rq -> templates/extension.ex.eex`), and asserts:

    1. the real output file was actually written to disk with the real
       content that engine actually produces, and
    2. running the exact same command AGAIN is a real idempotent no-op
       (`GgenIgniter.Actuate.write_file!/3`'s `:unchanged` decision) -- no
       duplicate write, no crash, no changed mtime-worthy content.

  This is the "does the whole pipeline actually work end to end" proof
  (ontology -> query -> render -> write, through the real CLI, through each
  real engine) -- not a unit test of any one function in isolation.

  ## `oxigraph` engine literal-quoting bug: FIXED at the source (real, verified)

  `GgenIgniter.Query.Oxigraph.run/2` (the native oxigraph NIF path) used to
  return RDF literal values with their raw serialized quoting/datatype
  suffixes still attached (e.g. a string literal came back as the
  3-character sequence `"name"` -- literal quote characters embedded in the
  Elixir string -- rather than the bare `name` the `sparql` engine returns).
  This is now fixed AT THE SOURCE, in the Rust NIF itself
  (`native/ggen_graph_nif/src/oxigraph_engine.rs`'s `normalize_term/1`, using
  oxrdf's own typed accessors -- see `GgenIgniter.Query.Oxigraph`'s own
  moduledoc, "Term normalization", for the full rationale and its one
  disclosed scope limit). Rendered through `test/fixtures/sample-pack`'s
  Elixir-source template, the `oxigraph` engine's output is now real,
  compileable Elixir -- confirmed below via `Code.string_to_quoted!/1`,
  byte-identical to what the `sparql` engine's describe block above already
  asserts. The end-to-end LOOP (ontology -> query -> render -> write, plus
  the idempotent-no-op re-run) is real and asserted for both engines.
  """
  use ExUnit.Case, async: false

  @moduletag :integration

  @pack_dir "test/fixtures/sample-pack"

  describe "--engine sparql" do
    test "real end-to-end loop: sync writes a real compiling file, re-sync is a real idempotent no-op" do
      out_dir =
        Path.join(
          System.tmp_dir!(),
          "ggen_igniter_e2e_sparql_#{System.unique_integer([:positive])}"
        )

      File.rm_rf!(out_dir)
      on_exit(fn -> File.rm_rf!(out_dir) end)

      out_path = Path.join(out_dir, "resource.ex")

      args = [
        "ggen_igniter.sync",
        "--engine",
        "sparql",
        "--pack-dir",
        @pack_dir,
        "--out",
        out_path
      ]

      {output1, exit_code1} = System.cmd("mix", args, cd: File.cwd!(), stderr_to_stdout: true)

      assert exit_code1 == 0,
             "first mix ggen_igniter.sync --engine sparql run failed:\n#{output1}"

      assert output1 =~ "ggen_igniter: wrote #{out_path}"
      assert output1 =~ "(engine: sparql, 4 queries, 7 total row(s))"

      assert File.exists?(out_path)
      content = File.read!(out_path)

      # Real syntax validity of what the real subprocess actually wrote.
      assert {:defmodule, _, _} = Code.string_to_quoted!(content)

      assert content =~ "defmodule AuditTrail.Resource do"
      assert content =~ "defmodule AuditTrail.Dsl.Event do"
      assert content =~ "defmodule AuditTrail.Dsl.Projection do"
      assert content =~ "name: [type: :atom, required: true, doc: \"The audited event's slug.\"]"
      assert content =~ "sections: [@audit],"
      assert content =~ "transformers: [AuditTrail.Resource.Persist],"

      # --- run #2: the real idempotent no-op path (GgenIgniter.Actuate's
      # unconditional byte-identical-content check), through the real CLI
      # again -- no duplicate write, no crash.
      {output2, exit_code2} = System.cmd("mix", args, cd: File.cwd!(), stderr_to_stdout: true)

      assert exit_code2 == 0,
             "second (idempotent) mix ggen_igniter.sync --engine sparql run failed:\n#{output2}"

      assert output2 =~ "ggen_igniter: unchanged (skipped, identical content): #{out_path}"
      refute output2 =~ "ggen_igniter: wrote #{out_path}"

      # The file on disk is byte-identical to what run #1 wrote -- the
      # no-op genuinely didn't touch it.
      assert File.read!(out_path) == content
    end
  end

  describe "--engine oxigraph" do
    test "real end-to-end loop via the native oxigraph NIF: sync writes the real file, re-sync is a real idempotent no-op" do
      out_dir =
        Path.join(
          System.tmp_dir!(),
          "ggen_igniter_e2e_oxigraph_#{System.unique_integer([:positive])}"
        )

      File.rm_rf!(out_dir)
      on_exit(fn -> File.rm_rf!(out_dir) end)

      out_path = Path.join(out_dir, "resource.ex")

      args = [
        "ggen_igniter.sync",
        "--engine",
        "oxigraph",
        "--pack-dir",
        @pack_dir,
        "--out",
        out_path
      ]

      {output1, exit_code1} = System.cmd("mix", args, cd: File.cwd!(), stderr_to_stdout: true)

      assert exit_code1 == 0,
             "first mix ggen_igniter.sync --engine oxigraph run failed:\n#{output1}"

      assert output1 =~ "ggen_igniter: wrote #{out_path}"
      assert output1 =~ "(engine: oxigraph, 4 queries, 7 total row(s))"

      assert File.exists?(out_path)
      content = File.read!(out_path)

      # Real content the oxigraph engine actually produces now that the
      # literal-quoting bug is fixed at the source: byte-identical shape to
      # the sparql engine's assertions above (see moduledoc's "FIXED at the
      # source" note) -- no quote characters leaking into module/atom/field
      # names.
      assert {:defmodule, _, _} = Code.string_to_quoted!(content)

      assert content =~ "defmodule AuditTrail.Resource do"
      assert content =~ "defmodule AuditTrail.Dsl.Event do"
      assert content =~ "defmodule AuditTrail.Dsl.Projection do"
      assert content =~ "name: [type: :atom, required: true, doc: \"The audited event's slug.\"]"
      assert content =~ "sections: [@audit],"
      assert content =~ "transformers: [AuditTrail.Resource.Persist],"

      # --- run #2: same real idempotent no-op path, same real CLI, this
      # engine's real (quoted) content included -- no duplicate write, no
      # crash despite that content being unusual.
      {output2, exit_code2} = System.cmd("mix", args, cd: File.cwd!(), stderr_to_stdout: true)

      assert exit_code2 == 0,
             "second (idempotent) mix ggen_igniter.sync --engine oxigraph run failed:\n#{output2}"

      assert output2 =~ "ggen_igniter: unchanged (skipped, identical content): #{out_path}"
      refute output2 =~ "ggen_igniter: wrote #{out_path}"

      assert File.read!(out_path) == content
    end
  end

  describe "--engine qlever" do
    setup do
      endpoint_reachable? =
        case :httpc.request(:get, {~c"http://localhost:7020", []}, [{:timeout, 1_000}], []) do
          {:ok, _} -> true
          _ -> false
        end

      unless endpoint_reachable? do
        ExUnit.configure(exclude: [:requires_qlever_server])
      end

      :ok
    end

    @tag :requires_qlever_server
    test "real end-to-end loop against a real, already-running QLever server: sync writes the real file, re-sync is a real idempotent no-op" do
      out_dir =
        Path.join(
          System.tmp_dir!(),
          "ggen_igniter_e2e_qlever_#{System.unique_integer([:positive])}"
        )

      File.rm_rf!(out_dir)
      on_exit(fn -> File.rm_rf!(out_dir) end)

      out_path = Path.join(out_dir, "gate_010_report.txt")

      gate_010 =
        Path.expand(
          "~/ash_r2rml/priv/ggen/ash-r2rml-pack/gates/010_required_resource_contract.rq"
        )

      template_path = Path.join(out_dir, "report.eex")
      File.mkdir_p!(out_dir)
      File.write!(template_path, "gate010 rows: <%= length(gate010) %>\n")

      args = [
        "ggen_igniter.sync",
        "--engine",
        "qlever",
        "--ontology",
        "config/gno/test/store.ttl",
        "--store-id",
        "http://example.com/Qlever",
        "--query",
        "gate010=#{gate_010}",
        "--template",
        template_path,
        "--out",
        out_path
      ]

      {output1, exit_code1} = System.cmd("mix", args, cd: File.cwd!(), stderr_to_stdout: true)

      assert exit_code1 == 0,
             "first mix ggen_igniter.sync --engine qlever run failed:\n#{output1}"

      assert output1 =~ "ggen_igniter: wrote #{out_path} (engine: qlever"

      assert File.exists?(out_path)
      content = File.read!(out_path)
      assert content == "gate010 rows: 24\n"

      # --- run #2 against the same real remote QLever server: real
      # idempotent no-op, no duplicate write, no crash.
      {output2, exit_code2} = System.cmd("mix", args, cd: File.cwd!(), stderr_to_stdout: true)

      assert exit_code2 == 0,
             "second (idempotent) mix ggen_igniter.sync --engine qlever run failed:\n#{output2}"

      assert output2 =~
               "ggen_igniter: unchanged (skipped, identical content): #{out_path} (engine: qlever"

      refute output2 =~ "ggen_igniter: wrote #{out_path}"

      assert File.read!(out_path) == content
    end
  end
end
