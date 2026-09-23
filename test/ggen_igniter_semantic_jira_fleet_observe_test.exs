defmodule GgenIgniter.SemanticJiraFleetObserveTest do
  @moduledoc """
  Chicago-style: real git repositories built in a unique tmp dir (a bare
  remote, two clones, a linked worktree, a real stash), the real
  `mix semantic_jira.observe --fleet` task run twice in-process and writing
  real Turtle to disk, parsed back through the real `rdf` Turtle reader and
  queried with the real `sparql` engine. Expected SHAs come from real
  `git rev-parse` calls against the same repositories. No network: the
  remotes are file paths, so `ls-remote` is real and the GitHub probes are
  recorded as typed `UNSUPPORTED:no-github-remote` outcomes. No test doubles
  of any kind.
  """

  # async: false -- the task is driven through Mix.Task.rerun/2 and prints
  # through the global Mix.shell().
  use ExUnit.Case, async: false

  alias GgenIgniter.{Ontology, Query}

  @sj "https://ggen-igniter.dev/ontology/semantic-jira#"
  @prefixes """
  PREFIX sj: <#{@sj}>
  PREFIX prov: <http://www.w3.org/ns/prov#>
  """

  # One fleet build and two task runs shared by every test in this file:
  # the tests only read the emitted Turtle and the repositories.
  setup_all do
    base = Path.join(System.tmp_dir!(), "sj_fleet_observe_#{System.unique_integer([:positive])}")
    File.rm_rf!(base)
    File.mkdir_p!(base)
    on_exit(fn -> File.rm_rf!(base) end)

    # Canonical path: git records worktree paths physically resolved, and
    # macOS tmp dirs sit behind a /var -> /private/var symlink.
    {tmp, 0} = System.cmd("pwd", ["-P"], cd: base)
    fleet = build_fleet!(String.trim(tmp))

    out1 = Path.join(fleet.tmp, "obs1.ttl")
    out2 = Path.join(fleet.tmp, "obs2.ttl")
    Mix.Task.rerun("semantic_jira.observe", ["--fleet", fleet.registry, "--out", out1])
    # Cross a second boundary so the prov:endedAtTime literal really differs.
    Process.sleep(1_100)
    Mix.Task.rerun("semantic_jira.observe", ["--fleet", fleet.registry, "--out", out2])

    graph = Ontology.load!(out1)
    Map.merge(fleet, %{out1: out1, out2: out2, graph: graph})
  end

  describe "run/1 (--fleet over real tmp repositories)" do
    test "two runs are byte-identical modulo the single prov:endedAtTime triple", ctx do
      first = File.read!(ctx.out1)
      second = File.read!(ctx.out2)

      assert ended_lines(first) |> length() == 1
      assert ended_lines(second) |> length() == 1
      refute first == second, "endedAtTime did not change across a 1.1s gap"
      assert strip_ended(first) == strip_ended(second)
    end

    test "one sj:observedRepository line per registry repository", ctx do
      text = File.read!(ctx.out1)

      lines =
        text |> String.split("\n") |> Enum.filter(&String.contains?(&1, "sj:observedRepository"))

      assert length(lines) == 3
    end

    test "unpushed commit: topic is ahead of its upstream at the topic SHA", ctx do
      refs = refs(ctx.graph, ctx.subject)
      topic = Map.fetch!(refs, "refs/heads/topic")

      assert topic.sha == rev_parse(ctx.subject, "topic")
      assert topic.ahead == 1
      assert topic.unpushed == true
      assert topic.ff == false
    end

    test "ff-able remote: main is behind origin/main with nothing ahead", ctx do
      main = ctx.graph |> refs(ctx.subject) |> Map.fetch!("refs/heads/main")

      assert main.sha == rev_parse(ctx.subject, "main")
      assert main.ahead == 0
      assert main.behind == 1
      assert main.ff == true
      assert main.unpushed == false
    end

    test "ls-remote delta: remote main moved past the local tracking ref", ctx do
      rows =
        Query.run(ctx.graph, """
        #{@prefixes}
        SELECT ?kind ?remote ?tracking ?sha WHERE {
          ?d a sj:RemoteRefDelta ;
             sj:refName "refs/heads/main" ;
             sj:deltaKind ?kind ;
             sj:remoteSha ?remote ;
             sj:trackingSha ?tracking ;
             sj:observedSha ?sha ;
             prov:wasGeneratedBy ?a .
          ?a sj:repositoryPath "#{ctx.subject}" .
        }
        """)

      assert [%{"kind" => "moved", "remote" => remote, "tracking" => tracking, "sha" => sha}] =
               rows

      assert remote == rev_parse(ctx.seed, "main")
      assert tracking == rev_parse(ctx.subject, "origin/main")
      assert sha == remote
      refute remote == tracking
    end

    test "dirty worktree: the linked worktree reports its two entries at its HEAD", ctx do
      rows =
        Query.run(ctx.graph, """
        #{@prefixes}
        SELECT ?path ?dirty ?count ?sha WHERE {
          ?w a sj:WorktreeObservation ;
             sj:worktreePath ?path ;
             sj:dirty ?dirty ;
             sj:dirtyEntryCount ?count ;
             sj:observedSha ?sha .
        }
        """)

      by_path = Map.new(rows, &{&1["path"], &1})

      linked = Map.fetch!(by_path, ctx.linked)
      assert linked["dirty"] == true
      assert linked["count"] == 2
      assert linked["sha"] == rev_parse(ctx.linked, "HEAD")

      main = Map.fetch!(by_path, ctx.subject)
      assert main["dirty"] == false
      assert main["count"] == 0
      assert main["sha"] == rev_parse(ctx.subject, "HEAD")
    end

    test "stash: the stash entry is bound to the stash commit SHA", ctx do
      rows =
        Query.run(ctx.graph, """
        #{@prefixes}
        SELECT ?ref ?subject ?sha WHERE {
          ?s a sj:StashObservation ;
             sj:stashRef ?ref ;
             sj:stashSubject ?subject ;
             sj:observedSha ?sha ;
             prov:wasGeneratedBy ?a .
          ?a sj:repositoryPath "#{ctx.subject}" .
        }
        """)

      assert [%{"ref" => "stash@{0}", "subject" => subject, "sha" => sha}] = rows
      assert sha == rev_parse(ctx.subject, "stash@{0}")
      assert subject =~ ~s(fleet-stash "quoted")
    end

    test "GitHub probes on a file remote are typed UNSUPPORTED, bound to HEAD", ctx do
      rows =
        Query.run(ctx.graph, """
        #{@prefixes}
        SELECT ?probe ?outcome ?sha WHERE {
          ?p a sj:ProbeOutcome ;
             sj:probe ?probe ;
             sj:probeOutcome ?outcome ;
             sj:observedSha ?sha ;
             prov:wasGeneratedBy ?a .
          ?a sj:repositoryPath "#{ctx.subject}" .
        }
        """)

      head = rev_parse(ctx.subject, "HEAD")

      assert Enum.sort(Enum.map(rows, & &1["probe"])) ==
               ["gh:default-branch-ci", "gh:pull-requests"]

      assert Enum.all?(rows, &(&1["outcome"] == "UNSUPPORTED:no-github-remote"))
      assert Enum.all?(rows, &(&1["sha"] == head))
    end

    test "an absent registry path is BLOCKED with no SHA and no entities", ctx do
      status =
        Query.run(ctx.graph, """
        #{@prefixes}
        SELECT ?status WHERE {
          ?a a sj:RepositoryObservation ;
             sj:repositoryPath "#{ctx.absent}" ;
             sj:observationStatus ?status .
        }
        """)

      assert [%{"status" => "BLOCKED:path-absent"}] = status

      activity_sha =
        Query.run(ctx.graph, """
        #{@prefixes}
        SELECT ?sha WHERE { ?a sj:repositoryPath "#{ctx.absent}" ; sj:observedSha ?sha }
        """)

      entities =
        Query.run(ctx.graph, """
        #{@prefixes}
        SELECT ?e WHERE { ?a sj:repositoryPath "#{ctx.absent}" . ?e prov:wasGeneratedBy ?a }
        """)

      assert activity_sha == []
      assert entities == []
    end

    test "every generated entity carries exactly one 40-hex observed SHA", ctx do
      entities =
        ctx.graph
        |> Query.run("#{@prefixes} SELECT ?e WHERE { ?e prov:wasGeneratedBy ?a }")
        |> Enum.map(& &1["e"])
        |> Enum.uniq()

      bound =
        Query.run(ctx.graph, """
        #{@prefixes}
        SELECT ?e ?sha WHERE { ?e prov:wasGeneratedBy ?a ; sj:observedSha ?sha }
        """)

      assert length(entities) > 10
      assert Enum.sort(Enum.map(bound, & &1["e"])) == Enum.sort(entities)
      assert Enum.all?(bound, &Regex.match?(~r/\A[0-9a-f]{40}\z/, &1["sha"]))
    end

    test "without --fleet the task refuses with a typed reason" do
      assert_raise Mix.Error, ~r/REFUSED:SEMANTIC_JIRA_OBSERVE_MODE_UNSUPPORTED/, fn ->
        Mix.Task.rerun("semantic_jira.observe", [])
      end
    end
  end

  describe "sj:capability-fleet-observe (pack ontology fact)" do
    test "is declared and every witness path exists at this subject" do
      graph = Ontology.load!("priv/ggen/semantic-jira-pack/ontology.ttl")

      rows =
        Query.run(graph, """
        #{@prefixes}
        SELECT ?path ?command ?order WHERE {
          sj:capability-fleet-observe a sj:Capability ;
            sj:witnessPath ?path ;
            sj:witnessCommand ?command ;
            sj:realizesWorkOrder ?order .
        }
        """)

      paths = rows |> Enum.map(& &1["path"]) |> Enum.uniq()

      assert "lib/mix/tasks/semantic_jira.observe.ex" in paths
      assert "test/ggen_igniter_semantic_jira_fleet_observe_test.exs" in paths
      assert Enum.all?(paths, &File.regular?/1), "missing witness: #{inspect(paths)}"
      assert Enum.uniq(Enum.map(rows, & &1["order"])) == ["GGEN_IGNITER-26922-15"]

      assert Enum.uniq(Enum.map(rows, & &1["command"])) ==
               ["mix test test/ggen_igniter_semantic_jira_fleet_observe_test.exs"]
    end
  end

  # ── fixtures: real repositories with known state ─────────────────────────

  defp build_fleet!(tmp) do
    config = Path.join(tmp, "gitconfig")

    File.write!(config, """
    [user]
    \tname = Fleet Observe Test
    \temail = fleet-observe@test.invalid
    [init]
    \tdefaultBranch = main
    [commit]
    \tgpgsign = false
    """)

    env = [{"GIT_CONFIG_GLOBAL", config}, {"GIT_CONFIG_NOSYSTEM", "1"}]
    remote = Path.join(tmp, "remote.git")
    seed = Path.join(tmp, "seed")
    subject = Path.join(tmp, "subject")
    linked = Path.join(tmp, "subject-linked")
    absent = Path.join(tmp, "absent-repo")

    git!(tmp, env, ["init", "--bare", "-b", "main", remote])
    git!(tmp, env, ["clone", remote, seed])
    commit!(seed, env, "README.md", "one\n", "c1")
    git!(seed, env, ["push", "origin", "main"])

    git!(tmp, env, ["clone", remote, subject])
    # Unpushed: a local branch tracking origin/main with one local commit.
    git!(subject, env, ["checkout", "-b", "topic", "--track", "origin/main"])
    commit!(subject, env, "topic.txt", "local\n", "unpushed on topic")
    git!(subject, env, ["checkout", "main"])

    # ff-able: the remote advances and subject fetches without merging.
    commit!(seed, env, "README.md", "two\n", "c2")
    git!(seed, env, ["push", "origin", "main"])
    git!(subject, env, ["fetch", "origin"])

    # ls-remote delta: the remote advances again after that fetch.
    commit!(seed, env, "README.md", "three\n", "c3")
    git!(seed, env, ["push", "origin", "main"])

    # Stash in the main worktree (which is clean afterwards).
    File.write!(Path.join(subject, "README.md"), "stashed change\n")
    git!(subject, env, ["stash", "push", "-m", ~s(fleet-stash "quoted")])

    # Dirty linked worktree: one modified tracked file + one untracked file.
    git!(subject, env, ["worktree", "add", "-b", "linked", linked, "origin/main"])
    File.write!(Path.join(linked, "README.md"), "dirty\n")
    File.write!(Path.join(linked, "untracked.txt"), "new\n")

    registry = Path.join(tmp, "fleet.ttl")

    File.write!(registry, """
    @prefix sj: <#{@sj}> .
    <file://#{subject}> a sj:ObservedRepository ; sj:repositoryPath "#{subject}" .
    <file://#{seed}> a sj:ObservedRepository ; sj:repositoryPath "#{seed}" .
    <file://#{absent}> a sj:ObservedRepository ; sj:repositoryPath "#{absent}" .
    """)

    %{
      tmp: tmp,
      registry: registry,
      seed: seed,
      subject: subject,
      linked: linked,
      absent: absent
    }
  end

  defp commit!(repo, env, file, content, message) do
    File.write!(Path.join(repo, file), content)
    git!(repo, env, ["add", file])
    git!(repo, env, ["commit", "-q", "-m", message])
  end

  defp git!(cwd, env, args) do
    {out, code} = System.cmd("git", args, cd: cwd, env: env, stderr_to_stdout: true)
    assert code == 0, "git #{Enum.join(args, " ")} failed (#{code}): #{out}"
    out
  end

  defp rev_parse(repo, rev) do
    {out, 0} = System.cmd("git", ["-C", repo, "rev-parse", rev])
    String.trim(out)
  end

  defp refs(graph, repo_path) do
    graph
    |> Query.run("""
    #{@prefixes}
    SELECT ?name ?sha ?ahead ?behind ?unpushed ?ff WHERE {
      ?r a sj:RefObservation ;
         sj:refName ?name ;
         sj:observedSha ?sha ;
         sj:aheadCount ?ahead ;
         sj:behindCount ?behind ;
         sj:unpushed ?unpushed ;
         sj:fastForwardable ?ff ;
         prov:wasGeneratedBy ?a .
      ?a sj:repositoryPath "#{repo_path}" .
    }
    """)
    |> Map.new(fn row ->
      {row["name"],
       %{
         sha: row["sha"],
         ahead: row["ahead"],
         behind: row["behind"],
         unpushed: row["unpushed"],
         ff: row["ff"]
       }}
    end)
  end

  defp ended_lines(text) do
    text |> String.split("\n") |> Enum.filter(&String.contains?(&1, "prov:endedAtTime"))
  end

  defp strip_ended(text) do
    text |> String.split("\n") |> Enum.reject(&String.contains?(&1, "prov:endedAtTime"))
  end
end
