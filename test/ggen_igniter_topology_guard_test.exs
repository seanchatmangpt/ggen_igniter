defmodule GgenIgniter.TopologyGuardTest do
  @moduledoc """
  Repository topology is transport, never ontology (operator directive 2026-09-23/24).

  The v26.9.22/23 run grew a shadow topology of git worktrees and integration copies under
  `~/wt/`, and courts, tests and defaults silently came to depend on those paths
  (`GGEN_IGNITER_DIR` defaulted into `~/wt/v26922/fri/ggen_igniter-int`). This guard makes the
  regression mechanical: no executable source, config, court, script or test in this repository
  may reference a `~/wt/` shadow checkout or create git worktrees. Receipts, fixtures and
  recorded episode evidence keep their historical paths and are excluded.

  Chicago: the committed tree is read with real `git ls-files`; the falsifier plants a real
  reference in a real temporary git repository and requires the same scan to refuse it.
  """
  use ExUnit.Case, async: true

  @root Path.expand("..", __DIR__)
  @scanned ~w(lib config scripts priv test .github mix.exs)
  @excluded ~r{(^|/)(receipts|fixtures|episodes)/|\.json$|^test/ggen_igniter_topology_guard_test\.exs$}
  @shadow_path ~r{/Users/[^/\s"']+/wt/|~/wt/}
  @worktree_add ~r{(^|[;&|(\n]|\$\()\s*git(\s+-C\s+\S+)?\s+worktree\s+add\b}m

  test "no executable file references a ~/wt shadow checkout or creates git worktrees" do
    assert offenders(@root) == []
  end

  test "the scan refuses a planted shadow path and a planted worktree add (falsifier)" do
    dir = Path.join(System.tmp_dir!(), "topology-guard-#{System.unique_integer([:positive])}")
    File.mkdir_p!(Path.join(dir, "lib"))
    on_exit(fn -> File.rm_rf!(dir) end)
    {_, 0} = System.cmd("git", ["-C", dir, "init", "-q"])
    File.write!(Path.join(dir, "lib/a.ex"), ~s|@dir "/Users/someone/wt/v26922/fri/x-int"\n|)
    File.write!(Path.join(dir, "lib/b.sh"), "cd /tmp && git worktree add ../y main\n")
    File.write!(Path.join(dir, "lib/c.ex"), "# fine: mentions git worktree in prose only\n")
    {_, 0} = System.cmd("git", ["-C", dir, "add", "-A"])

    assert Enum.map(offenders(dir), &elem(&1, 0)) == ["lib/a.ex", "lib/b.sh"]
  end

  defp offenders(root) do
    {out, 0} = System.cmd("git", ["-C", root, "ls-files", "--" | @scanned])

    for path <- String.split(out, "\n", trim: true),
        not Regex.match?(@excluded, path),
        text = File.read!(Path.join(root, path)),
        String.valid?(text),
        Regex.match?(@shadow_path, text) or Regex.match?(@worktree_add, text),
        do: {path, :shadow_topology}
  end
end
