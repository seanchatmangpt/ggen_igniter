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
end
