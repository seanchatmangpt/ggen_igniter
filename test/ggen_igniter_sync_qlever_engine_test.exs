defmodule GgenIgniter.SyncQleverEngineTest do
  @moduledoc """
  Chicago-style, no-mocks proof that `mix ggen_igniter.sync --engine qlever` runs
  end-to-end as a real subprocess: it loads a real manifest graph, resolves a real
  `gnoa:Qlever` store resource from it, runs a real gate query against a real,
  already-running QLever server, and writes a real generated file to disk.

  Requires the same real, locally-running QLever server as
  `ash_r2rml_gate_qlever_test.exs` (started via `qlever index && qlever start`
  against `~/ash_r2rml/priv/ontologies/fortune5/operational_shapes.ttl`, reachable
  at http://localhost:7020). Named, visible skip via `:requires_qlever_server` if
  unreachable -- never a silent mock substitution.
  """
  use ExUnit.Case, async: false

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
  test "mix ggen_igniter.sync --engine qlever runs a real gate query against real QLever and writes a real file" do
    out_dir =
      Path.join(System.tmp_dir!(), "ggen_igniter_qlever_engine_test_#{System.unique_integer([:positive])}")

    out_path = Path.join(out_dir, "gate_010_report.txt")
    gate_010 = Path.expand("~/ash_r2rml/priv/ggen/ash-r2rml-pack/gates/010_required_resource_contract.rq")

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

    {output, exit_code} = System.cmd("mix", args, cd: File.cwd!(), stderr_to_stdout: true)

    assert exit_code == 0, "mix ggen_igniter.sync --engine qlever failed:\n#{output}"
    assert output =~ "ggen_igniter: wrote #{out_path} (engine: qlever"

    assert File.exists?(out_path)
    content = File.read!(out_path)
    assert content == "gate010 rows: 24\n"
  end

  @tag :requires_qlever_server
  test "mix ggen_igniter.sync --engine qlever requires --store-id" do
    out_path =
      Path.join(System.tmp_dir!(), "ggen_igniter_qlever_engine_no_store_id_#{System.unique_integer([:positive])}.txt")

    template_path =
      Path.join(System.tmp_dir!(), "ggen_igniter_qlever_engine_template_#{System.unique_integer([:positive])}.eex")

    File.write!(template_path, "<%= length(rows) %>\n")

    args = [
      "ggen_igniter.sync",
      "--engine",
      "qlever",
      "--ontology",
      "config/gno/test/store.ttl",
      "--query",
      "rows=test/fixtures/spec.rq",
      "--template",
      template_path,
      "--out",
      out_path
    ]

    {output, exit_code} = System.cmd("mix", args, cd: File.cwd!(), stderr_to_stdout: true)

    refute exit_code == 0
    assert output =~ "--store-id is required"
  end

  test "mix ggen_igniter.sync rejects an unknown --engine" do
    out_path =
      Path.join(System.tmp_dir!(), "ggen_igniter_bad_engine_#{System.unique_integer([:positive])}.txt")

    args = [
      "ggen_igniter.sync",
      "--engine",
      "not_a_real_engine",
      "--ontology",
      "test/fixtures/audit_trail_ontology.ttl",
      "--query",
      "spec=test/fixtures/spec.rq",
      "--template",
      "test/fixtures/extension.ex.eex",
      "--out",
      out_path
    ]

    {output, exit_code} = System.cmd("mix", args, cd: File.cwd!(), stderr_to_stdout: true)

    refute exit_code == 0
    assert output =~ "invalid --engine"
  end
end
