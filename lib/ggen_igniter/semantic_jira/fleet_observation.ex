defmodule GgenIgniter.SemanticJira.FleetObservation do
  @moduledoc """
  Fleet observation as PROV-O: read-only git/gh probes over every repository
  in a fleet registry, emitted as Turtle in which every observation entity is
  bound to the exact SHA it was read at.

      mix semantic_jira.observe --fleet REGISTRY.ttl --out OBS.ttl

  The registry is a graph of `sj:ObservedRepository` nodes with an
  `sj:repositoryPath`, read through the pack query
  `runtime-queries/fleet_repositories.rq`. The output shape is the pack
  template `runtime-templates/fleet_observation.ttl.eex`; this module only
  runs the probes and parses their output (the hand-written residue recorded
  as `sj:ledger-unsupported-002`).

  Per repository (one `sj:RepositoryObservation` activity, `prov:used` the
  repository, `dcterms:isPartOf` the single `sj:FleetObservation`):

    * `sj:RefObservation` -- every `refs/heads/*` and `refs/remotes/*` ref,
      with upstream ahead/behind counts, `sj:unpushed` (ahead > 0) and
      `sj:fastForwardable` (ahead == 0 and behind > 0) for tracking branches;
    * `sj:RemoteRefDelta` -- `git ls-remote --symref` per remote compared with
      the local tracking refs (`moved`, `remote_only`, `tracking_only`);
    * `sj:WorktreeObservation` -- every worktree of `git worktree list`, with
      `git --no-optional-locks status --porcelain` dirty entry count;
    * `sj:StashObservation` -- every `git stash list` entry;
    * `sj:PullRequestObservation` -- open PRs (`gh pr list`) with the check
      rollup reduced to success/failure/pending/none;
    * `sj:DefaultBranchCiObservation` -- check runs at the default-branch SHA
      the remote reports (`gh api .../commits/SHA/check-runs`);
    * `sj:ProbeOutcome` -- a probe that could not observe, typed
      `UNSUPPORTED:*` or `BLOCKED:*`, bound to the repository HEAD it was
      attempted at.

  Read-only by construction: git runs with `GIT_OPTIONAL_LOCKS=0` (status
  never refreshes an index), `GIT_TERMINAL_PROMPT=0`, and no fetch; gh is
  used only for GET queries. A registry path that is absent or has no HEAD
  yields an activity with a `BLOCKED:*` status and no entities, so no
  entity is ever emitted without an observed SHA.

  Determinism: all collections are sorted and all IRIs are content-derived,
  so two runs over unchanged repositories differ only in the single
  `prov:endedAtTime` line.

  Disclosed bounds: tags are not observed; the CI conclusion reads GitHub
  check runs only (legacy commit statuses are not merged in); at most 200
  open PRs and 100 check runs are read per repository.
  """

  alias GgenIgniter.{Ontology, Query, Render}

  @sha ~r/\A(?:[0-9a-f]{40}|[0-9a-f]{64})\z/
  @network_timeout 120_000
  @git_env [
    {"GIT_OPTIONAL_LOCKS", "0"},
    {"GIT_TERMINAL_PROMPT", "0"},
    {"GIT_SSH_COMMAND", "ssh -o BatchMode=yes -o ConnectTimeout=15"},
    {"LC_ALL", "C"}
  ]

  @doc "Observe every registry repository and write the Turtle to `out_path`."
  @spec write!(String.t(), String.t(), keyword()) :: %{repositories: non_neg_integer()}
  def write!(registry_path, out_path, opts \\ []) do
    {turtle, count} = observe!(registry_path, opts)
    File.mkdir_p!(Path.dirname(out_path))
    File.write!(out_path, turtle)
    %{repositories: count}
  end

  @doc """
  Observe every registry repository; returns `{turtle, repository_count}`.

  `opts`: `:ended_at` (a `DateTime`, default now) is the only
  time-dependent input.
  """
  @spec observe!(String.t(), keyword()) :: {String.t(), non_neg_integer()}
  def observe!(registry_path, opts \\ []) do
    registry_path = Path.expand(registry_path)
    repositories = registry(registry_path)
    repos = Enum.map(repositories, &observe_repository/1)

    fleet_iri =
      urn("fleet-observation", [
        registry_path | Enum.map(repos, &"#{&1.path}@#{&1.head_sha}")
      ])

    repos = Enum.map(repos, &Map.put(&1, :iri, urn("observation", [fleet_iri, &1.repository])))

    ended_at =
      opts
      |> Keyword.get_lazy(:ended_at, &DateTime.utc_now/0)
      |> DateTime.truncate(:second)
      |> DateTime.to_iso8601()

    fleet = %{iri: fleet_iri, registry_iri: file_iri(registry_path), ended_at: ended_at}

    turtle =
      [GgenIgniter.SemanticA2A.pack_dir(), "runtime-templates", "fleet_observation.ttl.eex"]
      |> Path.join()
      |> File.read!()
      |> Render.render(fleet: fleet, repos: repos, lit: &literal/1)

    {turtle, length(repos)}
  end

  @doc "Registry rows `%{repository: iri, path: path}`, sorted by path."
  @spec registry(String.t()) :: [%{repository: String.t(), path: String.t()}]
  def registry(registry_path) do
    query =
      [GgenIgniter.SemanticA2A.pack_dir(), "runtime-queries", "fleet_repositories.rq"]
      |> Path.join()
      |> File.read!()

    registry_path
    |> Ontology.load!()
    |> Query.run(query)
    |> Enum.map(&%{repository: to_string(&1["repository"]), path: to_string(&1["path"])})
    |> Enum.uniq()
    |> Enum.sort_by(&{&1.path, &1.repository})
  end

  # ── per repository ────────────────────────────────────────────────────────

  defp observe_repository(%{repository: repository, path: path}) do
    base = %{
      repository: repository,
      path: path,
      head_sha: nil,
      status: nil,
      refs: [],
      deltas: [],
      worktrees: [],
      stashes: [],
      pull_requests: [],
      ci: [],
      probes: []
    }

    with true <- File.dir?(path) || {:blocked, "BLOCKED:path-absent"},
         {:ok, head} <- head_sha(path) do
      observe_at_head(%{base | head_sha: head, status: "OBSERVED"})
    else
      {:blocked, status} -> %{base | status: status}
    end
  end

  defp head_sha(path) do
    with {out, 0} <- git(path, ["rev-parse", "--verify", "--quiet", "HEAD^{commit}"]),
         head = String.trim(out),
         true <- Regex.match?(@sha, head) do
      {:ok, head}
    else
      _no_head -> {:blocked, "BLOCKED:no-head"}
    end
  end

  defp observe_at_head(repo) do
    refs = refs(repo)
    {deltas, remote_heads, ls_probes} = remote_deltas(repo, refs)
    {worktrees, wt_probes} = worktrees(repo)
    {prs, ci, gh_probes} = github(repo, remote_heads)

    probes =
      (ls_probes ++ wt_probes ++ gh_probes)
      |> Enum.map(&Map.put(&1, :iri, urn("probe", [repo.path, &1.probe, repo.head_sha])))
      |> Enum.sort_by(& &1.probe)

    %{
      repo
      | refs: refs,
        deltas: deltas,
        worktrees: worktrees,
        stashes: stashes(repo),
        pull_requests: prs,
        ci: ci,
        probes: probes
    }
  end

  # ── refs + upstream tracking ─────────────────────────────────────────────

  defp refs(repo) do
    format = "%(refname)%09%(objectname)%09%(upstream)%09%(upstream:track,nobracket)"

    {out, 0} =
      git(repo.path, ["for-each-ref", "--format=#{format}", "refs/heads", "refs/remotes"])

    out
    |> lines()
    |> Enum.flat_map(fn line ->
      case String.split(line, "\t") do
        [name, sha, upstream, track] -> ref(repo, name, sha, upstream, track)
        _other -> []
      end
    end)
    |> Enum.sort_by(& &1.name)
  end

  defp ref(repo, name, sha, upstream, track) do
    if Regex.match?(@sha, sha) do
      [
        %{
          iri: urn("ref", [repo.path, name, sha]),
          name: name,
          sha: sha,
          upstream: if(upstream == "", do: nil, else: upstream),
          ahead: count(track, "ahead"),
          behind: count(track, "behind"),
          gone: track == "gone"
        }
      ]
    else
      []
    end
  end

  defp count(track, word) do
    case Regex.run(~r/#{word} (\d+)/, track) do
      [_all, n] -> String.to_integer(n)
      nil -> 0
    end
  end

  # ── ls-remote delta ──────────────────────────────────────────────────────

  defp remote_deltas(repo, refs) do
    {out, 0} = git(repo.path, ["remote"])

    out
    |> lines()
    |> Enum.sort()
    |> Enum.reduce({[], %{}, []}, fn remote, {deltas, heads, probes} ->
      case ls_remote(repo.path, remote) do
        {:ok, remote_refs} ->
          {deltas ++ delta(repo, remote, remote_refs, refs), Map.put(heads, remote, remote_refs),
           probes}

        {:error, outcome, detail} ->
          {deltas, heads,
           [
             %{probe: "ls-remote:#{remote}", outcome: outcome, detail: detail, sha: repo.head_sha}
             | probes
           ]}
      end
    end)
  end

  defp ls_remote(path, remote) do
    args = [
      "-c",
      "http.lowSpeedLimit=1000",
      "-c",
      "http.lowSpeedTime=30",
      "ls-remote",
      "--symref",
      remote,
      "HEAD",
      "refs/heads/*"
    ]

    case timed(fn -> git(path, args) end, @network_timeout) do
      {:ok, {out, 0}} -> {:ok, parse_ls_remote(out)}
      {:ok, {out, code}} -> {:error, "BLOCKED:ls-remote-exit-#{code}", first_line(out)}
      :timeout -> {:error, "BLOCKED:ls-remote-timeout", "no answer in #{@network_timeout}ms"}
    end
  end

  defp parse_ls_remote(out) do
    out
    |> lines()
    |> Enum.reduce(%{heads: %{}, head_sha: nil, default_branch: nil}, fn line, acc ->
      case String.split(line, "\t") do
        ["ref: refs/heads/" <> branch, "HEAD"] -> %{acc | default_branch: branch}
        [sha, "HEAD"] -> %{acc | head_sha: sha}
        [sha, "refs/heads/" <> branch] -> put_in(acc, [:heads, branch], sha)
        _other -> acc
      end
    end)
  end

  defp delta(repo, remote, remote_refs, refs) do
    prefix = "refs/remotes/#{remote}/"

    tracking =
      for %{name: prefix_name, sha: sha} <- refs,
          String.starts_with?(prefix_name, prefix),
          branch = String.replace_prefix(prefix_name, prefix, ""),
          branch != "HEAD",
          into: %{},
          do: {branch, sha}

    branches = Enum.sort(Enum.uniq(Map.keys(remote_refs.heads) ++ Map.keys(tracking)))

    Enum.flat_map(branches, fn branch ->
      remote_sha = Map.get(remote_refs.heads, branch)
      tracking_sha = Map.get(tracking, branch)

      case {remote_sha, tracking_sha} do
        {same, same} -> []
        {nil, t} -> [delta_row(repo, remote, branch, "tracking_only", nil, t, t)]
        {r, nil} -> [delta_row(repo, remote, branch, "remote_only", r, nil, r)]
        {r, t} -> [delta_row(repo, remote, branch, "moved", r, t, r)]
      end
    end)
  end

  defp delta_row(repo, remote, branch, kind, remote_sha, tracking_sha, sha) do
    %{
      iri: urn("delta", [repo.path, remote, branch, kind, sha]),
      remote: remote,
      ref: "refs/heads/#{branch}",
      kind: kind,
      remote_sha: remote_sha,
      tracking_sha: tracking_sha,
      sha: sha
    }
  end

  # ── worktrees ────────────────────────────────────────────────────────────

  defp worktrees(repo) do
    {out, 0} = git(repo.path, ["worktree", "list", "--porcelain"])

    out
    |> String.split(~r/\n\n+/, trim: true)
    |> Enum.map(&worktree_block/1)
    |> Enum.reject(&(&1["bare"] || is_nil(&1["worktree"])))
    |> Enum.sort_by(& &1["worktree"])
    |> Enum.reduce({[], []}, fn block, {rows, probes} ->
      path = block["worktree"]
      sha = block["HEAD"]

      if is_binary(sha) and Regex.match?(@sha, sha) do
        {rows ++ [worktree_row(path, sha, block["branch"])], probes}
      else
        probe = %{
          probe: "worktree:#{path}",
          outcome: "BLOCKED:no-head",
          detail: path,
          sha: repo.head_sha
        }

        {rows, probes ++ [probe]}
      end
    end)
  end

  defp worktree_block(block) do
    block
    |> lines()
    |> Map.new(fn line ->
      case String.split(line, " ", parts: 2) do
        [key, value] -> {key, value}
        [key] -> {key, true}
      end
    end)
  end

  defp worktree_row(path, sha, branch) do
    {status, dirty_count} =
      if File.dir?(path) do
        case git(path, ["status", "--porcelain=v1", "--untracked-files=normal"]) do
          {out, 0} -> {"OBSERVED", length(lines(out))}
          {_out, code} -> {"BLOCKED:status-exit-#{code}", nil}
        end
      else
        {"BLOCKED:worktree-path-absent", nil}
      end

    %{
      iri: urn("worktree", [path, sha]),
      path: path,
      sha: sha,
      branch: if(is_binary(branch), do: branch, else: nil),
      status: status,
      dirty_count: dirty_count
    }
  end

  # ── stashes ──────────────────────────────────────────────────────────────

  defp stashes(repo) do
    {out, 0} = git(repo.path, ["stash", "list", "--format=%H%x09%gd%x09%gs"])

    out
    |> lines()
    |> Enum.map(&String.split(&1, "\t", parts: 3))
    |> Enum.filter(&stash_line?/1)
    |> Enum.map(fn [sha, ref, subject] ->
      %{iri: urn("stash", [repo.path, ref, sha]), sha: sha, ref: ref, subject: subject}
    end)
  end

  defp stash_line?([sha, _ref, _subject]), do: Regex.match?(@sha, sha)
  defp stash_line?(_other), do: false

  # ── GitHub: open PRs + default-branch CI ─────────────────────────────────

  defp github(repo, remote_heads) do
    remotes = remote_urls(repo.path)

    case Enum.find_value(remotes, fn {name, url} -> slug(url) && {name, slug(url)} end) do
      nil ->
        detail = "remotes: " <> Enum.map_join(remotes, ",", &elem(&1, 0))

        probes =
          for probe <- ["gh:default-branch-ci", "gh:pull-requests"] do
            %{
              probe: probe,
              outcome: "UNSUPPORTED:no-github-remote",
              detail: detail,
              sha: repo.head_sha
            }
          end

        {[], [], probes}

      {remote, slug} ->
        {prs, pr_probes} = pull_requests(repo, slug)
        {ci, ci_probes} = default_branch_ci(repo, slug, Map.get(remote_heads, remote))
        {prs, ci, pr_probes ++ ci_probes}
    end
  end

  defp remote_urls(path) do
    {out, 0} = git(path, ["remote"])

    out
    |> lines()
    |> Enum.sort()
    |> Enum.map(fn name ->
      case git(path, ["remote", "get-url", name]) do
        {url, 0} -> {name, String.trim(url)}
        _other -> {name, ""}
      end
    end)
    |> Enum.sort_by(fn {name, _url} -> {name != "origin", name} end)
  end

  @doc false
  @spec slug(String.t()) :: String.t() | nil
  def slug(url) do
    case Regex.run(~r{github\.com[:/]+([^/]+)/([^/]+?)(?:\.git)?/?\z}, url) do
      [_all, owner, name] -> "#{owner}/#{name}"
      nil -> nil
    end
  end

  defp pull_requests(repo, slug) do
    args = [
      "pr",
      "list",
      "--repo",
      slug,
      "--state",
      "open",
      "--limit",
      "200",
      "--json",
      "number,headRefName,headRefOid,baseRefName,statusCheckRollup"
    ]

    case gh_json(args) do
      {:ok, prs} when is_list(prs) ->
        rows =
          prs
          |> Enum.filter(&Regex.match?(@sha, to_string(&1["headRefOid"])))
          |> Enum.map(fn pr ->
            checks = pr["statusCheckRollup"] || []

            %{
              iri: urn("pull-request", [slug, pr["number"], pr["headRefOid"]]),
              number: pr["number"],
              head_ref: pr["headRefName"],
              base_ref: pr["baseRefName"],
              sha: pr["headRefOid"],
              conclusion: rollup(Enum.map(checks, &check_state/1)),
              check_count: length(checks)
            }
          end)
          |> Enum.sort_by(& &1.number)

        {rows, []}

      {:error, outcome, detail} ->
        {[], [%{probe: "gh:pull-requests", outcome: outcome, detail: detail, sha: repo.head_sha}]}
    end
  end

  defp default_branch_ci(repo, _slug, nil) do
    {[],
     [
       %{
         probe: "gh:default-branch-ci",
         outcome: "BLOCKED:no-remote-default-sha",
         detail: "ls-remote did not report HEAD for the GitHub remote",
         sha: repo.head_sha
       }
     ]}
  end

  defp default_branch_ci(repo, slug, %{head_sha: sha, default_branch: branch}) do
    if is_binary(sha) and Regex.match?(@sha, sha) do
      case gh_json(["api", "repos/#{slug}/commits/#{sha}/check-runs?per_page=100"]) do
        {:ok, %{"check_runs" => runs}} ->
          {[
             %{
               iri: urn("ci", [slug, sha]),
               branch: branch || "HEAD",
               sha: sha,
               conclusion: rollup(Enum.map(runs, &check_state/1)),
               check_count: length(runs)
             }
           ], []}

        {:ok, _other} ->
          {[],
           [
             %{
               probe: "gh:default-branch-ci",
               outcome: "BLOCKED:gh-unexpected-shape",
               detail: slug,
               sha: repo.head_sha
             }
           ]}

        {:error, outcome, detail} ->
          {[],
           [
             %{
               probe: "gh:default-branch-ci",
               outcome: outcome,
               detail: detail,
               sha: repo.head_sha
             }
           ]}
      end
    else
      default_branch_ci(repo, slug, nil)
    end
  end

  # CheckRun (status + conclusion, any case) and StatusContext (state).
  defp check_state(check) do
    status = check |> Map.get("status", "") |> to_string() |> String.downcase()
    conclusion = check |> Map.get("conclusion") |> to_string() |> String.downcase()
    state = check |> Map.get("state") |> to_string() |> String.downcase()

    cond do
      state in ["failure", "error"] -> :failure
      state in ["pending", "expected"] -> :pending
      state == "success" -> :success
      status not in ["", "completed"] -> :pending
      conclusion in ["success", "neutral", "skipped"] -> :success
      conclusion == "" -> :pending
      true -> :failure
    end
  end

  defp rollup([]), do: "none"

  defp rollup(states) do
    cond do
      :failure in states -> "failure"
      :pending in states -> "pending"
      true -> "success"
    end
  end

  defp gh_json(args) do
    case System.find_executable("gh") do
      nil ->
        {:error, "UNSUPPORTED:gh-absent", "gh not on PATH"}

      gh ->
        fn -> System.cmd(gh, args, stderr_to_stdout: true, env: @git_env) end
        |> timed(@network_timeout)
        |> decode_gh()
    end
  end

  defp decode_gh({:ok, {out, 0}}) do
    case Jason.decode(out) do
      {:ok, json} -> {:ok, json}
      {:error, _} -> {:error, "BLOCKED:gh-invalid-json", first_line(out)}
    end
  end

  defp decode_gh({:ok, {out, code}}), do: {:error, "BLOCKED:gh-exit-#{code}", first_line(out)}

  defp decode_gh(:timeout),
    do: {:error, "BLOCKED:gh-timeout", "no answer in #{@network_timeout}ms"}

  # ── helpers ──────────────────────────────────────────────────────────────

  defp git(path, args) do
    System.cmd("git", ["-C", path | args], stderr_to_stdout: false, env: @git_env)
  end

  defp timed(fun, timeout) do
    task = Task.async(fun)

    case Task.yield(task, timeout) || Task.shutdown(task, :brutal_kill) do
      {:ok, result} -> {:ok, result}
      _ -> :timeout
    end
  end

  defp lines(out), do: String.split(out, "\n", trim: true)

  defp first_line(out) do
    out |> String.split("\n", trim: true) |> List.first("") |> String.slice(0, 200)
  end

  defp urn(kind, parts) do
    digest =
      :sha256
      |> :crypto.hash(Enum.map_join(parts, "\u0000", &to_string/1))
      |> Base.encode16(case: :lower)
      |> binary_part(0, 32)

    "urn:ggen-igniter:sj:#{kind}:#{digest}"
  end

  defp file_iri(path), do: "file://" <> URI.encode(path)

  @doc false
  @spec literal(String.t()) :: String.t()
  def literal(value) do
    escaped =
      value
      |> to_string()
      |> String.replace("\\", "\\\\")
      |> String.replace("\"", "\\\"")
      |> String.replace("\n", "\\n")
      |> String.replace("\r", "\\r")
      |> String.replace("\t", "\\t")

    "\"" <> escaped <> "\""
  end
end
