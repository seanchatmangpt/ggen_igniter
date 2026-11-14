defmodule GgenIgniter.ReviewEval.CorpusTest do
  use ExUnit.Case, async: true

  @moduledoc """
  Chicago-style: real tmp-dir files, real JSON bytes on disk, real sha256.
  """

  alias GgenIgniter.ReviewEval.Corpus

  setup do
    dir =
      Path.join(System.tmp_dir!(), "rv-corpus-#{System.unique_integer([:positive])}")

    File.rm_rf!(dir)
    File.mkdir_p!(dir)
    on_exit(fn -> File.rm_rf!(dir) end)
    {:ok, root: dir}
  end

  defp sample_case(id \\ "INC-001-abc1234") do
    %{
      "case_id" => id,
      "schema_version" => 1,
      "source" => %{
        "kind" => "git_fix_commit",
        "ref" => "abc1234",
        "receipt_citation" => nil,
        "commit_subject" => "fix: thing"
      },
      "diff_ref" => %{
        "parent_sha" => String.duplicate("a", 40),
        "fix_sha" => String.duplicate("b", 40)
      },
      "defect" => %{
        "description" => "desc",
        "invariant" => "f/1 must add",
        "surfaces" => ["review_eval"]
      },
      "location" => %{"file" => "lib/x/y.ex", "line" => 10, "line_tolerance" => 3},
      "provenance" => %{
        "seeded_at" => "2026-10-20",
        "seed_command_version" => 1,
        "verified_in_fix" => true
      }
    }
  end

  describe "write/2 + load/1 roundtrip" do
    test "writes jsonl and loads identical cases back", %{root: root} do
      c1 = sample_case("INC-001-aaa0000")
      c2 = sample_case("INC-002-bbb0000")
      :ok = Corpus.write([c1, c2], root)

      assert {:ok, [^c1, ^c2]} = Corpus.load(root)
    end

    test "load on missing corpus returns empty ok", %{root: root} do
      assert {:ok, []} = Corpus.load(root)
    end
  end

  describe "digest/1" do
    test "is stable for identical bytes and changes with content", %{root: root} do
      Corpus.write([sample_case()], root)
      d1 = Corpus.digest(root)
      d2 = Corpus.digest(root)
      assert d1 == d2
      assert byte_size(d1) == 64

      Corpus.write([sample_case(), sample_case("INC-009-zzz9999")], root)
      refute Corpus.digest(root) == d1
    end
  end

  describe "load/1 malformed input" do
    test "fails closed with the bad line number", %{root: root} do
      Corpus.write([sample_case()], root)
      path = Corpus.corpus_path(root)
      File.write!(path, File.read!(path) <> "{not json\n")

      assert {:error, {:bad_line, 2}} = Corpus.load(root)
    end
  end

  describe "validate_case/1" do
    test "accepts a well-formed case" do
      assert :ok = Corpus.validate_case(sample_case())
    end

    test "rejects unknown source kind and wrong shape" do
      bad = sample_case() |> put_in(["source", "kind"], "nope")
      assert {:error, {:unknown_source_kind, "nope"}} = Corpus.validate_case(bad)
      assert {:error, :invalid_case_shape} = Corpus.validate_case(%{})
    end
  end
end
