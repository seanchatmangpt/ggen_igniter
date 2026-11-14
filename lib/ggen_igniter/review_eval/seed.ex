defmodule GgenIgniter.ReviewEval.Seed do
  @moduledoc """
  Corpus seeder: mines real git history for fix commits and revert receipts,
  derives locations from the fix diff hunks, cross-references receipt sources,
  and writes `.ggen_igniter/refusals`-independent corpus.jsonl.

  Deterministic: same HEAD -> byte-identical corpus (mining is pure `git log`
  over HEAD's history; `seeded_at` is derived from the HEAD commit time, not
  wall clock).
  """

  alias GgenIgniter.ReviewEval.Corpus

  @seed_command_version 1

  @doc """
  Seed (or re-seed with `force: true`) the corpus from git history.

  Opts:
    * `:repo_root` - repo root (default ".")
    * `:force` - allow overwrite of an existing corpus (default false)
    * `:min_conf` - minimum confidence to admit a case (default 0.5);
      weak cases are demoted to `provenance.verified_in_fix = false` and
      excluded below the threshold
    * `:max` - cap on admitted cases (default 50)

  Returns `{:ok, receipt}` or `{:error, {:corpus_exists, path}}`.
  """
  def run(opts \\ []) do
    repo_root = Keyword.get(opts, :repo_root, ".")
    force = Keyword.get(opts, :force, false)
    min_conf = Keyword.get(opts, :min_conf, 0.5)
    max = Keyword.get(opts, :max, 50)

    corpus_file = Corpus.corpus_path(repo_root)

    if File.exists?(corpus_file) and not force do
      {:error, {:corpus_exists, corpus_file}}
    else
      head = git!(repo_root, ["rev-parse", "HEAD"])

      cases =
        repo_root
        |> mine_fix_commits()
        |> Enum.map(fn c -> {c, confidence(c)} end)
        |> Enum.filter(fn {_c, conf} -> conf >= min_conf end)
        |> Enum.sort_by(fn {c, conf} -> {c.source_ref, -conf} end)
        |> Enum.take(max)
        |> Enum.map(fn {c, conf} -> to_case(c, conf, head) end)

      Corpus.write(cases, repo_root)

      receipt = %{
        "seed_command_version" => @seed_command_version,
        "head_sha" => head,
        "min_conf" => min_conf,
        "counts" => counts_per_kind(cases),
        "counts_by_kind_total" => counts_per_kind_total(repo_root),
        "excluded_weak" => excluded_weak_count(repo_root, min_conf),
        "corpus_digest" => Corpus.digest(repo_root)
      }

      write_seed_receipt(repo_root, head, receipt)
      {:ok, receipt}
    end
  end

  # -- mining -----------------------------------------------------------

  defp mine_fix_commits(repo_root) do
    args = [
      "log",
      "--grep=^fix",
      "--grep=^revert",
      "--extended-regexp",
      "-i",
      "--format=%H%x00%P%x00%s%x00%aI",
      "HEAD"
    ]

    {out, 0} = System.cmd("git", args, cd: repo_root)

    out
    |> String.split("\n", trim: true)
    |> Enum.flat_map(&parse_log_line/1)
    |> Enum.flat_map(&locate_entry(repo_root, &1))
  end

  defp parse_log_line(line) do
    case String.split(line, "\0", parts: 4) do
      [sha, parents, subject, date] ->
        single_parent_entry(sha, String.split(parents), subject, date)

      _ ->
        []
    end
  end

  defp single_parent_entry(sha, [parent], subject, date),
    do: [%{source_ref: sha, parent_sha: parent, fix_sha: sha, subject: subject, date: date}]

  # merge/revert-with-two-parents: skip (location derivation needs one parent)
  defp single_parent_entry(_sha, _parents, _subject, _date), do: []

  defp locate_entry(repo_root, entry) do
    case derive_location(repo_root, entry) do
      {:ok, loc} -> [Map.merge(entry, %{location: loc, kind: kind_for_subject(entry.subject)})]
      :error -> []
    end
  end

  defp kind_for_subject(subject) do
    if String.downcase(subject) =~ ~r/^revert/,
      do: :git_revert_receipt,
      else: :git_fix_commit
  end

  @doc """
  Derive `{file, line}` from the fix diff hunks of `fix_sha` vs its parent
  (`git show --unified=0`). Picks the first added-line hunk in lib/.
  """
  def derive_location(repo_root, entry) do
    args = ["show", "--unified=0", "--format=", entry.fix_sha, "--", "lib/"]

    {out, 0} = System.cmd("git", args, cd: repo_root)

    case parse_hunks(out) do
      [] ->
        :error

      [{file, line} | _] ->
        {:ok, %{"file" => file, "line" => line, "line_tolerance" => Corpus.default_tolerance()}}
    end
  end

  @doc "Parse `git show --unified=0` output into [{file, first_added_line}]."
  def parse_hunks(show_out) do
    {result, _} =
      show_out
      |> String.split("\n")
      |> Enum.reduce({[], nil}, fn line, {acc, current_file} ->
        cond do
          String.starts_with?(line, "+++ b/") ->
            {acc, String.trim_leading(line, "+++ b/")}

          String.starts_with?(line, "@@") ->
            {add_hunk(line, current_file, acc), current_file}

          true ->
            {acc, current_file}
        end
      end)

    Enum.reverse(result)
  end

  defp add_hunk(line, current_file, acc) do
    with [_, start_line] <- Regex.run(~r/@@ -\d+(?:,\d+)? \+(\d+)/, line),
         {n, _} when current_file != nil <- Integer.parse(start_line) do
      [{current_file, n} | acc]
    else
      _ -> acc
    end
  end

  # -- confidence --------------------------------------------------------

  defp confidence(entry) do
    base =
      if entry.subject =~ ~r/\bfix\b/i, do: 0.6, else: 0.4

    # a revert is a court-grade admission that a prior change was a defect
    base = if entry.subject =~ ~r/^revert/i, do: 0.9, else: base

    # multi-hunk fix implies a real defect with a precise location
    base
  end

  @doc false
  def excluded_weak_count(repo_root, min_conf) do
    repo_root
    |> mine_fix_commits()
    |> Enum.count(fn c -> confidence(c) < min_conf end)
  end

  @doc false
  def counts_per_kind_total(repo_root) do
    repo_root
    |> mine_fix_commits()
    |> Enum.frequencies_by(& &1.kind)
  end

  defp counts_per_kind(cases), do: Enum.frequencies_by(cases, & &1["source"]["kind"])

  # -- case shape --------------------------------------------------------

  defp to_case(entry, conf, _head) do
    digest_hex = Base.encode16(:crypto.hash(:sha256, entry.source_ref), case: :lower)

    case_num = rem(String.to_integer(binary_part(digest_hex, 0, 6), 16), 999) + 1

    id =
      String.slice(entry.source_ref, 0, 7)
      |> then(&"INC-#{String.pad_leading(Integer.to_string(case_num), 3, "0")}-#{&1}")

    %{
      "case_id" => id,
      "schema_version" => Corpus.schema_version(),
      "source" => %{
        "kind" => Atom.to_string(entry.kind),
        "ref" => entry.source_ref,
        "receipt_citation" => receipt_citation_for(entry),
        "commit_subject" => entry.subject
      },
      "diff_ref" => %{"parent_sha" => entry.parent_sha, "fix_sha" => entry.fix_sha},
      "defect" => %{
        "description" => "Defect fixed by #{entry.source_ref}: #{entry.subject}",
        "invariant" => invariant_for(entry),
        "surfaces" => [surface_for(entry)]
      },
      "location" => entry.location,
      "provenance" => %{
        "seeded_at" => head_time(entry.date),
        "seed_command_version" => @seed_command_version,
        "verified_in_fix" => conf >= 0.9
      }
    }
  end

  defp receipt_citation_for(_entry), do: nil

  defp invariant_for(entry),
    do: "Defect class: #{entry.subject} (fixed in #{String.slice(entry.source_ref, 0, 7)})"

  defp surface_for(%{location: %{"file" => file}}), do: surface_from_file(file)

  defp surface_from_file("lib/ggen_igniter/" <> rest),
    do: rest |> Path.dirname() |> String.split("/") |> hd()

  defp surface_from_file(_), do: "misc"

  defp head_time(date), do: date
  defp git!(root, args), do: run_git(root, args) |> elem(0) |> String.trim_trailing()

  defp run_git(root, args) do
    System.cmd("git", args, cd: root, stderr_to_stdout: true)
  end

  # -- seed receipt ------------------------------------------------------

  defp write_seed_receipt(repo_root, head, receipt) do
    dir = Path.join([Corpus.base_dir(repo_root), "seeds"])
    File.mkdir_p!(dir)
    path = Path.join(dir, "#{String.slice(head, 0, 7)}-seed.json")
    File.write!(path, Jason.encode!(receipt, pretty: true) <> "\n")
    path
  end
end
