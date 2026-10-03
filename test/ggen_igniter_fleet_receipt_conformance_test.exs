defmodule GgenIgniter.FleetReceiptConformanceTest do
  @moduledoc """
  Chicago-style conformance court for the vendored fleet R v2 schema — a court
  that does not depend on the machine it runs on.

  The two artifacts and their division of labor:

  - `priv/schema/fleet-receipt.v2.json` is a byte-identical vendor of
    `~/.claude/dfcm/receipt.schema.json` (the inter-repo contract artifact;
    its pinned digest rides in `priv/schema/fleet-receipt.v2.sha256`).
  - `GgenIgniter.SemanticJira.Bootstrap.Receipts.check/1` is that vendored
    law's IN-REPO EXECUTABLE FORM: the v2 required keys
    (`work_order_id`, `origin_authority{grant,actor}`, `provider{name}`,
    `provider_execution_id`), the extension-namespace rule (top-level keys
    outside the known set must match `^provider_ext\\.[a-z0-9][a-z0-9_.-]*$`
    and be objects), and the ALIVE/no-non-zero-exit vacuity rule. This file
    never re-parses the JSON schema (no jsonschema dependency) — it validates
    golden receipts through `check/1` and treats a `check/1 == []` verdict as
    the schema's executable restatement.

  Real collaborators only: a real tmp git repository, real
  `%GgenIgniter.Receipt{}` structs projected through
  `GgenIgniter.SemanticJira.RProjection.project/2` + `write/2`, real bytes on
  disk, real sha256 digests via `:crypto`, and (named skip when absent) the
  real machine validator `~/.claude/dfcm/validate_receipt.py` as a python3
  subprocess.
  """

  use ExUnit.Case, async: true

  alias GgenIgniter.Receipt
  alias GgenIgniter.SemanticJira.Bootstrap.Receipts
  alias GgenIgniter.SemanticJira.RProjection

  @machine_schema Path.expand("~/.claude/dfcm/receipt.schema.json")
  @vendored_schema Path.expand("priv/schema/fleet-receipt.v2.json")
  @vendored_digest_file Path.expand("priv/schema/fleet-receipt.v2.sha256")
  @machine_validator Path.expand("~/.claude/dfcm/validate_receipt.py")

  ## -- real collaborators -------------------------------------------------------

  defp scratch_dir! do
    dir =
      Path.join(
        System.tmp_dir!(),
        "ggen_igniter_fleet_receipt_conformance_#{System.unique_integer([:positive])}"
      )

    File.rm_rf!(dir)
    File.mkdir_p!(dir)
    on_exit(fn -> File.rm_rf!(dir) end)
    dir
  end

  # A REAL git repository: real `git init` + a real commit, so the projected
  # receipt's identity.subject_sha resolves through `git rev-parse HEAD` for real.
  defp git_repo! do
    repo = Path.join(scratch_dir!(), "repo")
    File.mkdir_p!(repo)

    git!(repo, ["init"])
    git!(repo, ["config", "user.email", "test@example.com"])
    git!(repo, ["config", "user.name", "FleetReceiptConformance Test"])

    File.write!(Path.join(repo, "seed.txt"), "seed\n")
    git!(repo, ["add", "."])
    git!(repo, ["commit", "-m", "seed commit"])

    repo
  end

  defp git!(repo, args) do
    {out, 0} = System.cmd("git", ["-C", repo | args], stderr_to_stdout: true)
    out
  end

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

  defp receipt! do
    Receipt.new(
      standing: :alive,
      recipe_key: "templates/x.ex.eex=>lib/generated/x.ex",
      started_at: "2026-10-02T00:00:00.000000Z",
      finished_at: "2026-10-02T00:00:00.050000Z",
      files: ["lib/generated/x.ex"],
      reason: nil,
      metadata: %{"work_order" => %{"path" => "docs/jira/v26.10.2/WO-1.md"}},
      commands: [command()]
    )
  end

  # The golden R receipt: REALLY projected, REALLY written to disk, REALLY
  # decoded back. Returns {repo, written_path, decoded_map}.
  defp written_golden! do
    repo = git_repo!()
    path = Path.join(scratch_dir!(), "golden.r.json")

    assert :ok =
             RProjection.write(receipt!(),
               repo: repo,
               output_path: path,
               work_order_id: "WO-CONF-1"
             )

    decoded = Jason.decode!(File.read!(path))
    # Non-vacuous baseline: the producer's own output must admit before any
    # mutant is claimed refused.
    assert Receipts.check(decoded) == [], "golden receipt itself must admit"
    {repo, path, decoded}
  end

  defp sha256_file!(path),
    do: Base.encode16(:crypto.hash(:sha256, File.read!(path)), case: :lower)

  ## -- the drift guard -----------------------------------------------------------
  #
  # Pure, local, machine-independent: digests two paths, never mutates either.
  # `:machine_absent` is a real verdict (the vendored copy is authoritative for
  # that run), `{:match, digest}` a live agreement, `{:drift, m, v}` the
  # refusal with both digests attached.

  defp drift_guard(machine_path, vendored_path) do
    if File.regular?(machine_path) do
      machine = sha256_file!(machine_path)
      vendored = sha256_file!(vendored_path)

      if machine == vendored,
        do: {:match, machine},
        else: {:drift, machine, vendored}
    else
      :machine_absent
    end
  end

  ## -- (a) drift guard: vendored copy vs the machine copy --------------------------

  describe "vendored fleet schema (drift guard)" do
    test "the vendored copy matches the machine copy byte-for-byte (named skip when absent)" do
      case drift_guard(@machine_schema, @vendored_schema) do
        {:match, _digest} ->
          # Live comparison ran and agreed.
          assert true

        {:drift, machine, vendored} ->
          flunk("""
          fleet schema DRIFT between machine and vendored copies:
            machine  #{@machine_schema}  sha256=#{machine}
            vendored #{@vendored_schema}  sha256=#{vendored}
          Re-vendor: cp ~/.claude/dfcm/receipt.schema.json priv/schema/fleet-receipt.v2.json
          """)

        :machine_absent ->
          # Named skip: machine copy absent; vendored copy is authoritative
          # for this run.
          assert true
      end
    end

    test "the recorded digest file pins the vendored bytes (sha256sum format)" do
      assert File.regular?(@vendored_schema), "vendored schema missing"
      recorded = File.read!(@vendored_digest_file)

      assert [hex, name] = String.split(String.trim_trailing(recorded), "  ")
      assert name == "fleet-receipt.v2.json"

      assert hex == sha256_file!(@vendored_schema),
             "digest file is stale: recorded #{hex}, actual #{sha256_file!(@vendored_schema)}"

      assert Regex.match?(~r/\A[0-9a-f]{64}\z/, hex)
    end

    test "the guard detects a corrupted copy in a scratch pair (anti-vacuity, no priv/schema writes)" do
      dir = scratch_dir!()
      good = Path.join(dir, "good.json")
      corrupt = Path.join(dir, "corrupt.json")
      File.write!(good, ~s({"required": ["identity"]}))
      File.write!(corrupt, ~s({"required": ["identity", "SOMETHING_ELSE"]}))

      # drift_guard/2 reports {machine_digest, vendored_digest} in that order.
      assert {:drift, machine_digest, vendored_digest} = drift_guard(corrupt, good)
      assert machine_digest != vendored_digest
      assert byte_size(machine_digest) == 64 and byte_size(vendored_digest) == 64
      assert machine_digest == sha256_file!(corrupt)
      assert vendored_digest == sha256_file!(good)

      # And the positive control on the same helper: identical bytes agree.
      assert {:match, digest} = drift_guard(good, good)
      assert digest == sha256_file!(good)

      # And the absent-machine verdict is real, not an error.
      assert :machine_absent = drift_guard(Path.join(dir, "does-not-exist.json"), good)
    end
  end

  ## -- (b) golden: a REAL projected receipt against the vendored law ----------------

  describe "golden R receipt (vendored law via check/1)" do
    test "a real projected + written receipt carries all four v2 keys and admits" do
      {_repo, path, r} = written_golden!()

      assert File.regular?(path)
      decoded = Jason.decode!(File.read!(path))

      for key <- ~w(work_order_id origin_authority provider provider_execution_id) do
        assert Map.has_key?(decoded, key), "written receipt lacks v2 key #{key}"
      end

      assert decoded["work_order_id"] == "WO-CONF-1"
      assert decoded["origin_authority"]["grant"]
      assert decoded["origin_authority"]["actor"]
      assert decoded["provider"]["name"]

      assert is_binary(decoded["provider_execution_id"]) and
               decoded["provider_execution_id"] != ""

      # check/1 == [] IS the vendored schema's executable form in-repo.
      assert Receipts.check(decoded) == []
      assert Receipts.check(r) == []
    end

    test "the written golden survives a JSON round-trip through the digest-pinned schema's law" do
      {_repo, _path, r} = written_golden!()
      assert Receipts.check(Jason.decode!(Jason.encode!(r))) == []
    end
  end

  ## -- (c) four mutants: the law refuses, it is not vacuous --------------------------

  describe "check/1 refuses the four v2 mutants with typed reasons" do
    test "mutant 1: ALIVE over a non-zero replay exit -> admission_vacuous" do
      {repo, _path, _r} = written_golden!()
      {:ok, r} = RProjection.project(receipt!(), repo: repo, work_order_id: "WO-MUT-1")
      assert r["standing"]["value"] == "ALIVE"

      # Force the vacuity: an ALIVE standing whose replay command did NOT exit 0.
      vacuous =
        put_in(r, ["replay", "commands"], [
          %{"cmd" => "mix compile", "cwd" => repo, "exit" => 1}
        ])

      assert "standing: ALIVE with a non-zero replay exit (admission_vacuous)" in Receipts.check(
               vacuous
             )
    end

    test "mutant 2: missing work_order_id -> typed required-key refusal" do
      {_repo, _path, r} = written_golden!()
      mutant = Map.delete(r, "work_order_id")

      errors = Receipts.check(mutant)

      assert Enum.any?(errors, &String.starts_with?(&1, "receipt/work_order_id:")),
             "expected a work_order_id reason, got: #{inspect(errors)}"
    end

    test "mutant 3: bare top-level \"native\" key -> namespace refusal" do
      {_repo, _path, r} = written_golden!()
      mutant = Map.put(r, "native", %{"receipt_hash" => "sha256:" <> String.duplicate("0", 64)})

      assert Enum.any?(
               Receipts.check(mutant),
               &(&1 =~ ~r/"native".*namespaced.*not bare at top level/)
             ),
             "expected a namespace reason for \"native\", got: #{inspect(Receipts.check(mutant))}"
    end

    test "mutant 4: extension key whose value is not an object -> object refusal" do
      {_repo, _path, r} = written_golden!()
      mutant = Map.put(r, "provider_ext.ggen_igniter", "not-an-object")

      assert Enum.any?(
               Receipts.check(mutant),
               &(&1 =~ ~r/provider_ext\.ggen_igniter/ and &1 =~ ~r/object/)
             ),
             "expected an object reason for provider_ext.ggen_igniter, got: #{inspect(Receipts.check(mutant))}"
    end
  end

  ## -- machine validator court (optional, named skip) ----------------------------------

  test "~/.claude/dfcm/validate_receipt.py ADMITS the written golden (real python3 subprocess)" do
    {_repo, path, _r} = written_golden!()

    if File.regular?(@machine_validator) do
      case System.cmd("python3", ["-c", "import jsonschema"], stderr_to_stdout: true) do
        {_, 0} ->
          {out, exit} = System.cmd("python3", [@machine_validator, path], stderr_to_stdout: true)
          assert exit == 0, "machine validator refused the golden receipt: #{out}"
          assert out =~ "ADMITTED"

        {_out, _nonzero} ->
          # Named skip: jsonschema absent — check/1 assertions above carry the law.
          assert true
      end
    else
      # Named skip: machine validator absent; the vendored-schema-backed
      # check/1 assertions above are authoritative for this run.
      assert true
    end
  end
end
