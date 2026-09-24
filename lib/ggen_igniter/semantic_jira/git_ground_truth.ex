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
  Only rows inside the work tree's own repository (the exact `owner/repo` of
  its `remote.origin.url`) are verified; a row naming another repository is a
  typed skip in the returned report under the run-level flag, and a refusal
  when the row opted itself in (see `verify_base_shas!/2`).
  Any nonzero exit, or a `--verify-cwd` that is not a git work tree, raises
  the typed refusal `REFUSED:SEMANTIC_JIRA_BASE_SHA_UNVERIFIED` BEFORE any
  actuation happens: the sync task calls this module after the named queries
  return and before the Reactor dispatch, so a refusal writes zero files.
  """

  @refusal "REFUSED:SEMANTIC_JIRA_BASE_SHA_UNVERIFIED"
  @skip "SKIPPED:SEMANTIC_JIRA_BASE_SHA_OUTSIDE_JURISDICTION"

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
    * `:all` -- when true, target EVERY row's baseSha (the `--verify-base-sha`
      flag); when false (default), target only rows that opted themselves in
      via the `#{@opt_in_column}` column.

  Jurisdiction (v26.9.22 union law, made explicit by V23-T6R): the verifier's
  jurisdiction is the verified work tree's OWN repository, the `owner/repo`
  parsed from its `remote.origin.url` and compared EXACTLY against the row's
  `repository` (never by substring). A targeted row naming another repository
  is never verified and never silently dropped:

    * targeted by `:all` only -- returned as a typed skip in `"skipped"`
      (`"kind" => "outside_jurisdiction"`, with the row's id, work order,
      repository, baseSha and the jurisdiction); the sync task prints each
      skip as a `#{@skip}` line;
    * opted in per order -- a refusal: the graph demanded ground truth this
      work tree cannot establish.

  Rows without a `repository` column, and work trees without an origin
  remote, are in jurisdiction (verify-everything behavior).

  Raises `ArgumentError` with the `#{@refusal}` prefix on the first failure.
  Otherwise returns `%{"verified" => shas, "skipped" => skips}`: every
  verified baseSha is a commit reachable from HEAD; nothing targeted is the
  vacuous `%{"verified" => [], "skipped" => []}` and never invokes git.
  """
  @spec verify_base_shas!([{String.t(), [map()]}], keyword()) :: %{
          String.t() => [String.t() | map()]
        }
  def verify_base_shas!(named_results, opts) when is_list(named_results) do
    cwd = Keyword.fetch!(opts, :verify_cwd)
    all? = Keyword.get(opts, :all, false)
    rows = Enum.flat_map(named_results, fn {_name, rows} -> rows end)

    targeted =
      Enum.filter(rows, &(is_binary(&1["base_sha"]) and (all? or git_ground_truth_declared?(&1))))

    {in_scope, skipped} = partition_jurisdiction(targeted, cwd)

    case in_scope |> base_shas() |> Enum.uniq() do
      [] ->
        %{"verified" => [], "skipped" => skipped}

      shas ->
        refuse_unless_git_work_tree!(cwd)
        Enum.each(shas, &verify_sha!(&1, cwd))
        %{"verified" => shas, "skipped" => skipped}
    end
  end

  @doc "One typed report line for a jurisdiction skip (printed by the sync task)."
  @spec skip_line(map()) :: String.t()
  def skip_line(skip), do: "#{@skip}: " <> Jason.encode!(skip)

  defp partition_jurisdiction([], _cwd), do: {[], []}

  defp partition_jurisdiction(targeted, cwd) do
    jurisdiction = repository_jurisdiction(cwd)

    Enum.reduce(targeted, {[], []}, fn row, {in_scope, skipped} ->
      cond do
        in_jurisdiction?(row, jurisdiction) ->
          {[row | in_scope], skipped}

        git_ground_truth_declared?(row) ->
          raise ArgumentError,
                "#{@refusal}: baseSha #{literal_value(row["base_sha"])} of " <>
                  "#{inspect(row["id"] || row["work_order"])} (repository " <>
                  "#{literal_value(row["repository"])}) opted into git ground truth but is " <>
                  "outside the jurisdiction #{jurisdiction} of #{cwd}"

        true ->
          {in_scope, [skip(row, jurisdiction) | skipped]}
      end
    end)
    |> then(fn {in_scope, skipped} ->
      {Enum.reverse(in_scope), skipped |> Enum.reverse() |> Enum.uniq()}
    end)
  end

  defp skip(row, jurisdiction) do
    %{
      "kind" => "outside_jurisdiction",
      "id" => literal_value(row["id"]),
      "work_order" => row["work_order"],
      "repository" => literal_value(row["repository"]),
      "base_sha" => literal_value(row["base_sha"]),
      "jurisdiction" => jurisdiction
    }
  end

  # The verifier's jurisdiction is the verified work tree's OWN repository:
  # rows bound to another history (e.g. crown rows binding `local/eds`) are
  # outside this check. `nil` = no origin remote = no jurisdiction filter.
  defp in_jurisdiction?(_row, nil), do: true

  defp in_jurisdiction?(row, jurisdiction) do
    case row["repository"] do
      repo when is_binary(repo) -> literal_value(repo) == jurisdiction
      _ -> true
    end
  end

  defp repository_jurisdiction(cwd) do
    case git(cwd, ["config", "--get", "remote.origin.url"]) do
      {url, 0} -> origin_repository(url)
      _ -> nil
    end
  end

  # `owner/repo` of an origin URL: https://host/owner/repo(.git),
  # git@host:owner/repo(.git), or a local path (last two segments).
  defp origin_repository(url) do
    url
    |> String.trim()
    |> String.trim_trailing("/")
    |> String.replace_suffix(".git", "")
    |> String.split(["/", ":"], trim: true)
    |> Enum.take(-2)
    |> Enum.join("/")
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
  defp literal_value(value) when not is_binary(value), do: value

  defp literal_value(value) do
    case Regex.run(~r/\A"(.*)"(?:\^\^<[^>]*>)?(?:@[A-Za-z-]+)?\z/s, value) do
      [_all, inner] -> inner
      _no_match -> value
    end
  end
end
