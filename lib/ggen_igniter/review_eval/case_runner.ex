defmodule GgenIgniter.ReviewEval.CaseRunner do
  @moduledoc """
  Materializes the defective state of one corpus case in a REAL temp clone
  (`git clone` + `git checkout parent_sha`), generates the defective diff, and
  invokes a review pipeline through a pluggable `reviewer_fn`.

  Default adapter shells out to `claude -p` with the ggen-reviewer agent
  markdown as the prompt and the defective diff on stdin. Never fabricates
  findings: if the reviewer binary is unavailable or fails, the case verdict
  is typed `:reviewer_unavailable` / `{:reviewer_error, code}` — counted as
  errors (fail-closed), not misses, and never as a fake pass.
  """

  @default_timeout 300_000

  @type result :: %{
          required(:case_id) => String.t(),
          required(:status) => :ok | :reviewer_unavailable | {:reviewer_error, term()},
          required(:stdout) => String.t(),
          required(:exit_code) => non_neg_integer() | nil,
          required(:duration_ms) => non_neg_integer(),
          required(:findings) => [map()] | nil
        }

  @doc """
  Run one case against a reviewer. Opts:

    * `:repo_root` - repo to clone (default ".")
    * `:reviewer_fn` - `(case, diff, opts) -> result-map` (default `claude -p` adapter)
    * `:timeout_ms` - forwarded to the reviewer (default 300_000)

  The returned map always carries `case_id`, `status`, `stdout`, `exit_code`,
  `duration_ms`, `findings`.
  """
  @spec run(map(), keyword()) :: result()
  def run(case, opts \\ []) do
    repo_root = Keyword.get(opts, :repo_root, ".")
    reviewer_fn = Keyword.get(opts, :reviewer_fn, &default_reviewer/3)
    timeout = Keyword.get(opts, :timeout_ms, @default_timeout)

    parent = case["diff_ref"]["parent_sha"]
    tmp = tmp_dir!()
    clone = Path.join(tmp, "clone")

    try do
      {_, 0} =
        System.cmd("git", ["clone", "--quiet", "--no-hardlinks", Path.absname(repo_root), clone],
          stderr_to_stdout: true
        )

      {_, 0} =
        System.cmd("git", ["checkout", "--quiet", parent], cd: clone, stderr_to_stdout: true)

      diff = defective_diff(clone, parent, case)

      started = System.monotonic_time(:millisecond)
      result = reviewer_fn.(case, diff, timeout: timeout)
      duration = System.monotonic_time(:millisecond) - started

      Map.merge(%{status: :ok, stdout: "", exit_code: nil, findings: nil}, result)
      |> Map.merge(%{case_id: case["case_id"], duration_ms: duration})
    after
      File.rm_rf!(tmp)
    end
  end

  @doc "git diff between parent_sha and fix_sha, restricted to the case location's file."
  @spec defective_diff(String.t(), String.t(), map()) :: String.t()
  def defective_diff(clone_root, parent_sha, case) do
    file = get_in(case, ["location", "file"])

    args =
      if is_binary(file),
        do: ["diff", parent_sha, case["diff_ref"]["fix_sha"], "--", file],
        else: ["diff", parent_sha, case["diff_ref"]["fix_sha"]]

    {out, 0} = System.cmd("git", args, cd: clone_root, stderr_to_stdout: true)
    out
  end

  # -- default adapter ---------------------------------------------------

  defp default_reviewer(case, diff, opts) do
    _timeout = Keyword.fetch!(opts, :timeout)

    if System.find_executable("claude") == nil do
      %{
        status: :reviewer_unavailable,
        stdout: "",
        exit_code: nil,
        findings: nil,
        raw: "claude binary not on PATH"
      }
    else
      file = get_in(case, ["location", "file"])
      args = ["-p", "--output-format", "text", reviewer_prompt()]
      script = "claude #{Enum.map_join(args, " ", &sh_quote/1)} < \"$REVIEW_EVAL_DIFF\""

      try do
        {stdout, code} =
          System.cmd("/bin/sh", ["-c", script],
            stderr_to_stdout: true,
            env: [{"REVIEW_EVAL_DIFF", write_diff_file!(diff)}]
          )

        %{
          status: if(code == 0, do: :ok, else: {:reviewer_error, code}),
          stdout: stdout,
          exit_code: code,
          findings: parse_findings(stdout),
          raw: stdout
        }
      rescue
        e ->
          %{
            status: {:reviewer_error, Exception.message(e)},
            stdout: "",
            exit_code: nil,
            findings: nil,
            raw: Exception.message(e)
          }
      after
        _ = file
        :ok
      end
    end
  end

  defp sh_quote(s), do: "'" <> String.replace(s, "'", "'\\''") <> "'"

  defp write_diff_file!(diff) do
    path = Path.join(System.tmp_dir!(), "review-eval-diff-#{:erlang.unique_integer()}")
    File.write!(path, diff)
    path
  end

  defp reviewer_prompt do
    path = Path.expand(".claude/agents/ggen-reviewer.md", File.cwd!())

    if File.exists?(path) do
      File.read!(path)
    else
      "Review the following diff for correctness defects. Cite findings as file:line."
    end
  end

  @doc "Best-effort extraction of file:line mentions from reviewer stdout."
  @spec parse_findings(String.t()) :: [map()]
  def parse_findings(stdout) do
    Regex.scan(~r/([A-Za-z0-9_\/\.\-]+\.(?:ex|exs|rs|ts|md)):(\d+)/, stdout)
    |> Enum.map(fn [_, f, ln] ->
      {n, _} = Integer.parse(ln)
      %{"file" => f, "line" => n}
    end)
    |> Enum.uniq()
  end

  # -- temp workspace (inside the lane build root, cleaned after each case) --

  defp tmp_dir! do
    base = Path.join([File.cwd!(), "_build-lane-l6", "review-eval-tmp"])
    File.mkdir_p!(base)
    path = Path.join(base, "case-#{:erlang.unique_integer([:positive])}")
    File.mkdir_p!(path)
    path
  end
end
