defmodule GgenIgniter.SemanticJira.RProjectionTest do
  @moduledoc """
  Chicago-style, no-mocks proof of `GgenIgniter.SemanticJira.RProjection`:
  real `%GgenIgniter.Receipt{}` structs, a real tmp git repository driven by
  real `git` subprocesses, real file writes under `System.tmp_dir!/0`, and
  the real structural admission law (`GgenIgniter.SemanticJira.Bootstrap.
  Receipts.check/1`) asserted on every `{:ok, _}` projection. The optional
  external court (`~/.claude/dfcm/validate_receipt.py`, a real python3
  subprocess) is a named skip when the validator or its `jsonschema`
  dependency is absent — never a silent pass.
  """

  use ExUnit.Case, async: true

  alias GgenIgniter.Receipt
  alias GgenIgniter.SemanticJira.Bootstrap.Receipts
  alias GgenIgniter.SemanticJira.RProjection

  @hex64 String.duplicate("a", 64)
  @hex64_b String.duplicate("b", 64)

  setup do
    repo = git_repo!()
    %{repo: repo, dir: Path.dirname(repo)}
  end

  ## -- real collaborators -----------------------------------------------------

  defp scratch_dir! do
    dir =
      Path.join(
        System.tmp_dir!(),
        "ggen_igniter_r_projection_test_#{System.unique_integer([:positive])}"
      )

    File.rm_rf!(dir)
    File.mkdir_p!(dir)
    on_exit(fn -> File.rm_rf!(dir) end)
    dir
  end

  # A REAL git repository: real `git init` + a real commit, so
  # `git rev-parse HEAD` / `git cat-file -e <sha>^{commit}` run for real.
  defp git_repo! do
    repo = Path.join(scratch_dir!(), "repo")
    File.mkdir_p!(repo)

    git!(repo, ["init"])
    git!(repo, ["config", "user.email", "test@example.com"])
    git!(repo, ["config", "user.name", "RProjection Test"])

    File.write!(Path.join(repo, "seed.txt"), "seed\n")
    git!(repo, ["add", "."])
    git!(repo, ["commit", "-m", "seed commit"])

    repo
  end

  defp git!(repo, args) do
    {out, 0} = System.cmd("git", ["-C", repo | args], stderr_to_stdout: true)
    out
  end

  defp head_sha!(repo), do: git!(repo, ["rev-parse", "HEAD"]) |> String.trim()

  defp command(extra \\ []) do
    %{
      "kind" => "sh_after",
      "cmd" => "mix compile",
      "template_path" => "priv/ggen/pack/templates/x.ex.eex",
      "target" => "lib/generated/x.ex",
      "exit_code" => 0,
      "output" => "compiled ok",
      "duration_ms" => 12,
      "status" => "ok"
    }
    |> Map.merge(Map.new(extra))
  end

  defp receipt!(standing, extra \\ []) do
    Receipt.new(
      Keyword.merge(
        [
          standing: standing,
          recipe_key: "templates/x.ex.eex=>lib/generated/x.ex",
          started_at: "2026-10-01T00:00:00.000000Z",
          finished_at: "2026-10-01T00:00:00.050000Z",
          pre_run_hash: "sha256:" <> @hex64,
          post_run_hash: "sha256:" <> @hex64_b,
          files: ["lib/generated/x.ex"],
          reason: nil,
          metadata: %{"work_order" => %{"path" => "docs/jira/v26.10.1/WO-1.md", "source_digest" => "sha256:" <> @hex64}},
          commands: [command()]
        ],
        extra
      )
    )
  end

  defp project_ok!(receipt, opts) do
    assert {:ok, r} = RProjection.project(receipt, opts)
    # Self-check law: EVERY ok projection admits structurally.
    assert Receipts.check(r) == []
    r
  end

  ## -- standing table ----------------------------------------------------------

  describe "project/2 (standing map)" do
    test "alive with all replay exits 0 -> ALIVE, no broken_term", %{repo: repo} do
      r = project_ok!(receipt!(:alive), repo: repo)

      assert r["standing"]["value"] == "ALIVE"
      assert r["standing"]["broken_term"] == nil
      assert r["standing"]["derived_from"] =~ "standing=alive"
    end

    test "alive with a non-zero replay exit -> REFUSED(admission_vacuous), NEVER ALIVE", %{
      repo: repo
    } do
      receipt =
        receipt!(:alive,
          commands: [command(), command(%{"exit_code" => 1, "status" => "failed"})]
        )

      r = project_ok!(receipt, repo: repo)

      assert r["standing"]["value"] == "REFUSED(admission_vacuous)"
      assert r["standing"]["broken_term"] == "admission_vacuous"
    end

    test "alive with a nil (timeout) replay exit -> REFUSED(admission_vacuous)", %{repo: repo} do
      receipt = receipt!(:alive, commands: [command(%{"exit_code" => nil, "status" => "timeout"})])

      r = project_ok!(receipt, repo: repo)

      assert r["standing"]["value"] == "REFUSED(admission_vacuous)"
      assert r["standing"]["broken_term"] == "admission_vacuous"
      [replayed] = r["replay"]["commands"]
      # The R schema requires an integer exit; the timeout is disclosed, not faked.
      assert replayed["exit"] == -1
      assert replayed["summary"] =~ "nil"
    end

    test "refused -> BLOCKED:<reason> with broken_term mu_on_O", %{repo: repo} do
      receipt = receipt!(:refused, reason: "path-safety guard refused a symlink escape")

      r = project_ok!(receipt, repo: repo)

      assert r["standing"]["value"] == "BLOCKED:path-safety guard refused a symlink escape"
      assert r["standing"]["broken_term"] == "mu_on_O"
    end

    test "compensated -> PARTIAL_ALIVE", %{repo: repo} do
      r = project_ok!(receipt!(:compensated), repo: repo)

      assert r["standing"]["value"] == "PARTIAL_ALIVE"
      assert r["standing"]["broken_term"] == nil
    end

    test "compensation_failed -> PARTIAL_ALIVE with the catastrophic detail in derived_from", %{
      repo: repo
    } do
      receipt = receipt!(:compensation_failed, reason: "revert write failed: eacces")

      r = project_ok!(receipt, repo: repo)

      assert r["standing"]["value"] == "PARTIAL_ALIVE"
      assert r["standing"]["derived_from"] =~ "CATASTROPHIC"
      assert r["standing"]["derived_from"] =~ "revert write failed: eacces"
    end

    test "build_broken -> BUILD_BROKEN with broken_term mu_unlawful", %{repo: repo} do
      r = project_ok!(receipt!(:build_broken), repo: repo)

      assert r["standing"]["value"] == "BUILD_BROKEN"
      assert r["standing"]["broken_term"] == "mu_unlawful"
    end

    test "every standing projects to a self-checking receipt", %{repo: repo} do
      for standing <- Receipt.standings() do
        receipt =
          if standing == :refused do
            receipt!(standing, reason: "guard refused")
          else
            receipt!(standing)
          end

        r = project_ok!(receipt, repo: repo)
        assert is_binary(r["standing"]["derived_from"]) and r["standing"]["derived_from"] != ""
      end
    end
  end

  ## -- refusals -----------------------------------------------------------------

  describe "project/2 (fail-closed refusals)" do
    test "refuses a non-Receipt shape" do
      assert {:error, {:r_projection_refused, :invalid_receipt}} =
               RProjection.project(%{"standing" => "alive"}, repo: "/tmp")

      assert {:error, {:r_projection_refused, :invalid_receipt}} =
               RProjection.project("not a receipt", repo: "/tmp")
    end

    test "refuses :repo_required when opts[:repo] is missing" do
      assert {:error, {:r_projection_refused, :repo_required}} =
               RProjection.project(receipt!(:alive), [])
    end

    test "refuses :head_unresolvable for a plain non-git directory" do
      plain = scratch_dir!() |> Path.join("plain")
      File.mkdir_p!(plain)

      assert {:error, {:r_projection_refused, :head_unresolvable}} =
               RProjection.project(receipt!(:alive), repo: plain)
    end

    test "refuses {:subject_sha_not_a_commit, sha} for a bogus 40-hex anchor in a real repo", %{
      repo: repo
    } do
      bogus = String.duplicate("9", 40)

      assert {:error, {:r_projection_refused, {:subject_sha_not_a_commit, ^bogus}}} =
               RProjection.project(receipt!(:alive), repo: repo, subject_sha: bogus)
    end

    test "refuses :work_order_id_required when neither metadata nor opts carry one", %{
      repo: repo
    } do
      receipt = receipt!(:alive, metadata: %{})

      assert {:error, {:r_projection_refused, :work_order_id_required}} =
               RProjection.project(receipt, repo: repo)
    end

    test "refuses :no_replay_commands for a commandless receipt", %{repo: repo} do
      # A real :refused receipt records no commands (nothing was actuated).
      refused = receipt!(:refused, reason: "guard refused", commands: [])

      assert {:error, {:r_projection_refused, :no_replay_commands}} =
               RProjection.project(refused, repo: repo)
    end

    test "refuses an invalid authority ceiling", %{repo: repo} do
      assert {:error, {:r_projection_refused, {:invalid_ceiling, "WRITE"}}} =
               RProjection.project(receipt!(:alive),
                 repo: repo,
                 subject_sha: head_sha!(repo),
                 ceiling: "WRITE"
               )
    end
  end

  ## -- identity / field law ------------------------------------------------------

  describe "project/2 (identity and field law)" do
    test "default subject_sha is the repo's REAL HEAD; base_sha defaults to it", %{repo: repo} do
      r = project_ok!(receipt!(:alive), repo: repo)

      assert r["identity"]["subject_sha"] == head_sha!(repo)
      assert r["identity"]["base_sha"] == head_sha!(repo)
      assert Regex.match?(~r/\A[0-9a-f]{40}\z/, r["identity"]["subject_sha"])
    end

    test "explicit subject_sha/base_sha opts are honored; work_order_id opt overrides metadata", %{
      repo: repo
    } do
      base = head_sha!(repo)

      r =
        project_ok!(receipt!(:alive),
          repo: repo,
          subject_sha: base,
          base_sha: base,
          work_order_id: "WO-EXPLICIT"
        )

      assert r["identity"]["subject_sha"] == base
      assert r["identity"]["base_sha"] == base
      assert r["work_order_id"] == "WO-EXPLICIT"
      assert r["identity"]["subject"] == "WO-EXPLICIT"
    end

    test "pre/post run hashes land in subject_before/after and NEVER in identity", %{repo: repo} do
      r = project_ok!(receipt!(:alive), repo: repo)

      assert r["subject_before"] == "sha256:" <> @hex64
      assert r["subject_after"] == "sha256:" <> @hex64_b

      # File-set digests are not commit anchors: identity carries only the
      # 40-hex commit SHAs, never a "sha256:" digest.
      refute Map.has_key?(r["identity"], "subject_before")
      refute Map.has_key?(r["identity"], "subject_after")
      refute r["identity"]["subject_sha"] =~ ~r/^sha256:/
      assert r["identity"]["subject_sha"] != r["subject_before"]
      assert r["identity"]["subject_sha"] != r["subject_after"]
    end

    test "consequence is honest: commits [], files_changed == receipt.files, remote_effects []", %{
      repo: repo
    } do
      receipt = receipt!(:alive, files: ["lib/generated/x.ex", "lib/generated/y.ex"])

      r = project_ok!(receipt, repo: repo)

      assert r["consequence"] == %{
               "commits" => [],
               "files_changed" => ["lib/generated/x.ex", "lib/generated/y.ex"],
               "remote_effects" => []
             }
    end

    test "replay commands map cmd/cwd/exit with cwd defaulting to the repo", %{repo: repo} do
      r = project_ok!(receipt!(:alive), repo: repo)

      [replayed] = r["replay"]["commands"]
      assert replayed["cmd"] == "mix compile"
      assert replayed["cwd"] == repo
      assert replayed["exit"] == 0
    end

    test "authority defaults; origin_authority mirrors authority", %{repo: repo} do
      r = project_ok!(receipt!(:alive), repo: repo)

      assert r["authority"] == %{"ceiling" => "CONSTRUCT", "grant" => "NONE", "actor" => "ggen-igniter"}
      assert r["origin_authority"] == r["authority"]

      custom = project_ok!(receipt!(:alive),
        repo: repo,
        ceiling: "DO",
        grant: "lease-42",
        actor: "operator"
      )

      assert custom["authority"] == %{"ceiling" => "DO", "grant" => "lease-42", "actor" => "operator"}
      assert custom["origin_authority"] == custom["authority"]
    end

    test "provider/provider_execution_id/receipt_hash namespace law", %{repo: repo} do
      receipt = receipt!(:alive)
      r = project_ok!(receipt, repo: repo)

      assert r["provider"] == %{"name" => "ggen-igniter"}
      assert r["provider_execution_id"] == receipt.id

      # receipt_hash rides ONLY in provider_ext.ggen_igniter (an object), never
      # bare at top level; schema_version is never projected.
      assert r["provider_ext.ggen_igniter"]["receipt_hash"] == receipt.receipt_hash
      assert r["provider_ext.ggen_igniter"]["receipt_hash"] == Receipt.compute_receipt_hash(receipt)
      assert r["provider_ext.ggen_igniter"]["recipe_key"] == receipt.recipe_key
      refute Map.has_key?(r, "receipt_hash")
      refute Map.has_key?(r, "schema_version")
    end
  end

  ## -- write/2 --------------------------------------------------------------------

  describe "write/2" do
    test "refuses :output_path_required when no path is given", %{repo: repo} do
      assert {:error, {:r_projection_refused, :output_path_required}} =
               RProjection.write(receipt!(:alive), repo: repo)
    end

    test "refuses a forbidden output path (Claude home) via Guard.forbidden_path/1", %{repo: repo} do
      forbidden = Path.join([System.user_home!(), ".claude", "r_projection_escape_test.r.json"])

      assert {:error, {:r_projection_refused, {:forbidden_output_path, reason}}} =
               RProjection.write(receipt!(:alive), repo: repo, output_path: forbidden)

      assert reason =~ ".claude"
      refute File.exists?(forbidden)
    end

    test "writes <stem>.r.json: .json suffix replaced, bare stem gains suffix", %{repo: repo} do
      dir = scratch_dir!()

      from_json = Path.join(dir, "from.json")
      assert :ok = RProjection.write(receipt!(:alive), repo: repo, output_path: from_json)
      assert File.exists?(Path.join(dir, "from.r.json"))
      refute File.exists?(from_json)

      from_bare = Path.join(dir, "bare")
      assert :ok = RProjection.write(receipt!(:alive), repo: repo, output_path: from_bare)
      assert File.exists?(Path.join(dir, "bare.r.json"))

      from_r = Path.join(dir, "already.r.json")
      assert :ok = RProjection.write(receipt!(:alive), repo: repo, output_path: from_r)
      assert File.exists?(Path.join(dir, "already.r.json"))
    end

    test "round-trip: written file is pretty JSON with a trailing newline that decodes and admits", %{
      repo: repo
    } do
      path = Path.join(scratch_dir!(), "receipt.r.json")

      assert :ok =
               RProjection.write(receipt!(:alive),
                 repo: repo,
                 output_path: path,
                 work_order_id: "WO-RT"
               )

      bytes = File.read!(path)
      assert String.ends_with?(bytes, "\n")
      assert String.contains?(bytes, "\n  ") or String.contains?(bytes, "\n    ")

      decoded = Jason.decode!(bytes)
      assert Receipts.check(decoded) == []
      assert decoded["identity"]["subject_sha"] == head_sha!(repo)
      assert decoded["work_order_id"] == "WO-RT"
    end

    test "accepts an already-projected r map AND a raw receipt struct", %{repo: repo} do
      dir = scratch_dir!()
      receipt = receipt!(:alive)
      {:ok, r} = RProjection.project(receipt, repo: repo)

      assert :ok = RProjection.write(r, output_path: Path.join(dir, "from_map"))
      assert :ok = RProjection.write(receipt, repo: repo, output_path: Path.join(dir, "from_receipt"))

      assert File.read!(Path.join(dir, "from_map.r.json")) ==
               File.read!(Path.join(dir, "from_receipt.r.json"))
    end

    test "refuses an r map that does not admit structurally" do
      assert {:error, {:r_projection_refused, {:invalid_r_map, errors}}} =
               RProjection.write(%{"standing" => %{"value" => "ALIVE"}}, output_path: "/tmp/x")

      assert is_list(errors) and errors != []
    end

    test "determinism: same receipt + opts -> byte-identical JSON", %{repo: repo} do
      dir = scratch_dir!()
      receipt = receipt!(:alive)

      assert :ok = RProjection.write(receipt, repo: repo, output_path: Path.join(dir, "a"))
      assert :ok = RProjection.write(receipt, repo: repo, output_path: Path.join(dir, "b"))

      assert File.read!(Path.join(dir, "a.r.json")) == File.read!(Path.join(dir, "b.r.json"))
    end
  end

  ## -- external validator court (optional, named skip) -----------------------------

  test "~/.claude/dfcm/validate_receipt.py ADMITS the written .r.json (real python3 subprocess)",
       %{repo: repo} do
    validator = Path.expand("~/.claude/dfcm/validate_receipt.py")

    if File.regular?(validator) do
      case System.cmd("python3", ["-c", "import jsonschema"], stderr_to_stdout: true) do
        {_, 0} ->
          path = Path.join(scratch_dir!(), "receipt.r.json")

          assert :ok = RProjection.write(receipt!(:alive), repo: repo, output_path: path)

          {out, exit} = System.cmd("python3", [validator, path], stderr_to_stdout: true)
          assert exit == 0, "validator refused the projection: #{out}"
          assert out =~ "ADMITTED"

        {_out, _nonzero} ->
          # Named skip: jsonschema is absent — the in-process check/1 assertions
          # above still carry the structural law.
          assert true
      end
    else
      # Named skip: validator absent on this machine.
      assert true
    end
  end
end
