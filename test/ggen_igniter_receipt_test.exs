defmodule GgenIgniter.ReceiptTest do
  @moduledoc """
  Chicago-style, no-mocks unit proof of `GgenIgniter.Receipt`: real structs,
  real SHA-256 hashing, real file reads/writes under `System.tmp_dir!/0`.
  No mocking anywhere in this file.
  """

  use ExUnit.Case, async: true

  alias GgenIgniter.Receipt

  defp scratch_dir! do
    dir =
      Path.join(
        System.tmp_dir!(),
        "ggen_igniter_receipt_test_#{System.unique_integer([:positive])}"
      )

    File.rm_rf!(dir)
    File.mkdir_p!(dir)
    on_exit(fn -> File.rm_rf!(dir) end)
    dir
  end

  describe "standings/0 and new/1" do
    test "exposes exactly the five required standings" do
      assert Receipt.standings() == [
               :alive,
               :refused,
               :compensated,
               :build_broken,
               :compensation_failed
             ]
    end

    for standing <- [:alive, :refused, :compensated, :build_broken, :compensation_failed] do
      test "new/1 accepts standing #{inspect(standing)}" do
        receipt = Receipt.new(%{standing: unquote(standing)})
        assert receipt.standing == unquote(standing)
        assert is_binary(receipt.id)
        assert String.starts_with?(receipt.id, "rcpt_")
      end
    end

    test "new/1 raises ArgumentError for an invented standing" do
      assert_raise ArgumentError, ~r/must be one of/, fn ->
        Receipt.new(%{standing: :made_up})
      end
    end

    test "new/1 defaults files/events/metadata to empty and reason to nil" do
      receipt = Receipt.new(%{standing: :alive})
      assert receipt.files == []
      assert receipt.events == []
      assert receipt.metadata == %{}
      assert receipt.reason == nil
    end
  end

  describe "hash_entries/1 and hash_files/1" do
    test "is order-independent (same set of {path, content} pairs hash identically)" do
      forward = Receipt.hash_entries([{"a.ex", "alpha"}, {"b.ex", "beta"}])
      backward = Receipt.hash_entries([{"b.ex", "beta"}, {"a.ex", "alpha"}])
      assert forward == backward
    end

    test "a nil (absent) entry hashes differently from an entry with real content" do
      absent = Receipt.hash_entries([{"a.ex", nil}])
      present = Receipt.hash_entries([{"a.ex", "alpha"}])
      assert absent != present
    end

    test "hash_files/1 reads REAL current on-disk content, matching hash_entries/1 for the same bytes" do
      dir = scratch_dir!()
      path = Path.join(dir, "real.ex")
      File.write!(path, "defmodule Real do\nend\n")

      assert Receipt.hash_files([path]) ==
               Receipt.hash_entries([{path, "defmodule Real do\nend\n"}])
    end

    test "hash_files/1 treats a missing real file the same as a nil entry" do
      dir = scratch_dir!()
      missing_path = Path.join(dir, "does_not_exist.ex")
      refute File.exists?(missing_path)

      assert Receipt.hash_files([missing_path]) == Receipt.hash_entries([{missing_path, nil}])
    end

    test "changing real file content changes the real hash" do
      dir = scratch_dir!()
      path = Path.join(dir, "changing.ex")

      File.write!(path, "v1")
      hash1 = Receipt.hash_files([path])

      File.write!(path, "v2")
      hash2 = Receipt.hash_files([path])

      assert hash1 != hash2
    end
  end

  describe "append!/2 and read_all!/1 -- real append-only JSONL persistence" do
    test "a fresh base_dir with no receipts yet reads back as an empty list" do
      dir = scratch_dir!()
      assert Receipt.read_all!(dir) == []
    end

    test "appending a receipt persists it as real, readable JSON on disk" do
      dir = scratch_dir!()

      receipt =
        Receipt.new(%{
          standing: :compensated,
          recipe_key: "template.eex=>out.ex",
          files: ["lib/out.ex"],
          pre_run_hash: "sha256:before",
          post_run_hash: "sha256:before",
          reason: "a real reason string"
        })

      assert :ok = Receipt.append!(dir, receipt)

      [persisted] = Receipt.read_all!(dir)
      assert persisted["standing"] == "compensated"
      assert persisted["recipe_key"] == "template.eex=>out.ex"
      assert persisted["files"] == ["lib/out.ex"]
      assert persisted["pre_run_hash"] == "sha256:before"
      assert persisted["post_run_hash"] == "sha256:before"
      assert persisted["reason"] == "a real reason string"

      # The real file on disk really is one JSON object per line.
      receipt_path = Receipt.path(dir)
      assert File.exists?(receipt_path)
      lines = receipt_path |> File.read!() |> String.split("\n", trim: true)
      assert length(lines) == 1
      assert {:ok, _} = Jason.decode(List.first(lines))
    end

    test "appending multiple receipts preserves real chronological order, never overwriting a prior line" do
      dir = scratch_dir!()

      Receipt.append!(dir, Receipt.new(%{standing: :refused, reason: "first"}))
      Receipt.append!(dir, Receipt.new(%{standing: :alive, reason: "second"}))
      Receipt.append!(dir, Receipt.new(%{standing: :compensated, reason: "third"}))

      persisted = Receipt.read_all!(dir)
      assert Enum.map(persisted, & &1["reason"]) == ["first", "second", "third"]
    end
  end

  describe "PRD v2 fields -- new/1 defaults" do
    test "new/1 (unchanged arity) defaults every PRD v2 field to its real, honest default" do
      receipt = Receipt.new(%{standing: :alive})

      assert receipt.schema_version == "1"
      assert receipt.tool_version == Mix.Project.config()[:version]
      assert receipt.operation == nil
      assert receipt.inputs == []
      assert receipt.queries == []
      assert receipt.engine == nil
      assert receipt.outputs == []
      assert receipt.skipped_outputs == []
      assert receipt.commands == []
      assert receipt.source_hash == nil
      assert receipt.plan_hash == nil
      assert receipt.pre_state_hash == nil
      assert receipt.result_hash == nil
      assert receipt.parent_hash == nil
      assert receipt.completed_at == nil
      assert is_binary(receipt.receipt_hash)
      assert String.starts_with?(receipt.receipt_hash, "sha256:")
    end

    test "new/1 preserves caller-supplied PRD v2 field values" do
      receipt =
        Receipt.new(%{
          standing: :alive,
          operation: "sync",
          inputs: ["ontology.ttl"],
          queries: ["spec=alpha.rq"],
          engine: "oxigraph",
          outputs: ["lib/alpha.ex"],
          skipped_outputs: ["lib/skip.ex"],
          commands: ["mix compile --warnings-as-errors"],
          source_hash: "sha256:src",
          plan_hash: "sha256:plan",
          pre_state_hash: "sha256:pre",
          result_hash: "sha256:result",
          completed_at: "2026-08-27T12:00:00Z"
        })

      assert receipt.operation == "sync"
      assert receipt.inputs == ["ontology.ttl"]
      assert receipt.queries == ["spec=alpha.rq"]
      assert receipt.engine == "oxigraph"
      assert receipt.outputs == ["lib/alpha.ex"]
      assert receipt.skipped_outputs == ["lib/skip.ex"]
      assert receipt.commands == ["mix compile --warnings-as-errors"]
      assert receipt.source_hash == "sha256:src"
      assert receipt.plan_hash == "sha256:plan"
      assert receipt.pre_state_hash == "sha256:pre"
      assert receipt.result_hash == "sha256:result"
      assert receipt.completed_at == "2026-08-27T12:00:00Z"
    end

    test "to_json_map/1 round-trips every PRD v2 field through real Jason encode/decode" do
      receipt =
        Receipt.new(%{
          standing: :alive,
          operation: "sync",
          engine: "oxigraph",
          outputs: ["lib/alpha.ex"]
        })

      json = receipt |> Receipt.to_json_map() |> Jason.encode!() |> Jason.decode!()

      assert json["schema_version"] == "1"
      assert json["tool_version"] == receipt.tool_version
      assert json["operation"] == "sync"
      assert json["engine"] == "oxigraph"
      assert json["outputs"] == ["lib/alpha.ex"]
      assert json["receipt_hash"] == receipt.receipt_hash
    end
  end

  describe "compute_receipt_hash/1 -- real chain-integrity digest" do
    test "is deterministic for the same real receipt content" do
      receipt = Receipt.new(%{standing: :alive, files: ["a.ex"]})
      assert Receipt.compute_receipt_hash(receipt) == Receipt.compute_receipt_hash(receipt)
    end

    test "changes when any real field of the receipt changes" do
      receipt = Receipt.new(%{standing: :alive, reason: "one"})
      changed = %{receipt | reason: "two"}

      assert Receipt.compute_receipt_hash(receipt) != Receipt.compute_receipt_hash(changed)
    end

    test "new/1 populates receipt_hash with the real digest of its own content" do
      receipt = Receipt.new(%{standing: :alive, files: ["a.ex"]})
      assert receipt.receipt_hash == Receipt.compute_receipt_hash(receipt)
    end

    test "an explicitly-supplied receipt_hash is preserved verbatim (round-trip case)" do
      receipt = Receipt.new(%{standing: :alive, receipt_hash: "sha256:preserved"})
      assert receipt.receipt_hash == "sha256:preserved"
    end
  end

  describe "new/2 -- real parent_hash chain-linking via reconstruct_standing/2" do
    test "the first receipt for a recipe_key has a nil parent_hash (honest rootless case)" do
      dir = scratch_dir!()

      receipt =
        Receipt.new(%{standing: :alive, recipe_key: "t.eex=>out.ex"}, base_dir: dir)

      assert receipt.parent_hash == nil
    end

    test "a second real receipt for the same recipe_key chains parent_hash to the first's real receipt_hash" do
      dir = scratch_dir!()

      first =
        Receipt.new(
          %{
            standing: :alive,
            recipe_key: "t.eex=>out.ex",
            pre_run_hash: "sha256:p0",
            post_run_hash: "sha256:p1"
          },
          base_dir: dir
        )

      :ok = Receipt.append!(dir, first)

      second =
        Receipt.new(
          %{
            standing: :alive,
            recipe_key: "t.eex=>out.ex",
            pre_run_hash: "sha256:p1",
            post_run_hash: "sha256:p2"
          },
          base_dir: dir
        )

      assert second.parent_hash == first.receipt_hash
      assert is_binary(second.parent_hash)
    end

    test "an explicit parent_hash in attrs is never overridden by the base_dir lookup" do
      dir = scratch_dir!()

      first = Receipt.new(%{standing: :alive, recipe_key: "t.eex=>out.ex"}, base_dir: dir)
      :ok = Receipt.append!(dir, first)

      second =
        Receipt.new(
          %{standing: :alive, recipe_key: "t.eex=>out.ex", parent_hash: "sha256:explicit"},
          base_dir: dir
        )

      assert second.parent_hash == "sha256:explicit"
    end
  end

  describe "to_prd_status/1" do
    test "maps every real standing (struct and bare atom) to its PRD status" do
      assert Receipt.to_prd_status(:alive) == "ALIVE"
      assert Receipt.to_prd_status(:refused) == "BLOCKED"
      assert Receipt.to_prd_status(:compensated) == "PARTIAL_ALIVE"
      assert Receipt.to_prd_status(:build_broken) == "BUILD_BROKEN"
      assert Receipt.to_prd_status(:compensation_failed) == "PARTIAL_ALIVE"

      for standing <- Receipt.standings() do
        receipt = Receipt.new(%{standing: standing})
        assert Receipt.to_prd_status(receipt) == Receipt.to_prd_status(standing)
      end
    end

    test "an unrecognized standing atom maps to the honest UNKNOWN fallback" do
      assert Receipt.to_prd_status(:something_invented) == "UNKNOWN"
    end
  end
end
