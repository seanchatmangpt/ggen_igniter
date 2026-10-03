defmodule GgenIgniter.EpochWatermark do
  @moduledoc """
  Records the implementation-plane identity at a CalVer epoch boundary:
  which implementation files existed, as exactly which git blob SHAs, when
  the epoch closed.

  ## Why identity, not blame

  The epoch law ("implementation authored before the watermark is legacy
  evidence, not future implementation") must be checkable against a
  candidate tree WITHOUT trusting git chronology: `git blame` attributes a
  delete-and-re-added file to the re-adding commit, so an agent can launder
  legacy code through a re-commit and every blame-based gate reads it as
  fresh. This module therefore records the pre-epoch state as an identity
  manifest — `path` + `blob_sha` pairs stamped at one `head_sha`/`tree_sha`
  — and `GgenIgniter.EpochFreshness` asks the candidate tree against those
  exact identities, with content similarity as the falsifier for renames,
  copies and re-adds that change the path.

  The manifest is an identity stamp, not a cache: re-stamping the same epoch
  over a different tree would silently redefine what "legacy" means for
  that epoch, so a second `stamp!/3` over a changed tree is refused unless
  the caller passes `restamp: %{reason: ...}` — and the reason is recorded
  in the manifest itself.

  ## Honest limits

  The manifest records TRACKED files only (`git ls-files -s`): an
  untracked-but-present pre-epoch file is invisible to the stamp, and the
  freshness court will see it as a brand-new file. Commit everything that
  should count as legacy before stamping. Blob contents are not copied into
  the manifest; the court reads them back with `git cat-file`, so rewriting
  repository history after stamping (beyond reflog reachability) can break
  the similarity falsifier — the manifest's SHAs remain authoritative
  either way.
  """

  @schema_version "1"
  @default_glob "lib/**/*.ex"

  @typedoc "Decoded watermark.json — string keys, Jason's default map shape."
  @type manifest :: %{String.t() => term()}

  @type refusal ::
          {:refused_epoch_watermark,
           %{
             code: :not_a_git_work_tree | :restamp_required | :empty_implementation_set,
             detail: String.t()
           }}

  @doc "The watermark's on-disk path: `<base_dir>/.ggen_igniter/epoch/<epoch>/watermark.json`."
  @spec path(String.t(), String.t()) :: String.t()
  def path(base_dir, epoch),
    do: Path.join([base_dir, ".ggen_igniter", "epoch", epoch, "watermark.json"])

  @doc "The implementation-plane glob stamped when `stamp!/3` is not given a `:glob`."
  @spec default_glob() :: String.t()
  def default_glob, do: @default_glob

  @doc """
  Loads a previously stamped manifest. `{:error, :not_found}` when no
  watermark exists for the epoch; `{:error, :corrupt}` when the file exists
  but is not decodable JSON — a corrupt stamp is never reported as absence,
  because "no watermark" and "unreadable watermark" demand different
  repairs.
  """
  @spec load(String.t(), String.t()) :: {:ok, manifest()} | {:error, :not_found | :corrupt}
  def load(base_dir, epoch) do
    file = path(base_dir, epoch)

    if File.exists?(file) do
      case Jason.decode(File.read!(file)) do
        {:ok, decoded} -> {:ok, decoded}
        {:error, _} -> {:error, :corrupt}
      end
    else
      {:error, :not_found}
    end
  end

  @doc """
  Stamps the pre-epoch implementation identity for `epoch`.

  Options:

    * `:glob` — implementation-plane glob (default `#{@default_glob}`)
    * `:restamp` — `false` (default) or `%{reason: binary}`, required to
      overwrite an existing stamp whose head/tree/files differ
    * `:now` — `DateTime.t()` for the watermark instant (default now)

  Re-stamping an UNCHANGED tree is idempotent: `{:ok, manifest, path}` with
  the same identities. Re-stamping a CHANGED tree without `:restamp` is
  `{:error, {:refused_epoch_watermark, %{code: :restamp_required}}}`.
  """
  @spec stamp!(String.t(), String.t(), keyword()) ::
          {:ok, manifest(), String.t()} | {:error, refusal()}
  def stamp!(base_dir, epoch, opts \\ []) do
    glob = Keyword.get(opts, :glob, @default_glob)
    now = Keyword.get(opts, :now, DateTime.utc_now())
    restamp = Keyword.get(opts, :restamp, false)

    with :ok <- inside_work_tree!(base_dir),
         {:ok, head_sha} <- git_rev(base_dir, ["rev-parse", "HEAD"]),
         {:ok, tree_sha} <- git_rev(base_dir, ["rev-parse", "HEAD^{tree}"]),
         {:ok, files} <- implementation_files(base_dir, glob) do
      identity = %{"head_sha" => head_sha, "tree_sha" => tree_sha, "files" => files}
      file = path(base_dir, epoch)

      ctx = %{
        base_dir: base_dir,
        epoch: epoch,
        identity: identity,
        glob: glob,
        now: now,
        file: file,
        restamp: restamp
      }

      resolve_stamp(read_existing(file), ctx)
    end
  end

  defp read_existing(file) do
    if File.exists?(file) do
      case Jason.decode(File.read!(file)) do
        {:ok, decoded} when is_map(decoded) -> decoded
        {:error, _} -> :corrupt
      end
    else
      nil
    end
  end

  defp resolve_stamp(nil, ctx), do: write_fresh(ctx, nil)

  defp resolve_stamp(:corrupt, ctx) do
    {:error,
     {:refused_epoch_watermark,
      %{
        code: :restamp_required,
        detail:
          "existing watermark.json for epoch #{ctx.epoch} is not decodable JSON; " <>
            "repair or restamp with a reason"
      }}}
  end

  defp resolve_stamp(decoded, ctx) do
    if identity_matches?(decoded, ctx.identity) do
      {:ok, Map.merge(decoded, ctx.identity), ctx.file}
    else
      case ctx.restamp do
        %{reason: reason} when is_binary(reason) ->
          write_fresh(ctx, reason)

        _ ->
          {:error,
           {:refused_epoch_watermark,
            %{
              code: :restamp_required,
              detail:
                "epoch #{ctx.epoch} already stamped at a different tree; pass " <>
                  "restamp: %{reason: ...} to redefine the epoch boundary"
            }}}
      end
    end
  end

  defp write_fresh(ctx, reason) do
    write_stamp!(ctx.base_dir, ctx.epoch, ctx.identity, ctx.glob, ctx.now, reason)
  end

  # Identity = the pre-epoch tree, not the stamp's wall clock: two stamps of
  # the same tree are the same boundary regardless of `now`, so only
  # head/tree/files decide idempotency.
  defp identity_matches?(decoded, identity) do
    is_binary(decoded["head_sha"]) and
      decoded["head_sha"] == identity["head_sha"] and
      decoded["tree_sha"] == identity["tree_sha"] and
      decoded["files"] == identity["files"]
  end

  @doc """
  The git blob SHA of `content` — the exact object id git itself would
  store, computed without invoking git so the freshness court can hash
  untracked candidate files with the same identity scheme the stamp used.
  """
  @spec blob_sha(binary()) :: String.t()
  def blob_sha(content) when is_binary(content) do
    :crypto.hash(
      :sha,
      <<"blob ", Integer.to_string(byte_size(content))::binary, 0, content::binary>>
    )
    |> Base.encode16(case: :lower)
  end

  defp write_stamp!(base_dir, epoch, identity, glob, now, restamp_reason) do
    manifest =
      identity
      |> Map.merge(%{
        "schema_version" => @schema_version,
        "epoch" => epoch,
        "watermark_instant" => DateTime.to_iso8601(now),
        "implementation_glob" => glob
      })
      |> maybe_put_reason(restamp_reason)

    file = path(base_dir, epoch)
    File.mkdir_p!(Path.dirname(file))

    temp = file <> ".tmp-#{:erlang.unique_integer([:positive])}"
    File.write!(temp, Jason.encode!(manifest, pretty: true) <> "\n")
    File.rename!(temp, file)

    {:ok, manifest, file}
  end

  defp maybe_put_reason(manifest, nil), do: manifest
  defp maybe_put_reason(manifest, reason), do: Map.put(manifest, "restamp_reason", reason)

  # `:(glob)` pathspec magic makes `**` behave like Path.wildcard's — without
  # it, git's default pathspec `*` also matches `/` and the two glob dialects
  # silently disagree about which files the implementation plane covers.
  defp implementation_files(base_dir, glob) do
    case git(base_dir, ["ls-files", "-s", "--", ":(glob)" <> glob]) do
      {output, 0} ->
        files =
          output
          |> String.split("\n", trim: true)
          |> Enum.map(&parse_ls_files_row/1)
          |> Enum.reject(&is_nil/1)
          |> Enum.sort_by(& &1["path"])

        if files == [] do
          {:error,
           {:refused_epoch_watermark,
            %{
              code: :empty_implementation_set,
              detail:
                "glob #{inspect(glob)} matches no tracked files; an epoch stamp over " <>
                  "nothing is not a boundary"
            }}}
        else
          {:ok, files}
        end

      {output, code} ->
        {:error,
         {:refused_epoch_watermark,
          %{
            code: :not_a_git_work_tree,
            detail: "git ls-files exited #{code} in #{base_dir}: #{String.trim(output)}"
          }}}
    end
  end

  # `<mode> <oid> <stage>\t<path>` — stage 0 only; a nonzero stage is an
  # unresolved merge conflict, and stamping a conflicted blob identity as an
  # epoch boundary would record a state that never existed as one branch.
  defp parse_ls_files_row(row) do
    case String.split(row, "\t", parts: 2) do
      [meta, path] ->
        case String.split(meta, " ") do
          [_mode, oid, "0"] -> %{"path" => path, "blob_sha" => oid}
          _ -> nil
        end

      _ ->
        nil
    end
  end

  defp inside_work_tree!(base_dir) do
    case git(base_dir, ["rev-parse", "--is-inside-work-tree"]) do
      {"true" <> _, 0} ->
        :ok

      {_, _} ->
        {:error,
         {:refused_epoch_watermark,
          %{
            code: :not_a_git_work_tree,
            detail:
              "#{base_dir} is not inside a git work tree; an epoch boundary needs " <>
                "committed blob identities to stamp"
          }}}
    end
  end

  defp git_rev(base_dir, args) do
    case git(base_dir, args) do
      {output, 0} ->
        rev = String.trim(output)

        if Regex.match?(~r/\A[0-9a-f]{40}\z/, rev) do
          {:ok, rev}
        else
          {:error,
           {:refused_epoch_watermark,
            %{
              code: :not_a_git_work_tree,
              detail: "git #{Enum.join(args, " ")} returned #{inspect(rev)}"
            }}}
        end

      {output, code} ->
        {:error,
         {:refused_epoch_watermark,
          %{
            code: :not_a_git_work_tree,
            detail: "git #{Enum.join(args, " ")} exited #{code}: #{String.trim(output)}"
          }}}
    end
  end

  # Same discipline as SemanticJira.GitGroundTruth: exit 0 is the only
  # success signal; every nonzero exit is a typed refusal, never a crash
  # and never a pass.
  defp git(base_dir, args) do
    System.cmd("git", args, cd: base_dir, stderr_to_stdout: true)
  end
end
