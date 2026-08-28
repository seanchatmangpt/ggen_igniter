defmodule GgenIgniterReplayTest do
  @moduledoc """
  Chicago-style: a REAL receipt written by `GgenIgniter.Receipt.append!/2` to
  a real tmp dir, real output files on real disk, real content mutation
  between receipt-write and replay. No mocks -- exercises
  `Mix.Tasks.GgenIgniter.Replay.load_receipt/1` and `build_report/2`
  directly (never `run/1`, which calls `System.halt/1` for real and would
  kill the test runner).
  """
  use ExUnit.Case, async: true

  alias GgenIgniter.{Manifest, Receipt}
  alias Mix.Tasks.GgenIgniter.Replay

  setup do
    tmp_dir =
      System.tmp_dir!()
      |> Path.join("ggen_igniter_replay_test_#{System.unique_integer([:positive, :monotonic])}")

    File.mkdir_p!(tmp_dir)
    on_exit(fn -> File.rm_rf!(tmp_dir) end)

    %{tmp_dir: tmp_dir}
  end

  defp write_output!(tmp_dir, relpath, content) do
    full_path = Path.join(tmp_dir, relpath)
    File.mkdir_p!(Path.dirname(full_path))
    File.write!(full_path, content)
    full_path
  end

  test "no drift: recomputed output hash matches the recorded receipt", %{tmp_dir: tmp_dir} do
    out_path = write_output!(tmp_dir, "lib/resource.ex", "defmodule Resource do\nend\n")

    post_run_hash = Receipt.hash_files([out_path])

    receipt =
      Receipt.new(%{
        standing: :alive,
        recipe_key: "templates/resource.ex.eex=>lib/resource.ex",
        pre_run_hash: Receipt.hash_entries([{out_path, nil}]),
        post_run_hash: post_run_hash,
        files: [out_path],
        events: [],
        reason: nil,
        metadata: %{}
      })

    :ok = Receipt.append!(tmp_dir, receipt)

    [receipt_partition] =
      tmp_dir
      |> Receipt.dir()
      |> File.ls!()
      |> Enum.filter(&String.ends_with?(&1, ".jsonl"))

    receipt_file = Path.join(Receipt.dir(tmp_dir), receipt_partition)

    assert {:ok, loaded_receipt} = Replay.load_receipt(receipt_file)
    assert loaded_receipt["standing"] == "alive"

    report = Replay.build_report(loaded_receipt, tmp_dir)

    assert report.categories == []
  end

  test "drift detected: a real file mutation between receipt-write and replay", %{
    tmp_dir: tmp_dir
  } do
    out_path = write_output!(tmp_dir, "lib/resource.ex", "defmodule Resource do\nend\n")

    post_run_hash = Receipt.hash_files([out_path])

    receipt =
      Receipt.new(%{
        standing: :alive,
        recipe_key: "templates/resource.ex.eex=>lib/resource.ex",
        pre_run_hash: Receipt.hash_entries([{out_path, nil}]),
        post_run_hash: post_run_hash,
        files: [out_path],
        events: [],
        reason: nil,
        metadata: %{}
      })

    :ok = Receipt.append!(tmp_dir, receipt)

    # Real mutation of the real on-disk output AFTER the receipt was
    # recorded -- the exact scenario `detect_output_drift/2` must catch.
    File.write!(out_path, "defmodule Resource do\n  def mutated?, do: true\nend\n")

    [receipt_partition] =
      tmp_dir
      |> Receipt.dir()
      |> File.ls!()
      |> Enum.filter(&String.ends_with?(&1, ".jsonl"))

    receipt_file = Path.join(Receipt.dir(tmp_dir), receipt_partition)

    assert {:ok, loaded_receipt} = Replay.load_receipt(receipt_file)

    report = Replay.build_report(loaded_receipt, tmp_dir)

    assert [%{category: "output state changed"} = drift] = report.categories
    assert drift.recorded == post_run_hash
    assert drift.current == Receipt.hash_files([out_path])
    refute drift.current == drift.recorded
  end

  test "drift detected: ontology changed since receipt, via manifest pack_dir", %{
    tmp_dir: tmp_dir
  } do
    pack_dir = Path.join(tmp_dir, "priv/ggen/mypack")
    File.mkdir_p!(pack_dir)
    ontology_path = Path.join(pack_dir, "ontology.ttl")
    File.write!(ontology_path, "@prefix ex: <http://example.org/> .\nex:A a ex:B .\n")

    out_path = write_output!(tmp_dir, "lib/resource.ex", "defmodule Resource do\nend\n")
    recipe_key = "#{pack_dir}/templates/resource.ex.eex=>lib/resource.ex"

    manifest =
      Manifest.load(tmp_dir)
      |> Manifest.put(
        recipe_key,
        Manifest.build_entry(
          "#{pack_dir}/templates/resource.ex.eex",
          "lib/resource.ex",
          pack_dir,
          %{out_path => Manifest.hash_content(File.read!(out_path))}
        )
      )

    Manifest.persist!(manifest, tmp_dir)

    recorded_graph_hash =
      "sha256:" <>
        (:crypto.hash(:sha256, File.read!(ontology_path)) |> Base.encode16(case: :lower))

    receipt =
      Receipt.new(%{
        standing: :alive,
        recipe_key: recipe_key,
        pre_run_hash: Receipt.hash_entries([{out_path, nil}]),
        post_run_hash: Receipt.hash_files([out_path]),
        files: [out_path],
        events: [],
        reason: nil,
        metadata: %{"graph_hash" => recorded_graph_hash}
      })

    :ok = Receipt.append!(tmp_dir, receipt)

    # Real mutation of the real ontology AFTER the receipt was recorded.
    File.write!(ontology_path, "@prefix ex: <http://example.org/> .\nex:A a ex:Changed .\n")

    [receipt_partition] =
      tmp_dir
      |> Receipt.dir()
      |> File.ls!()
      |> Enum.filter(&String.ends_with?(&1, ".jsonl"))

    receipt_file = Path.join(Receipt.dir(tmp_dir), receipt_partition)

    assert {:ok, loaded_receipt} = Replay.load_receipt(receipt_file)

    report = Replay.build_report(loaded_receipt, tmp_dir)

    assert Enum.any?(report.categories, &(&1.category == "ontology changed"))
  end

  test "invalid invocation: receipt file does not exist" do
    assert {:error, message} = Replay.load_receipt("/nonexistent/path/receipt.json")
    assert message =~ "could not read receipt file"
  end

  test "invalid invocation: receipt file is not valid JSON", %{tmp_dir: tmp_dir} do
    bad_path = Path.join(tmp_dir, "bad_receipt.json")
    File.write!(bad_path, "not json at all {{{")

    assert {:error, message} = Replay.load_receipt(bad_path)
    assert message =~ "not valid JSON"
  end

  test "loads a single-JSON-object receipt file (not a .jsonl partition)", %{tmp_dir: tmp_dir} do
    out_path = write_output!(tmp_dir, "lib/resource.ex", "defmodule Resource do\nend\n")

    receipt =
      Receipt.new(%{
        standing: :alive,
        recipe_key: "templates/resource.ex.eex=>lib/resource.ex",
        pre_run_hash: nil,
        post_run_hash: Receipt.hash_files([out_path]),
        files: [out_path],
        events: [],
        reason: nil,
        metadata: %{}
      })

    single_object_path = Path.join(tmp_dir, "extracted_receipt.json")
    File.write!(single_object_path, Jason.encode!(Receipt.to_json_map(receipt)))

    assert {:ok, loaded_receipt} = Replay.load_receipt(single_object_path)
    report = Replay.build_report(loaded_receipt, tmp_dir)

    assert report.categories == []
  end
end
