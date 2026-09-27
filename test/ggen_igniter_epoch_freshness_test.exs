defmodule GgenIgniter.EpochFreshnessTest do
  @moduledoc """
  Falsifier corpus for the epoch freshness court. Every verdict atom of
  `GgenIgniter.EpochFreshness` is witnessed by at least one test over a
  REAL temp git repository (the same anti-vacuity discipline as the agent
  guard tests: a gate whose firings are not witnessed carries no bits).

  The anti-vacuity pair at the end is the court's proof of discrimination:
  a fully fresh attributed tree passes, the same tree with one stamped
  pre-epoch file re-added fails. If both ever pass, or both ever fail, the
  court is decoration.
  """

  use ExUnit.Case, async: false

  alias GgenIgniter.{EpochFreshness, EpochWatermark}

  @epoch "v26.10.1"
  @boundary ~U[2026-09-30 12:00:00Z]
  @post_watermark "2026-10-01T09:00:00Z"
  @pre_watermark "2026-09-01T09:00:00Z"

  @legacy_book """
  defmodule Legacy.Book do
    defstruct [:title, :isbn]

    def new(title, isbn), do: %__MODULE__{title: title, isbn: isbn}

    def display(%__MODULE__{title: title}), do: String.upcase(title)

    def valid?(%__MODULE__{isbn: isbn}), do: is_binary(isbn) and byte_size(isbn) == 13

    def shelf_code(%__MODULE__{title: title, isbn: isbn}) do
      "\#{String.slice(title, 0, 3)}-\#{isbn}"
    end

    def metadata(%__MODULE__{title: title, isbn: isbn}) do
      %{chars: String.length(title), digits: Integer.parse(isbn) |> elem(0), code: :book}
    end

    def summary(books), do: Enum.count(books, &valid?/1)
  end
  """

  @legacy_helpers """
  defmodule Legacy.Helpers do
    def pad(value, width), do: String.pad_leading(value, width)

    def truncate(value, max), do: String.slice(value, 0, max)

    def join(parts, sep), do: Enum.join(parts, sep)
  end
  """

  setup do
    dir = fresh_repo()
    on_exit(fn -> File.rm_rf(dir) end)
    %{dir: dir}
  end

  # -- the witness corpus -------------------------------------------------------

  test "keep-old: an unchanged pre-epoch implementation file is REFUSED_LEGACY_EDIT", %{dir: dir} do
    stamp_watermark(dir)

    {:ok, report} = EpochFreshness.check(dir, @epoch)

    assert %{"verdict" => :REFUSED_LEGACY_EDIT} = file_report(report, "lib/legacy.ex")
    assert report["standing"] == :REFUSED
  end

  test "edit-old: a trivially edited pre-epoch file is still REFUSED_LEGACY_EDIT", %{dir: dir} do
    stamp_watermark(dir)

    File.write!(Path.join(dir, "lib/legacy.ex"), @legacy_book <> "\n# touched\n")
    commit_all(dir, "touch legacy")

    {:ok, report} = EpochFreshness.check(dir, @epoch)

    assert %{"verdict" => :REFUSED_LEGACY_EDIT} = file_report(report, "lib/legacy.ex")
  end

  test "copy-to-new-name: byte-identical legacy content at a new path is REFUSED_COPY_READD", %{
    dir: dir
  } do
    stamp_watermark(dir)

    File.rm!(Path.join(dir, "lib/legacy.ex"))
    File.write!(Path.join(dir, "lib/copy.ex"), @legacy_book)
    commit_all(dir, "rename legacy to copy")

    {:ok, report} = EpochFreshness.check(dir, @epoch)

    assert %{"verdict" => :REFUSED_COPY_READD, "closest_pre_epoch_match" => "lib/legacy.ex"} =
             file_report(report, "lib/copy.ex")
  end

  test "similar hand-rewrite without attribution is REFUSED_UNEXPLAINED_SIMILARITY", %{dir: dir} do
    stamp_watermark(dir)

    File.rm!(Path.join(dir, "lib/legacy.ex"))
    File.write!(Path.join(dir, "lib/manual.ex"), similar_rewritten_book())

    # The fixture must actually clear the threshold, or this test proves nothing.
    assert EpochFreshness.similarity(similar_rewritten_book(), @legacy_book) >= 0.9

    {:ok, report} = EpochFreshness.check(dir, @epoch)

    assert %{"verdict" => :REFUSED_UNEXPLAINED_SIMILARITY, "similarity" => s} =
             file_report(report, "lib/manual.ex")

    assert s >= report["threshold"]
  end

  test "dissimilar hand-write with a dated ledger row is ALIVE_FRESH_RESIDUE", %{dir: dir} do
    stamp_watermark(dir)

    File.rm!(Path.join(dir, "lib/legacy.ex"))
    File.write!(Path.join(dir, "lib/manual.ex"), novel_implementation())
    add_ledger_row(dir, "lib/manual.ex", "2026-10-02")

    {:ok, report} = EpochFreshness.check(dir, @epoch)

    assert %{"verdict" => :ALIVE_FRESH_RESIDUE} = file_report(report, "lib/manual.ex")
  end

  test "KEY DISCRIMINATOR: byte-identical regeneration with a receipt is ALIVE_GENERATED", %{
    dir: dir
  } do
    stamp_watermark(dir)

    # Same bytes as the stamped legacy blob — similarity 1.0 by construction.
    # The receipt (manufacture provenance) is what makes this lawful.
    File.rm!(Path.join(dir, "lib/legacy.ex"))
    File.write!(Path.join(dir, "lib/legacy.ex"), @legacy_book)
    commit_all(dir, "regenerate legacy from ontology")
    write_receipt(dir, ["lib/legacy.ex"], blob_sha: true)

    {:ok, report} = EpochFreshness.check(dir, @epoch)

    assert %{"verdict" => :ALIVE_GENERATED, "similarity" => 1.0} =
             file_report(report, "lib/legacy.ex")
  end

  test "generated-then-edited: bytes diverging from the receipt are REFUSED_GENERATED_ARTIFACT_MUTATED",
       %{dir: dir} do
    stamp_watermark(dir)

    File.rm!(Path.join(dir, "lib/legacy.ex"))
    File.write!(Path.join(dir, "lib/legacy.ex"), @legacy_book)
    commit_all(dir, "regenerate legacy from ontology")
    write_receipt(dir, ["lib/legacy.ex"], blob_sha: true)

    File.write!(Path.join(dir, "lib/legacy.ex"), @legacy_book <> "\n# sneaky hand edit\n")

    {:ok, report} = EpochFreshness.check(dir, @epoch)

    assert %{"verdict" => :REFUSED_GENERATED_ARTIFACT_MUTATED} =
             file_report(report, "lib/legacy.ex")
  end

  test "brand-new file with no provenance at all is REFUSED_NO_ATTRIBUTION", %{dir: dir} do
    stamp_watermark(dir)

    File.rm!(Path.join(dir, "lib/legacy_helpers.ex"))
    File.write!(Path.join(dir, "lib/novel.ex"), novel_implementation())
    commit_all(dir, "add novel")

    {:ok, report} = EpochFreshness.check(dir, @epoch)

    assert %{"verdict" => :REFUSED_NO_ATTRIBUTION} = file_report(report, "lib/novel.ex")
  end

  test "only-pre-watermark receipt: a new file whose only receipt predates the boundary is REFUSED_PRE_EPOCH_RECEIPT",
       %{dir: dir} do
    stamp_watermark(dir)

    File.rm!(Path.join(dir, "lib/legacy_helpers.ex"))
    File.write!(Path.join(dir, "lib/old_receipt.ex"), novel_implementation())
    write_receipt(dir, ["lib/old_receipt.ex"], blob_sha: true, at: @pre_watermark)

    {:ok, report} = EpochFreshness.check(dir, @epoch)

    assert %{"verdict" => :REFUSED_PRE_EPOCH_RECEIPT} =
             file_report(report, "lib/old_receipt.ex")
  end

  test "fail closed: a never-stamped epoch refuses the whole run", %{dir: dir} do
    assert {:error, {:refused_epoch_check, %{code: :watermark_not_found, detail: _}}} =
             EpochFreshness.check(dir, "v27.1.1")
  end

  test "fail closed: a corrupt watermark refuses instead of faking absence", %{dir: dir} do
    watermark_path = EpochWatermark.path(dir, @epoch)
    File.mkdir_p!(Path.dirname(watermark_path))
    File.write!(watermark_path, "not json at all")

    assert {:error, {:refused_epoch_check, %{code: :watermark_not_found, detail: detail}}} =
             EpochFreshness.check(dir, @epoch)

    assert detail =~ "not decodable"
  end

  test "fail closed: a non-git base_dir refuses even with a hand-placed watermark", %{} do
    dir = fresh_dir_without_git()

    on_exit(fn -> File.rm_rf(dir) end)

    watermark = %{
      "schema_version" => "1",
      "epoch" => @epoch,
      "watermark_instant" => DateTime.to_iso8601(@boundary),
      "head_sha" => String.duplicate("a", 40),
      "tree_sha" => String.duplicate("b", 40),
      "implementation_glob" => "lib/**/*.ex",
      "files" => []
    }

    watermark_path = EpochWatermark.path(dir, @epoch)
    File.mkdir_p!(Path.dirname(watermark_path))
    File.write!(watermark_path, Jason.encode!(watermark))

    File.mkdir_p!(Path.join(dir, "lib"))
    File.write!(Path.join(dir, "lib/x.ex"), "defmodule X do\nend")

    assert {:error, {:refused_epoch_check, %{code: :not_a_git_work_tree}}} =
             EpochFreshness.check(dir, @epoch)
  end

  test "unreadable candidate is UNKNOWN_PROVENANCE and counts as refused", %{dir: dir} do
    stamp_watermark(dir)
    File.rm!(Path.join(dir, "lib/legacy_helpers.ex"))

    # A path matching the implementation glob that cannot be read as a file.
    File.mkdir!(Path.join(dir, "lib/weird.ex"))

    {:ok, report} = EpochFreshness.check(dir, @epoch)

    assert %{"verdict" => :UNKNOWN_PROVENANCE, "source_inputs" => [reason]} =
             file_report(report, "lib/weird.ex")

    assert reason =~ "unreadable"
    assert report["implementation_files"]["refused"] >= 1
  end

  # -- ANTI-VACUITY PAIR ---------------------------------------------------------

  test "anti-vacuity (a): a fully fresh attributed tree stands ALIVE", %{dir: dir} do
    stamp_watermark(dir)

    # legacy.ex: regenerated byte-identically, receipted (receipt admits).
    File.rm!(Path.join(dir, "lib/legacy.ex"))
    File.write!(Path.join(dir, "lib/legacy.ex"), @legacy_book)
    write_receipt(dir, ["lib/legacy.ex"], blob_sha: true)

    # legacy_helpers.ex: deleted, replaced by ledgered fresh residue.
    File.rm!(Path.join(dir, "lib/legacy_helpers.ex"))
    File.write!(Path.join(dir, "lib/manual.ex"), novel_implementation())
    add_ledger_row(dir, "lib/manual.ex", "2026-10-02")
    commit_all(dir, "fresh epoch tree")

    {:ok, report} = EpochFreshness.check(dir, @epoch)

    assert report["standing"] == :ALIVE

    counts = report["implementation_files"]

    assert counts["admitted_generated"] == 1
    assert counts["admitted_residue"] == 1
    assert counts["refused"] == 0

    assert counts["total"] ==
             counts["admitted_generated"] + counts["admitted_residue"] + counts["refused"]
  end

  test "anti-vacuity (b): the same tree with one stamped legacy file re-added REFUSES", %{
    dir: dir
  } do
    stamp_watermark(dir)

    File.rm!(Path.join(dir, "lib/legacy.ex"))
    File.write!(Path.join(dir, "lib/legacy.ex"), @legacy_book)
    write_receipt(dir, ["lib/legacy.ex"], blob_sha: true)
    File.rm!(Path.join(dir, "lib/legacy_helpers.ex"))
    File.write!(Path.join(dir, "lib/manual.ex"), novel_implementation())
    add_ledger_row(dir, "lib/manual.ex", "2026-10-02")
    commit_all(dir, "fresh epoch tree")

    # The smuggling: the pre-epoch helpers file comes back, unattributed.
    File.write!(Path.join(dir, "lib/legacy_helpers.ex"), @legacy_helpers)

    {:ok, report} = EpochFreshness.check(dir, @epoch)

    assert report["standing"] == :REFUSED
    assert %{"verdict" => :REFUSED_LEGACY_EDIT} = file_report(report, "lib/legacy_helpers.ex")
  end

  # -- watermark idempotency + restamp ------------------------------------------

  test "watermark: identical re-stamp is idempotent, changed tree requires --restamp", %{dir: dir} do
    {:ok, first, _} = EpochWatermark.stamp!(dir, @epoch, now: @boundary)
    {:ok, second, _} = EpochWatermark.stamp!(dir, @epoch, now: @boundary)

    assert first["files"] == second["files"]
    assert first["tree_sha"] == second["tree_sha"]

    File.write!(Path.join(dir, "lib/legacy.ex"), @legacy_book <> "\n# epoch drift\n")
    commit_all(dir, "drift after the boundary")

    assert {:error, {:refused_epoch_watermark, %{code: :restamp_required}}} =
             EpochWatermark.stamp!(dir, @epoch, now: @boundary)

    {:ok, restamped, _} =
      EpochWatermark.stamp!(dir, @epoch, now: @boundary, restamp: %{reason: "boundary moved"})

    assert restamped["restamp_reason"] == "boundary moved"
    assert restamped["tree_sha"] != first["tree_sha"]
  end

  test "watermark: empty implementation set refuses to stamp a boundary over nothing", %{dir: dir} do
    File.rm_rf!(Path.join(dir, "lib"))
    commit_all(dir, "remove lib")

    assert {:error, {:refused_epoch_watermark, %{code: :empty_implementation_set}}} =
             EpochWatermark.stamp!(dir, @epoch, now: @boundary)
  end

  # -- report shape --------------------------------------------------------------

  test "report carries the contract shape: subject identity, informing authorship, counts that add up",
       %{dir: dir} do
    stamp_watermark(dir)

    {:ok, report} = EpochFreshness.check(dir, @epoch)

    assert Regex.match?(~r/\A[0-9a-f]{64}\z/, report["subject_tree"])
    assert report["watermark_tree"] =~ ~r/\A[0-9a-f]{40}\z/
    assert report["threshold"] == 0.9
    assert report["epoch"] == @epoch

    Enum.each(report["files"], fn file ->
      assert MapSet.subset?(
               MapSet.new(Map.keys(file)),
               MapSet.new([
                 "path",
                 "blob_sha",
                 "provenance_kind",
                 "manufacture_receipt",
                 "source_inputs",
                 "closest_pre_epoch_match",
                 "similarity",
                 "authorship_newest",
                 "verdict"
               ])
             )

      if authorship = file["authorship_newest"] do
        assert {:ok, _, _} = DateTime.from_iso8601(authorship)
      end
    end)

    counts = report["implementation_files"]

    assert counts["total"] ==
             counts["admitted_generated"] + counts["admitted_residue"] + counts["refused"]
  end

  # -- explain -------------------------------------------------------------------

  test "explain returns the verdict plus the law that would admit the file", %{dir: dir} do
    stamp_watermark(dir)

    {:ok, explanation} = EpochFreshness.explain(dir, @epoch, "lib/legacy.ex")

    assert explanation["verdict"] == :REFUSED_LEGACY_EDIT
    assert explanation["law"] =~ "Delete it and let ggen_igniter manufacture the replacement"
    assert explanation["threshold"] == 0.9
  end

  test "explain refuses a path outside the base dir", %{dir: dir} do
    stamp_watermark(dir)

    assert {:error, {:refused_epoch_check, %{code: :file_outside_base_dir}}} =
             EpochFreshness.explain(dir, @epoch, "../elsewhere/lib/x.ex")
  end

  # -- similarity unit law ---------------------------------------------------------

  test "similarity: byte-equal is 1.0, dissimilar modules are below the threshold" do
    assert EpochFreshness.similarity(@legacy_book, @legacy_book) == 1.0
    assert EpochFreshness.similarity(@legacy_book, novel_implementation()) < 0.9
  end

  test "similarity: reformat and comment-only changes stay high — reformatting does not launder legacy" do
    reformatted =
      @legacy_book
      |> String.replace("\n  ", "\n        ")
      |> then(&(&1 <> "\n# reformatted only, no semantic change\n"))

    score = EpochFreshness.similarity(reformatted, @legacy_book)
    assert score >= 0.9
  end

  # -- fixtures ----------------------------------------------------------------

  defp fresh_repo do
    dir =
      Path.join(System.tmp_dir!(), "epoch-freshness-#{:erlang.unique_integer([:positive])}")

    File.mkdir_p!(Path.join(dir, "lib"))
    git!(dir, ["init"])
    git!(dir, ["config", "user.email", "epoch@test"])
    git!(dir, ["config", "user.name", "epoch test"])

    File.write!(Path.join(dir, "lib/legacy.ex"), @legacy_book)
    File.write!(Path.join(dir, "lib/legacy_helpers.ex"), @legacy_helpers)
    commit_all(dir, "legacy implementation")

    dir
  end

  defp fresh_dir_without_git do
    dir = Path.join(System.tmp_dir!(), "epoch-nogit-#{:erlang.unique_integer([:positive])}")
    File.mkdir_p!(dir)
    dir
  end

  defp commit_all(dir, message) do
    git!(dir, ["add", "."])
    git!(dir, ["commit", "--no-gpg-sign", "-m", message])
  end

  defp git!(dir, args) do
    {out, code} = System.cmd("git", args, cd: dir, stderr_to_stdout: true)

    if code != 0, do: flunk("git #{Enum.join(args, " ")} failed: #{out}")

    out
  end

  defp stamp_watermark(dir, opts \\ []) do
    default = [now: @boundary]

    assert {:ok, _manifest, _path} =
             EpochWatermark.stamp!(dir, @epoch, Keyword.merge(default, opts))
  end

  defp write_receipt(dir, files, opts) do
    with_blob? = Keyword.get(opts, :blob_sha, false)
    finished_at = Keyword.get(opts, :at, @post_watermark)

    outputs =
      if with_blob? do
        Enum.map(files, fn f ->
          content = File.read!(Path.join(dir, f))
          %{"path" => f, "hash" => EpochWatermark.blob_sha(content)}
        end)
      else
        files
      end

    receipt = %{
      "id" => "receipt-test-#{System.unique_integer([:positive])}",
      "recipe_key" => "test-recipe",
      "standing" => "alive",
      "finished_at" => finished_at,
      "files" => files,
      "outputs" => outputs
    }

    receipts_dir = Path.join([dir, ".ggen_igniter", "receipts"])
    File.mkdir_p!(receipts_dir)

    File.write!(
      Path.join(receipts_dir, receipt["id"] <> ".jsonl"),
      Jason.encode!(receipt) <> "\n"
    )
  end

  defp add_ledger_row(dir, path, date) do
    File.write!(
      Path.join(dir, "HANDWRITTEN.md"),
      "# HANDWRITTEN — the 1% ledger\n\n#{path} | fresh residue element | none | some-pack | #{date}\n"
    )
  end

  defp file_report(report, path) do
    Enum.find(report["files"], &(&1["path"] == path)) ||
      flunk(
        "no file report for #{path}; got: #{inspect(Enum.map(report["files"], & &1["path"]))}"
      )
  end

  defp similar_rewritten_book do
    """
    defmodule Legacy.Book do
      defstruct [:title, :isbn]

      def new(title, isbn), do: %__MODULE__{title: title, isbn: isbn}

      def display(%__MODULE__{title: title}), do: String.downcase(title)

      def valid?(%__MODULE__{isbn: isbn}), do: is_binary(isbn) and byte_size(isbn) == 13

      def shelf_code(%__MODULE__{title: title, isbn: isbn}) do
        "\#{String.slice(title, 0, 3)}-\#{isbn}"
      end

      def metadata(%__MODULE__{title: title, isbn: isbn}) do
        %{chars: String.length(title), digits: Integer.parse(isbn) |> elem(0), code: :book}
      end

      def summary(books), do: Enum.count(books, &valid?/1)
    end
    """
  end

  # Genuinely different semantics: different module name, different calls,
  # different shape — the positive case for fresh hand-written residue.
  defp novel_implementation do
    """
    defmodule EpochNovel.Catalog do
      @behaviour :gen_statem

      def render_items(items, opts \\\\ []) do
        items
        |> Enum.reverse()
        |> Enum.with_index()
        |> Enum.map_join("\\n", fn {item, i} -> format_row(item, i, opts) end)
      end

      defp format_row({%{name: name, tags: tags}, i}, idx, opts) do
        width = Keyword.get(opts, :width, 8)
        suffix = if Enum.any?(tags, &(&1 == :archived)), do: " [a]", else: ""
        "\#{idx}. " <> :io_lib.format("~\#{width}s", [name]) <> suffix
      end

      defp format_row(_, _, _), do: ""
    end
    """
  end
end
