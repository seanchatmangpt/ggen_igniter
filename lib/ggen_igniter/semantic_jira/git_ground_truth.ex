defmodule GgenIgniter.SemanticJira.GitGroundTruth do
  @moduledoc """
  Opt-in git ground truth for WorkOrder `baseSha` values.

  Closes the witnessed admission residual `residual_base_sha_wrong_commit`
  (wave-1 falsifier matrix, commit 58460d0): admission verifies `baseSha` as
  an exact 40-hex FORMAT only, so a well-formed but WRONG commit SHA is
  admitted, because admission has no git ground truth in-graph.

  Verification is deliberately OPT-IN at two independent levels, because the
  canonical graph's own fabric WorkOrders (GALL-001..032) carry baseSha
  values that are not guaranteed to exist in any particular consumer
  checkout -- default-on verification would break the existing manufacture
  set:

    * run level: `mix ggen_igniter.sync --verify-base-sha` verifies the
      baseSha of EVERY WorkOrder row this run rendered;
    * order level: an in-graph `sj:requiresGitGroundTruth true` triple on an
      individual WorkOrder verifies that order's baseSha even without the
      run-level flag -- the graph author opted that one order in.

  With neither opt-in active, behavior is byte-for-byte unchanged (the
  no-regression contract: the GALL set still manufactures).

  For each targeted baseSha, two real git commands must BOTH exit 0 against
  the verification work tree (`--verify-cwd DIR`, defaulting to the current
  working directory):

      git -C <cwd> cat-file -e <sha>^{commit}
      git -C <cwd> merge-base --is-ancestor <sha> HEAD

  i.e. the SHA must name a real commit object that is reachable from HEAD.
  Any nonzero exit, or a `--verify-cwd` that is not a git work tree, raises
  the typed refusal `REFUSED:SEMANTIC_JIRA_BASE_SHA_UNVERIFIED` BEFORE any
  actuation happens: the sync task calls this module after the named queries
  return and before the Reactor dispatch, so a refusal writes zero files.
  """

  @refusal "REFUSED:SEMANTIC_JIRA_BASE_SHA_UNVERIFIED"

  # The `020_work_orders.rq` gate exposes this OPTIONAL column; a truthy
  # value opts that single WorkOrder into git verification.
  @opt_in_column "requires_git_ground_truth"

  # Same format law the admission kernel already enforces; repeated here so
  # git never receives a non-SHA scalar (e.g. a branch name) as a revision.
  @sha ~r/\A[0-9a-f]{40}\z/

  @doc "The typed refusal prefix every refusal from this module carries."
  @spec refusal_prefix() :: String.t()
  def refusal_prefix, do: @refusal

  @doc """
  Verifies the targeted WorkOrder baseSha values against a real git work tree.

  `named_results` is the sync task's `[{query_name, rows}]` list; every row
  carrying a `base_sha` column is a WorkOrder row. `opts`:

    * `:verify_cwd` (required) -- the directory whose git history is ground
      truth. Must be a real git work tree whenever anything needs verifying.
    * `:all` -- when true, verify EVERY row's baseSha (the `--verify-base-sha`
      flag); when false (default), verify only rows that opted themselves in
      via the `#{@opt_in_column}` column.

  Raises `ArgumentError` with the `#{@refusal}` prefix on the first failure;
  returns `:ok` when every targeted baseSha is a commit reachable from HEAD
  (including the vacuous case: nothing targeted).
  """
  @spec verify_base_shas!([{String.t(), [map()]}], keyword()) :: :ok
  def verify_base_shas!(named_results, opts) when is_list(named_results) do
    cwd = Keyword.fetch!(opts, :verify_cwd)
    rows = Enum.flat_map(named_results, fn {_name, rows} -> rows end)

    jurisdiction = repository_jurisdiction(cwd)

    targeted_shas =
      if Keyword.get(opts, :all, false) do
        rows
      else
        Enum.filter(rows, &git_ground_truth_declared?/1)
      end
      |> Enum.filter(&in_jurisdiction?(&1, jurisdiction))
      |> base_shas()

    case Enum.uniq(targeted_shas) do
      [] ->
        :ok

      shas ->
        refuse_unless_git_work_tree!(cwd)
        Enum.each(shas, &verify_sha!(&1, cwd))
    end
  end

  # The verifier's jurisdiction is the verified work tree's OWN repository
  # (v26.9.22 union law): the crown rows bind `local/eds`, so their baseSha
  # values are commits of another history — outside this check, never a
  # refusal here and never silently "verified". Rows without a repository
  # column, and work trees without an origin remote, keep the old
  # verify-everything behavior.
  defp in_jurisdiction?(_row, %{origin_url: nil}), do: true

  defp in_jurisdiction?(row, %{origin_url: url}) when is_map(row) do
    case row["repository"] do
      repo when is_binary(repo) -> String.contains?(url, repo)
      _ -> true
    end
  end

  defp repository_jurisdiction(cwd) do
    case git(cwd, ["config", "--get", "remote.origin.url"]) do
      {url, 0} -> %{origin_url: String.trim(url)}
      _ -> %{origin_url: nil}
    end
  end

  defp verify_sha!(sha, cwd) do
    unless Regex.match?(@sha, sha) do
      # The 40-hex format law belongs to the admission kernel and templates;
      # a row that reaches git verification without it is reported through
      # the same typed refusal rather than silently skipped or passed to git
      # as a revision.
      raise ArgumentError, unverified_message(sha, cwd)
    end

    if git_ok?(cwd, ["cat-file", "-e", "#{sha}^{commit}"]) and
         git_ok?(cwd, ["merge-base", "--is-ancestor", sha, "HEAD"]) do
      :ok
    else
      raise ArgumentError, unverified_message(sha, cwd)
    end
  end

  defp unverified_message(sha, cwd) do
    "#{@refusal}: baseSha #{sha} is not a commit reachable in #{cwd}"
  end

  defp refuse_unless_git_work_tree!(cwd) do
    inside? =
      case git(cwd, ["rev-parse", "--is-inside-work-tree"]) do
        {"true" <> _rest, 0} -> true
        _ -> false
      end

    unless inside? do
      raise ArgumentError,
            "#{@refusal}: --verify-cwd #{cwd} is not a git work tree; git ground " <>
              "truth for baseSha cannot be established there"
    end
  end

  # Explicit exit handling on every git invocation: exit 0 is the only
  # success signal; any other exit (1 = not an ancestor, 128 = unknown
  # revision, etc.) is a refusal, never a crash and never a pass.
  defp git_ok?(cwd, args) do
    case git(cwd, args) do
      {_, 0} -> true
      {_, _nonzero} -> false
    end
  end

  defp git(cwd, args) do
    case File.dir?(cwd) do
      true ->
        System.cmd("git", args, cd: cwd, stderr_to_stdout: true)

      false ->
        raise ArgumentError,
              "#{@refusal}: --verify-cwd #{cwd} is not a git work tree; git ground " <>
                "truth for baseSha cannot be established there"
    end
  end

  defp base_shas(rows) do
    for row <- rows, base_sha = row["base_sha"], is_binary(base_sha) do
      literal_value(base_sha)
    end
  end

  defp git_ground_truth_declared?(row) do
    case Map.get(row, @opt_in_column) do
      value when is_binary(value) -> literal_value(value) == "true"
      true -> true
      _other -> false
    end
  end

  # Query rows arrive engine-shaped: the `sparql` engine yields bare values
  # while `oxigraph` yields N-Triples-style terms (quoted, optionally with a
  # `^^<datatype>` or language-tag suffix). Normalize to the bare lexical
  # form so the opt-in predicate and the verification itself behave
  # identically under every engine.
  defp literal_value(value) do
    case Regex.run(~r/\A"(.*)"(?:\^\^<[^>]*>)?(?:@[A-Za-z-]+)?\z/s, value) do
      [_all, inner] -> inner
      _no_match -> value
    end
  end
end
