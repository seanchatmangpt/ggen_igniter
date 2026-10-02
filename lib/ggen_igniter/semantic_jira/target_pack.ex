defmodule GgenIgniter.SemanticJira.TargetPack do
  @moduledoc """
  Sync-time WORLD enforcement for WorkOrder `sj:targetPack` names.

  The FORMAT/WORLD law split (the `sj:baseSha` precedent):
  `GgenIgniter.SemanticJira.admit_work_order/1` verifies a target pack as a
  FORMAT only (`@pack_name` regex, `{:error, {:invalid_target_pack, v}}`);
  this module owns the WORLD half at sync time:

    * `enforce!/2` walks the sync task's named query rows (the same
      `[{query_name, rows}]` shape `GgenIgniter.SemanticJira.GitGroundTruth.
      verify_base_shas!/2` walks), collects every distinct non-nil
      `target_pack` column value, and for each one resolves the real pack
      directory via `GgenIgniter.Pack.resolve_dir!/1` (`[pack: name]`),
      refuses a nonexistent pack (resolve_dir! returns nonexistent
      cwd-relative dirs unchanged), and stamps the pack's content identity
      via `GgenIgniter.PackLock.digest_checked/1`.
    * An unknown pack raises `ArgumentError` with the typed refusal prefix
      `REFUSED:TARGET_PACK_UNKNOWN pack="<name>" work_order="<id>"` BEFORE
      the Reactor dispatch, so a refusal writes zero files.
    * A digest failure (symlink escape, unreadable file) re-raises with the
      existing `GgenIgniter.PackLock` prefixes
      (`REFUSED:PACK_SYMLINK_ESCAPE` / `REFUSED:PACK_FILE_UNREADABLE`).

  Like `GitGroundTruth`, the two helpers in `Mix.Tasks.GgenIgniter.Sync`
  (`maybe_enforce_target_packs!/2`, beside both `maybe_verify_base_shas!`
  call sites) are only the task-level plumbing; a run with no
  `target_pack` on any row is a no-op returning the vacuous `%{}`.
  """

  alias GgenIgniter.{Pack, PackLock}

  @refusal "REFUSED:TARGET_PACK_UNKNOWN"

  @doc "The typed refusal prefix every unknown-pack refusal from this module carries."
  @spec refusal_prefix() :: String.t()
  def refusal_prefix, do: @refusal

  @doc """
  Enforces every distinct non-nil `target_pack` across `named_results`
  (the sync task's `[{query_name, rows}]` list) and returns the stamp
  `%{pack_name => pack_digest}`.

  Raises `ArgumentError` with the `#{@refusal}` prefix on the first
  unknown pack (named by the first row that carried it), and re-raises
  `GgenIgniter.PackLock`'s own typed prefixes on digest failure. The
  vacuous no-op -- no row carries a target pack -- returns `%{}` without
  touching the filesystem.
  """
  @spec enforce!([{String.t(), [map()]}], keyword()) :: %{String.t() => String.t()}
  def enforce!(named_results, opts \\ []) when is_list(named_results) do
    rows = Enum.flat_map(named_results, fn {_name, rows} -> rows end)

    rows
    |> Enum.filter(&target_pack_declared?/1)
    |> Map.new(&{&1["target_pack"], &1["id"]})
    |> Enum.map(fn {pack, work_order} -> {pack, resolve_and_digest!(pack, work_order, opts)} end)
    |> Map.new()
  end

  # FORMAT was already verified at admission; here the name must name a real
  # pack directory whose content digests cleanly.
  defp resolve_and_digest!(pack, work_order, _opts) do
    dir = Pack.resolve_dir!(pack: pack)

    unless File.dir?(dir) do
      raise ArgumentError,
            "#{@refusal} pack=#{inspect(pack)} work_order=#{inspect(work_order)}"
    end

    case PackLock.digest_checked(dir) do
      {:ok, digest} -> digest
      # Re-raise under PackLock's own typed prefixes: the pack EXISTS, its
      # content is what failed the lock walk.
      {:error, reason} -> raise ArgumentError, PackLock.refusal_text(reason)
    end
  end

  defp target_pack_declared?(row),
    do: is_binary(row["target_pack"]) and row["target_pack"] != ""
end
