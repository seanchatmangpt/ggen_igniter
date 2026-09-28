defmodule GgenIgniter.EpochFreshness do
  @moduledoc """
  The epoch freshness court: judges every implementation-plane file of a
  candidate tree against a stamped `GgenIgniter.EpochWatermark` and returns
  one typed verdict per file.

  ## The law

  Per-file binary, three witnesses, in this order of authority:

    **Receipts admit. Similarity falsifies. Blame informs.**

  A file crosses the boundary only with post-watermark provenance — a ggen
  manufacture receipt or a `HANDWRITTEN.md` residue row dated at or after
  the watermark. High similarity to a pre-epoch file does NOT refuse a
  receipted file (deterministic regeneration from the same ontology SHOULD
  produce similar bytes — that is the architecture working), but it does
  refuse an unattributed or residue file that turns out to be legacy
  implementation wearing a new path. Git authorship timestamps are recorded
  as an informing column and never decide anything, because
  delete-and-re-add launders blame.

  ## Verdict precedence (deterministic)

  1. Post-watermark alive receipt lists the file: a recorded output hash
     that disagrees with the current bytes refuses
     (`REFUSED_GENERATED_ARTIFACT_MUTATED` — generating lawfully and then
     hand-editing the artifact is exactly the smuggling this court exists
     for); otherwise `ALIVE_GENERATED`.
  2. Residue ledger row: similarity ≥ threshold refuses
     (`REFUSED_UNEXPLAINED_SIMILARITY` — "irreducible residue" that
     resembles legacy code is not residue), else `ALIVE_FRESH_RESIDUE`.
  3. No attribution: same path in the watermark ⇒ `REFUSED_LEGACY_EDIT`
     (covers keep, edit, rename-in-place); exact blob match at any path ⇒
     `REFUSED_COPY_READD`; similarity ≥ threshold ⇒
     `REFUSED_UNEXPLAINED_SIMILARITY`; only pre-watermark receipts ⇒
     `REFUSED_PRE_EPOCH_RECEIPT`; else `REFUSED_NO_ATTRIBUTION`.

  Fail closed: a missing watermark, a corrupt watermark, or a non-git
  `base_dir` refuses the whole run rather than admitting anything, and an
  unreadable file is `UNKNOWN_PROVENANCE` (counted as refused) rather than
  skipped.

  ## Honest limits

  Similarity is Jaccard over AST call signatures/atoms and normalized
  lines — not a compiler. A sufficiently creative rewrite defeats it,
  which is precisely why similarity is the FALSIFIER and receipts are the
  admission path. Legacy contents are read back with `git cat-file` and
  pruned to a ±4x byte-size band before comparison; the prune is an
  optimization with an honest direction (a ≥0.9 Jaccard cannot survive a
  4x size difference), not a semantic filter.
  """

  alias GgenIgniter.ArtifactIdentity
  alias GgenIgniter.EpochWatermark

  @verdicts [
    :ALIVE_GENERATED,
    :ALIVE_FRESH_RESIDUE,
    :REFUSED_NO_ATTRIBUTION,
    :REFUSED_PRE_EPOCH_RECEIPT,
    :REFUSED_LEGACY_EDIT,
    :REFUSED_COPY_READD,
    :REFUSED_UNEXPLAINED_SIMILARITY,
    :REFUSED_GENERATED_ARTIFACT_MUTATED,
    :UNKNOWN_PROVENANCE
  ]

  @default_threshold 0.9
  @size_band 4

  @type verdict ::
          :ALIVE_GENERATED
          | :ALIVE_FRESH_RESIDUE
          | :REFUSED_NO_ATTRIBUTION
          | :REFUSED_PRE_EPOCH_RECEIPT
          | :REFUSED_LEGACY_EDIT
          | :REFUSED_COPY_READD
          | :REFUSED_UNEXPLAINED_SIMILARITY
          | :REFUSED_GENERATED_ARTIFACT_MUTATED
          | :UNKNOWN_PROVENANCE

  @type refusal ::
          {:refused_epoch_check,
           %{
             code: :watermark_not_found | :not_a_git_work_tree | :file_outside_base_dir,
             detail: String.t()
           }}

  # Elixir 1.18 typespecs reject binary-literal map keys, so the per-file and
  # report shapes are typed as open string-keyed maps; the exact key contract
  # is the moduledoc's "Verdict precedence" section and _LANES.md Contract v1.
  @typedoc "One file's judgment row: keys path, blob_sha, provenance_kind, manufacture_receipt, source_inputs, closest_pre_epoch_match, similarity, authorship_newest, verdict."
  @type file_report :: %{String.t() => term()}

  @typedoc "Whole-run report: keys schema_version, epoch, subject_tree, watermark_tree, threshold, implementation_files, files, receipts_unparsable_lines, standing, checked_at."
  @type report :: %{String.t() => term()}

  @doc "The closed set of verdict atoms this court returns."
  @spec verdicts() :: [verdict(), ...]
  def verdicts, do: @verdicts

  @doc "Alive iff the verdict atom names survival (`ALIVE_*`)."
  @spec alive?(verdict()) :: boolean()
  def alive?(verdict), do: String.starts_with?(Atom.to_string(verdict), "ALIVE_")

  @doc """
  Judges the candidate implementation tree in `base_dir` against the
  watermark stamped for `epoch`.

  Options: `:watermark` (pre-loaded manifest, skips `EpochWatermark.load/2`),
  `:threshold` (float; watermark's `similarity_threshold` else
  #{@default_threshold}), `:report_path` (persist the report JSON), `:now`
  (`DateTime.t()` for `checked_at`).
  """
  @spec check(String.t(), String.t(), keyword()) :: {:ok, report()} | {:error, refusal()}
  def check(base_dir, epoch, opts \\ []) do
    with {:ok, watermark} <- resolve_watermark(base_dir, epoch, opts),
         :ok <- git_ground!(base_dir) do
      now = Keyword.get(opts, :now, DateTime.utc_now())
      threshold = threshold(opts, watermark)
      ctx = context(base_dir, watermark, now, threshold)

      {files, _cache} = ctx |> list_candidates() |> Enum.map_reduce(%{}, &judge(&1, &2, ctx))

      report =
        %{
          "schema_version" => "1",
          "epoch" => epoch,
          "subject_tree" => subject_tree(files),
          "watermark_tree" => watermark["tree_sha"],
          "threshold" => threshold,
          "implementation_files" => counts(files),
          "files" => files,
          "receipts_unparsable_lines" => ctx.unparsable,
          "standing" => standing(files),
          "checked_at" => DateTime.to_iso8601(now)
        }

      case Keyword.get(opts, :report_path) do
        nil -> :ok
        path -> write_report!(path, report)
      end

      {:ok, report}
    end
  end

  @doc """
  The microscope: the full provenance chain for ONE file, plus `"law"` —
  the specific condition that would make it ALIVE. Read-only by design: a
  refused verdict here is information, not a task failure (the check task
  is the gate; this is the explanation).
  """
  @spec explain(String.t(), String.t(), String.t(), keyword()) ::
          {:ok, map()} | {:error, refusal()}
  def explain(base_dir, epoch, rel_path, opts \\ []) do
    with {:ok, watermark} <- resolve_watermark(base_dir, epoch, opts),
         :ok <- git_ground!(base_dir),
         true <- inside_base?(base_dir, rel_path) do
      threshold = threshold(opts, watermark)
      ctx = context(base_dir, watermark, Keyword.get(opts, :now, DateTime.utc_now()), threshold)
      {file_report, _cache} = judge(rel_path, %{}, ctx)

      {:ok, Map.merge(file_report, %{"threshold" => threshold, "law" => law(file_report)})}
    else
      false ->
        {:error,
         {:refused_epoch_check,
          %{
            code: :file_outside_base_dir,
            detail: "#{rel_path} does not resolve inside #{base_dir}"
          }}}

      error ->
        error
    end
  end

  @doc """
  Jaccard similarity in [0, 1] between two sources: 1.0 on byte equality,
  else the max of an AST feature Jaccard (call signatures + literal atoms)
  and a normalized-line token Jaccard. Deterministic across runs.
  """
  @spec similarity(String.t(), String.t()) :: float()
  def similarity(a, b) when is_binary(a) and is_binary(b) do
    if a == b do
      1.0
    else
      max(ast_jaccard(a, b), token_jaccard(a, b))
    end
  end

  # -- context ----------------------------------------------------------------

  defp resolve_watermark(base_dir, epoch, opts) do
    case Keyword.fetch(opts, :watermark) do
      {:ok, watermark} when is_map(watermark) ->
        {:ok, watermark}

      _ ->
        case EpochWatermark.load(base_dir, epoch) do
          {:ok, watermark} ->
            {:ok, watermark}

          {:error, :not_found} ->
            {:error,
             {:refused_epoch_check,
              %{
                code: :watermark_not_found,
                detail:
                  "no watermark stamped for epoch #{epoch}; run " <>
                    "mix ggen_igniter.epoch.watermark --epoch #{epoch} at the boundary"
              }}}

          {:error, :corrupt} ->
            {:error,
             {:refused_epoch_check,
              %{
                code: :watermark_not_found,
                detail:
                  "watermark.json for epoch #{epoch} exists but is not decodable — " <>
                    "a corrupt boundary refuses the run instead of faking one"
              }}}
        end
    end
  end

  defp git_ground!(base_dir) do
    case System.cmd("git", ["rev-parse", "--is-inside-work-tree"],
           cd: base_dir,
           stderr_to_stdout: true
         ) do
      {"true" <> _, 0} ->
        :ok

      {_, _} ->
        {:error,
         {:refused_epoch_check,
          %{
            code: :not_a_git_work_tree,
            detail:
              "#{base_dir} is not a git work tree; authorship and legacy blob " <>
                "ground truth cannot be established there"
          }}}
    end
  end

  defp threshold(opts, watermark) do
    Keyword.get_lazy(opts, :threshold, fn ->
      case watermark["similarity_threshold"] do
        value when is_binary(value) ->
          case Float.parse(value) do
            {f, _} -> f
            :error -> @default_threshold
          end

        %Decimal{} = value ->
          Decimal.to_float(value)

        value when is_float(value) ->
          value

        _ ->
          @default_threshold
      end
    end)
  end

  defp context(base_dir, watermark, now, threshold) do
    {receipts, unparsable} = load_receipts(base_dir)

    %{
      base_dir: base_dir,
      now: now,
      threshold: threshold,
      watermark_instant: parse_instant(watermark["watermark_instant"]),
      glob: watermark["implementation_glob"] || EpochWatermark.default_glob(),
      legacy_by_path: legacy_by_path(watermark),
      legacy_blobs: legacy_blobs(watermark),
      receipts: receipts,
      unparsable: unparsable,
      manifest_hashes: manifest_hashes(base_dir),
      residue: residue_rows(base_dir, parse_instant(watermark["watermark_instant"]))
    }
  end

  # -- per-file judgment ------------------------------------------------------

  defp judge(rel_path, cache, ctx) do
    authorship = authorship_newest(ctx.base_dir, rel_path)

    case File.read(Path.join(ctx.base_dir, rel_path)) do
      {:ok, content} ->
        blob = EpochWatermark.blob_sha(content)
        {report, cache} = judge_content(rel_path, content, blob, authorship, cache, ctx)
        {report, cache}

      {:error, reason} ->
        {%{
           "path" => rel_path,
           "blob_sha" => nil,
           "provenance_kind" => "none",
           "manufacture_receipt" => nil,
           "source_inputs" => ["unreadable: #{inspect(reason)}"],
           "closest_pre_epoch_match" => nil,
           "similarity" => nil,
           "authorship_newest" => authorship,
           "verdict" => :UNKNOWN_PROVENANCE
         }, cache}
    end
  end

  # The precedence IS the law: receipts (1) admit before similarity is ever
  # consulted as a falsifier (2, 3); path identity and blob identity decide
  # before fuzzy similarity does; only-existence of pre-epoch receipts and
  # bare lack of provenance come last.
  defp judge_content(rel_path, content, blob, authorship, cache, ctx) do
    {similarity, closest, cache} = closest_legacy(content, cache, ctx)
    sim = similarity || 0.0

    cond do
      receipt = generated_by_post_watermark_receipt(rel_path, ctx) ->
        verdict =
          if mutated?(rel_path, receipt, blob, content, ctx),
            do: :REFUSED_GENERATED_ARTIFACT_MUTATED,
            else: :ALIVE_GENERATED

        {file_report(
           rel_path,
           blob,
           "generated",
           receipt_id(receipt),
           similarity,
           closest,
           authorship,
           verdict
         ), cache}

      date = residue_date(rel_path, ctx) ->
        verdict =
          if sim >= ctx.threshold, do: :REFUSED_UNEXPLAINED_SIMILARITY, else: :ALIVE_FRESH_RESIDUE

        {file_report(
           rel_path,
           blob,
           "residue",
           Date.to_iso8601(date),
           similarity,
           closest,
           authorship,
           verdict
         ), cache}

      Map.has_key?(ctx.legacy_by_path, rel_path) ->
        {file_report(
           rel_path,
           blob,
           "none",
           nil,
           similarity,
           rel_path,
           authorship,
           :REFUSED_LEGACY_EDIT
         ), cache}

      match_path = exact_legacy_blob(blob, ctx) ->
        {file_report(
           rel_path,
           blob,
           "none",
           nil,
           1.0,
           match_path,
           authorship,
           :REFUSED_COPY_READD
         ), cache}

      sim >= ctx.threshold ->
        {file_report(
           rel_path,
           blob,
           "none",
           nil,
           similarity,
           closest,
           authorship,
           :REFUSED_UNEXPLAINED_SIMILARITY
         ), cache}

      any_receipt?(rel_path, ctx) ->
        {file_report(
           rel_path,
           blob,
           "none",
           nil,
           similarity,
           closest,
           authorship,
           :REFUSED_PRE_EPOCH_RECEIPT
         ), cache}

      true ->
        {file_report(
           rel_path,
           blob,
           "none",
           nil,
           similarity,
           closest,
           authorship,
           :REFUSED_NO_ATTRIBUTION
         ), cache}
    end
  end

  defp file_report(path, blob, kind, receipt, similarity, closest, authorship, verdict) do
    %{
      "path" => path,
      "blob_sha" => blob,
      "provenance_kind" => kind,
      "manufacture_receipt" => receipt,
      "source_inputs" => source_inputs(kind, receipt),
      "closest_pre_epoch_match" => closest,
      "similarity" => similarity,
      "authorship_newest" => authorship,
      "verdict" => verdict
    }
  end

  defp source_inputs("generated", receipt) when is_binary(receipt), do: ["receipt:" <> receipt]
  defp source_inputs("residue", date) when is_binary(date), do: ["handwritten-ledger@" <> date]
  defp source_inputs(_, _), do: []

  # -- attribution --------------------------------------------------------------

  defp generated_by_post_watermark_receipt(rel_path, ctx) do
    Enum.find(ctx.receipts, fn receipt ->
      lists_file?(receipt, rel_path) and post_watermark?(receipt, ctx.watermark_instant)
    end)
  end

  defp any_receipt?(rel_path, ctx) do
    Enum.any?(ctx.receipts, &lists_file?(&1, rel_path))
  end

  defp lists_file?(receipt, path) do
    path in file_paths(receipt)
  end

  defp file_paths(receipt) do
    (List.wrap(receipt["files"]) ++
       case receipt["outputs"] do
         outputs when is_list(outputs) -> Enum.map(outputs, &output_path/1)
         _ -> []
       end)
    |> Enum.reject(&is_nil/1)
  end

  defp output_path(p) when is_binary(p), do: p
  defp output_path(%{"path" => p}), do: p
  defp output_path(_), do: nil

  defp post_watermark?(receipt, watermark_instant) do
    alive_standing?(receipt["standing"]) and
      case parse_dt(receipt["finished_at"]) do
        {:ok, finished} -> DateTime.compare(finished, watermark_instant) in [:gt, :eq]
        :error -> false
      end
  end

  # Unparseable timestamps and non-alive standings never attribute — the
  # fail-closed direction: a receipt that cannot prove WHEN it ran cannot
  # prove it ran in this epoch.
  defp alive_standing?(standing) when standing in [:alive, "alive", "ALIVE"], do: true
  defp alive_standing?(_), do: false

  # Generated-artifact mutation: the receipt (or the manifest) recorded what
  # this file's bytes were when manufacture ran; current bytes disagreeing
  # with every recorded identity is the hand-edit signature.
  defp mutated?(rel_path, receipt, blob, content, ctx) do
    case recorded_hashes(rel_path, receipt, ctx) do
      [] -> false
      hashes -> not Enum.any?(hashes, &hash_matches?(&1, content, blob))
    end
  end

  # Receipt rows carry output identities either under the candidate's
  # repo-relative path, or — for the manifest — under its canonical absolute
  # identity (ArtifactIdentity.canonicalize/2's output), so both spellings
  # are consulted; a hash under any other path says nothing about this file.
  defp recorded_hashes(rel_path, receipt, ctx) do
    from_receipt =
      for entry <- List.wrap(receipt["outputs"]),
          is_map(entry),
          output_path(entry) == rel_path,
          hash = entry["hash"] || entry["sha"],
          is_binary(hash) do
        hash
      end

    from_manifest =
      Map.get(ctx.manifest_hashes, ArtifactIdentity.canonicalize(ctx.base_dir, rel_path), [])

    from_receipt ++ from_manifest
  end

  defp receipt_id(receipt), do: receipt["id"] || receipt["recipe_key"] || "unknown-receipt"

  # Manifest attribution reuses the manifest's OWN reader (load_safe/1) so
  # its schema-versioning law is honored here instead of re-parsed; a corrupt
  # manifest contributes no hashes rather than crashing the court.
  defp manifest_hashes(base_dir) do
    case GgenIgniter.Manifest.load_safe(base_dir) do
      {:ok, %{"entries" => entries}} when is_map(entries) ->
        Enum.reduce(entries, %{}, fn {_key, entry}, acc ->
          case entry && entry["outputs"] do
            outputs when is_map(outputs) ->
              Enum.reduce(outputs, acc, fn {path, hash}, acc ->
                Map.update(acc, path, List.wrap(hash), &[List.wrap(hash) | &1])
              end)

            _ ->
              acc
          end
        end)

      _ ->
        %{}
    end
  end

  # Recorded identities arrive in two schemes: 40-hex = git blob SHA, 64-hex
  # = content sha256. Compare in whichever scheme the recorded hash speaks;
  # anything else matches nothing (fail closed).
  defp hash_matches?(recorded, content, blob) do
    cond do
      recorded == blob ->
        true

      Regex.match?(~r/\A[0-9a-f]{64}\z/, recorded) ->
        recorded == Base.encode16(:crypto.hash(:sha256, content), case: :lower)

      true ->
        false
    end
  end

  defp load_receipts(base_dir) do
    dir = Path.join([base_dir, ".ggen_igniter", "receipts"])

    case File.ls(dir) do
      {:ok, files} ->
        files
        |> Enum.filter(&String.ends_with?(&1, ".jsonl"))
        |> Enum.flat_map(fn file ->
          dir |> Path.join(file) |> File.read!() |> String.split("\n", trim: true)
        end)
        |> Enum.map(&Jason.decode/1)
        |> Enum.map_reduce(0, fn
          {:ok, row}, n when is_map(row) -> {row, n}
          _, n -> {nil, n + 1}
        end)
        |> then(fn {rows, unparsable} -> {Enum.reject(rows, &is_nil/1), unparsable} end)

      {:error, _} ->
        {[], 0}
    end
  end

  defp residue_date(rel_path, ctx), do: Map.get(ctx.residue, rel_path)

  # Ledger row format (repo HANDWRITTEN.md convention):
  # `path | semantic element | missing capability | intended owner pack | date`
  # A row dated on/after the watermark instant's calendar date attributes the
  # path as fresh residue; earlier rows simply do not exist to this court.
  defp residue_rows(base_dir, watermark_instant) do
    file = Path.join(base_dir, "HANDWRITTEN.md")
    boundary_date = DateTime.to_date(watermark_instant)

    if File.exists?(file) do
      file
      |> File.read!()
      |> String.split("\n", trim: true)
      |> Enum.reduce(%{}, fn line, acc ->
        case residue_row(line) do
          {path, %Date{} = date} ->
            if Date.compare(date, boundary_date) in [:gt, :eq],
              do: Map.put(acc, path, date),
              else: acc

          nil ->
            acc
        end
      end)
    else
      %{}
    end
  end

  defp residue_row(line) do
    cells = line |> String.split("|") |> Enum.map(&String.trim/1)

    with [path | rest] when path != "" and rest != [] <- cells,
         {:ok, date} <- Date.from_iso8601(List.last(cells)) do
      {path, date}
    else
      _ -> nil
    end
  end

  # -- legacy tree --------------------------------------------------------------

  defp legacy_by_path(watermark) do
    Map.new(List.wrap(watermark["files"]), fn file -> {file["path"], file["blob_sha"]} end)
  end

  defp legacy_blobs(watermark) do
    Map.new(List.wrap(watermark["files"]), fn file -> {file["blob_sha"], file["path"]} end)
  end

  # Max similarity across the whole pre-epoch implementation tree — rename,
  # copy, split and move all surface here, not just same-path edits.
  defp closest_legacy(content, cache, ctx) do
    if ctx.legacy_by_path == %{} do
      {nil, nil, cache}
    else
      content_size = byte_size(content)

      Enum.reduce(ctx.legacy_by_path, {nil, nil, cache}, fn {path, blob}, acc ->
        {best_s, _best_p, cache} = acc
        {legacy_content, cache} = legacy_content(blob, cache, ctx)

        score =
          if is_binary(legacy_content) and within_band?(content_size, byte_size(legacy_content)) do
            similarity(content, legacy_content)
          else
            0.0
          end

        if score > (best_s || 0.0) do
          {score, path, cache}
        else
          {best_s, elem(acc, 1), cache}
        end
      end)
    end
  end

  # A ≥0.9 Jaccard cannot survive a 4x size difference in either direction;
  # skipping those comparisons is an optimization with a stated direction,
  # not a semantic filter.
  defp within_band?(a, b), do: a <= @size_band * b and b <= @size_band * a

  defp exact_legacy_blob(blob, ctx), do: Map.get(ctx.legacy_blobs, blob)

  defp legacy_content(blob, cache, ctx) do
    case Map.fetch(cache, blob) do
      {:ok, content} ->
        {content, cache}

      :error ->
        content =
          case System.cmd("git", ["cat-file", "blob", blob],
                 cd: ctx.base_dir,
                 stderr_to_stdout: true
               ) do
            {out, 0} -> out
            {_, _} -> nil
          end

        {content, Map.put(cache, blob, content)}
    end
  end

  # -- tree plumbing -------------------------------------------------------------

  defp list_candidates(ctx) do
    root = Path.expand(ctx.base_dir)

    root
    |> then(&Path.wildcard(Path.join(&1, ctx.glob)))
    |> Enum.map(&Path.relative_to(&1, root))
    |> Enum.sort()
  end

  defp inside_base?(base_dir, rel_path) do
    abs = Path.expand(rel_path, Path.expand(base_dir))
    root = Path.expand(base_dir)
    abs == root or String.starts_with?(abs, root <> "/")
  end

  defp subject_tree(files) do
    files
    |> Enum.map(fn f -> "#{f["path"]} #{f["blob_sha"]}" end)
    |> Enum.sort()
    |> Enum.join("\n")
    |> then(&:crypto.hash(:sha256, &1))
    |> Base.encode16(case: :lower)
  end

  defp counts(files) do
    %{
      "total" => length(files),
      "admitted_generated" => Enum.count(files, &(&1["verdict"] == :ALIVE_GENERATED)),
      "admitted_residue" => Enum.count(files, &(&1["verdict"] == :ALIVE_FRESH_RESIDUE)),
      "refused" => Enum.count(files, &(not alive?(&1["verdict"])))
    }
  end

  defp standing(files) do
    if Enum.all?(files, &alive?(&1["verdict"])), do: :ALIVE, else: :REFUSED
  end

  # Informing column only — it never decides a verdict (delete-and-re-add
  # launders blame, which is why identity and receipts decide).
  defp authorship_newest(base_dir, rel_path) do
    case System.cmd("git", ["log", "--follow", "--format=%aI", "-n", "1", "--", rel_path],
           cd: base_dir,
           stderr_to_stdout: true
         ) do
      {out, 0} ->
        case String.trim(out) do
          "" -> nil
          instant -> instant
        end

      {_, _} ->
        nil
    end
  end

  defp write_report!(path, report) do
    File.mkdir_p!(Path.dirname(path))
    temp = path <> ".tmp-#{:erlang.unique_integer([:positive])}"
    File.write!(temp, Jason.encode!(report, pretty: true) <> "\n")
    File.rename!(temp, path)
  end

  defp parse_instant(instant) when is_binary(instant) do
    case DateTime.from_iso8601(instant) do
      {:ok, dt, _} -> dt
      _ -> DateTime.from_unix!(0)
    end
  end

  defp parse_instant(_), do: DateTime.from_unix!(0)

  defp parse_dt(nil), do: :error

  defp parse_dt(text) when is_binary(text) do
    case DateTime.from_iso8601(text) do
      {:ok, dt, _} -> {:ok, dt}
      _ -> :error
    end
  end

  defp parse_dt(_), do: :error

  # -- explain ----------------------------------------------------------------

  defp law(%{"verdict" => v} = report) do
    case v do
      :ALIVE_GENERATED ->
        "ALIVE: receipt #{inspect(report["manufacture_receipt"])} attributes this file to " <>
          "post-watermark manufacture."

      :ALIVE_FRESH_RESIDUE ->
        "ALIVE: HANDWRITTEN.md ledger row dated on/after the watermark, and the content " <>
          "does not resemble any pre-epoch implementation file."

      :REFUSED_GENERATED_ARTIFACT_MUTATED ->
        "Restore the exact bytes the receipt recorded, or re-run the generator so a fresh " <>
          "receipt commits to the current bytes. Editing a generated artifact after its " <>
          "receipt is the smuggling path this court exists for."

      :REFUSED_LEGACY_EDIT ->
        "This path is the pre-epoch implementation. Delete it and let ggen_igniter " <>
          "manufacture the replacement (a receipt then admits it), or author genuinely " <>
          "new implementation with a HANDWRITTEN.md row dated >= the watermark."

      :REFUSED_COPY_READD ->
        "Byte-identical to pre-epoch file " <>
          inspect(report["closest_pre_epoch_match"]) <>
          " at a different path. Deleting and re-adding does not change blob identity."

      :REFUSED_UNEXPLAINED_SIMILARITY ->
        "Content resembles pre-epoch implementation" <>
          closest_clause(report) <>
          " beyond the threshold with no manufacture receipt behind it. Regenerate via " <>
          "ggen_igniter (the receipt explains the similarity) or write genuinely new code."

      :REFUSED_PRE_EPOCH_RECEIPT ->
        "The only receipts naming this file predate the watermark. Re-run the manufacture " <>
          "step in this epoch so a post-watermark receipt exists."

      :REFUSED_NO_ATTRIBUTION ->
        "No post-watermark receipt, no residue ledger row. Every implementation file needs " <>
          "provenance: a ggen receipt, or a HANDWRITTEN.md row dated >= the watermark."

      :UNKNOWN_PROVENANCE ->
        "The file could not be judged (see source_inputs). Repair the filesystem condition " <>
          "and re-run; UNKNOWN counts as refused."
    end
  end

  defp closest_clause(%{"closest_pre_epoch_match" => nil}), do: ""
  defp closest_clause(%{"closest_pre_epoch_match" => p}), do: " (" <> inspect(p) <> ")"

  # -- similarity ----------------------------------------------------------------

  defp ast_jaccard(a, b) do
    case {ast_features(a), ast_features(b)} do
      {fa, fb} when map_size(fa) == 0 and map_size(fb) == 0 -> 0.0
      {fa, fb} -> jaccard(fa, fb)
    end
  end

  # AST features: every call as {name, arity} (remote calls fold the alias
  # tail into the name: "Repo.all/1"), plus every literal atom. Macros and
  # special forms are calls too — the feature set is deliberately uniform.
  defp ast_features(source) do
    with {:ok, ast} <- Code.string_to_quoted(source) do
      {_, features} =
        Macro.prewalk(ast, MapSet.new(), fn
          {{:., _, [target, fun]}, _, args} = node, acc
          when is_atom(fun) and is_list(args) ->
            {node, MapSet.put(acc, {remote_name(target, fun), length(args)})}

          {fun, _, args} = node, acc when is_atom(fun) and is_list(args) ->
            {node, MapSet.put(acc, {fun, length(args)})}

          node, acc when is_atom(node) ->
            {node, MapSet.put(acc, node)}

          node, acc ->
            {node, acc}
        end)

      features
    else
      _ -> MapSet.new()
    end
  end

  # Alias segments are not always atoms: `__MODULE__.Sub` parses as an
  # aliases node whose segment list contains the raw `__MODULE__` tuple
  # (witnessed: real-tree check crashed joining it), so every segment is
  # flattened through alias_segment/1 before the join.
  defp remote_name({:__aliases__, _, mods}, fun),
    do: Enum.map_join(mods ++ [fun], ".", &alias_segment/1)

  defp remote_name(target, fun) when is_atom(target), do: "#{target}.#{fun}"
  defp remote_name(target, fun), do: alias_segment(target) <> "." <> Atom.to_string(fun)

  defp alias_segment({:__MODULE__, _, _}), do: "__MODULE__"
  defp alias_segment({:__aliases__, _, mods}), do: Enum.map_join(mods, ".", &alias_segment/1)
  defp alias_segment(atom) when is_atom(atom), do: Atom.to_string(atom)
  defp alias_segment(other), do: inspect(other)

  # Token features: comment-stripped (line-level, naive about "#" inside
  # strings — stated limit), whitespace-collapsed non-blank lines.
  defp token_jaccard(a, b) do
    {ta, tb} = {token_features(a), token_features(b)}

    if MapSet.size(ta) == 0 and MapSet.size(tb) == 0 do
      0.0
    else
      jaccard(ta, tb)
    end
  end

  defp token_features(source) do
    source
    |> String.split("\n")
    |> Enum.map(&strip_comment/1)
    |> Enum.map(&(&1 |> String.replace(~r/\s+/, " ") |> String.trim()))
    |> Enum.reject(&(&1 == ""))
    |> MapSet.new()
  end

  defp strip_comment(line) do
    case String.split(line, "#", parts: 2) do
      [code, _comment] -> code
      [code] -> code
    end
  end

  defp jaccard(sa, sb) do
    intersection = MapSet.intersection(sa, sb) |> MapSet.size()
    union = MapSet.union(sa, sb) |> MapSet.size()

    if union == 0, do: 0.0, else: intersection / union
  end
end
