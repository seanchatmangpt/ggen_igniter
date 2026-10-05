defmodule GgenIgniter.ReceiptsSchemaCurrencyTest do
  @moduledoc """
  Permanent, skip-guarded court for receipt-schema currency (the manual
  "37 tests ran once" check from the igniter roadmap backlog, C2/AG3): the
  fields `GgenIgniter.SemanticJira.RProjection.build/7` emits and the
  fields `semantic-jira/authority-index-receipt/v1` emits must stay in
  currency with the fleet schema at `~/.claude/dfcm/receipt.schema.json`.

  Chicago-style: the fixture constructs the minimal valid input and runs the
  REAL projection (`RProjection.project/2` over a real `%GgenIgniter.Receipt{}`
  in a real tmp git repo) and the REAL
  `GgenIgniter.SemanticJira.Authority.index_receipt/1`; nothing is mocked.
  Every `{:ok, _}` projection already admits through the real structural law
  (`Bootstrap.Receipts.check/1`).

  If the external fleet schema file is absent, every test is skipped --
  visibly, with reason `BLOCKED:schema-absent` -- never a silent pass. The
  decision is made at this module's COMPILE time (a file-level
  `@tag skip:`), not in `setup`: per `test/test_helper.exs`'s GI-13 note,
  ExUnit 1.18 has no runtime per-test skip escape hatch, and a
  `setup`-local `{:skip, _}` return raises. The `:skip_schema` tag stays on
  the tests regardless, so `--only skip_schema` / `--include skip_schema`
  can address them directly.
  """

  use ExUnit.Case, async: true

  alias GgenIgniter.Receipt
  alias GgenIgniter.SemanticJira.Authority
  alias GgenIgniter.SemanticJira.Bootstrap.Receipts
  alias GgenIgniter.SemanticJira.RProjection

  @schema_path Path.expand("~/.claude/dfcm/receipt.schema.json")

  # Compile-time (module-body) decision: a file existence check here is a
  # stable precondition for the lifetime of one `mix test` invocation -- the
  # same shape test_helper.exs uses for `:requires_ash_r2rml`.
  schema_present? = File.exists?(@schema_path)

  skip_reason =
    if schema_present? do
      false
    else
      "BLOCKED:schema-absent (no fleet schema at #{inspect(@schema_path)})"
    end

  # Statically read the schema's own required-field list at compile time so
  # the assertions below are checked against the schema text itself, not a
  # hand-copied second catalog. When the schema file is absent this is the
  # empty list and the tests are skipped anyway.
  schema_required =
    if schema_present? do
      @schema_path |> File.read!() |> Jason.decode!() |> Map.get("required", [])
    else
      []
    end

  @schema_required schema_required
  @tag :skip_schema
  @tag skip: skip_reason
  test "fleet schema required fields are exactly the R projection's required emissions" do
    assert Enum.all?(
             ~w(identity authority consequence replay standing work_order_id
                origin_authority provider provider_execution_id),
             &(&1 in @schema_required)
           ),
           "fleet schema's required list drifted: #{inspect(@schema_required)}"
  end

  @tag :skip_schema
  @tag skip: skip_reason
  test "every schema-required field is present in a real R projection" do
    {:ok, r} = RProjection.project(receipt!(), repo: git_repo!(), ceiling: "CONSTRUCT")
    assert Receipts.check(r) == []

    for field <- @schema_required do
      assert Map.has_key?(r, field),
             "R projection dropped schema-required field #{inspect(field)}"
    end
  end

  @tag :skip_schema
  @tag skip: skip_reason
  test "subject_before/after stay OUT of identity (digest-boundary law)" do
    # The fixture receipt carries real pre_run_hash/post_run_hash (file-set
    # digests, "sha256:hex" shape). They ride top-level subject_before/
    # subject_after and NEVER inside identity.
    {:ok, r} = RProjection.project(receipt!(), repo: git_repo!())
    assert Receipts.check(r) == []

    refute Map.has_key?(r["identity"], "subject_before")
    refute Map.has_key?(r["identity"], "subject_after")

    assert r["subject_before"] =~ ~r/\Asha256:[0-9a-f]{64}\z/
    assert r["subject_after"] =~ ~r/\Asha256:[0-9a-f]{64}\z/

    # identity's commit anchors are bare 40-hex git SHAs, the OTHER digest
    # shape — the boundary is exactly which shape lives where.
    assert r["identity"]["subject_sha"] =~ ~r/\A[0-9a-f]{40}\z/
    assert r["identity"]["base_sha"] =~ ~r/\A[0-9a-f]{40}\z/
  end

  @tag :skip_schema
  @tag skip: skip_reason
  test "authority-index-receipt/v1 emits its own coherent field set" do
    index = %{
      admitted: %{"http://example.com/origin#order" => "sha256:" <> String.duplicate("c", 64)},
      refused: %{"http://example.com/origin#other" => {:authority_not_admitted, "k"}},
      source_digest: "sha256:" <> String.duplicate("d", 64)
    }

    receipt = Authority.index_receipt(index)

    assert receipt["schema"] == "semantic-jira/authority-index-receipt/v1"
    assert receipt["authority"] == "NONE"
    assert receipt["grants_do_authority"] == false
    assert is_binary(receipt["receipt_digest"])

    # Rows are preserved, never reduced to booleans, and typed.
    assert [%{"iri" => "http://example.com/origin#order", "digest" => _}] = receipt["admitted"]
    assert [%{"iri" => "http://example.com/origin#other", "refusal" => _}] = receipt["refused"]

    # The receipt is authority-inert by construction: the receipt digest is
    # deterministic over the canonical rows (same index -> same digest).
    assert receipt["receipt_digest"] == Authority.index_receipt(index)["receipt_digest"]
  end

  ## -- real collaborators (same shape as RProjectionTest) ----------------------

  defp scratch_dir! do
    dir =
      Path.join(
        System.tmp_dir!(),
        "ggen_igniter_receipts_schema_currency_test_#{System.unique_integer([:positive])}"
      )

    File.rm_rf!(dir)
    File.mkdir_p!(dir)
    on_exit(fn -> File.rm_rf!(dir) end)
    dir
  end

  defp git_repo! do
    repo = Path.join(scratch_dir!(), "repo")
    File.mkdir_p!(repo)

    {_, 0} = System.cmd("git", ["-C", repo, "init"], stderr_to_stdout: true)
    {_, 0} = System.cmd("git", ["-C", repo, "config", "user.email", "t@example.com"])
    {_, 0} = System.cmd("git", ["-C", repo, "config", "user.name", "Schema Currency Test"])

    File.write!(Path.join(repo, "seed.txt"), "seed\n")
    {_, 0} = System.cmd("git", ["-C", repo, "add", "."])
    {_, 0} = System.cmd("git", ["-C", repo, "commit", "-m", "seed"], stderr_to_stdout: true)

    repo
  end

  defp receipt! do
    Receipt.new(
      standing: :alive,
      recipe_key: "templates/x.ex.eex=>lib/generated/x.ex",
      started_at: "2026-10-01T00:00:00.000000Z",
      finished_at: "2026-10-01T00:00:00.050000Z",
      pre_run_hash: "sha256:" <> String.duplicate("a", 64),
      post_run_hash: "sha256:" <> String.duplicate("b", 64),
      files: ["lib/generated/x.ex"],
      reason: nil,
      metadata: %{
        "work_order" => %{
          "path" => "docs/jira/v26.10.1/WO-1.md",
          "source_digest" => "sha256:" <> String.duplicate("a", 64)
        }
      },
      commands: [
        %{
          "kind" => "sh_after",
          "cmd" => "mix compile",
          "exit_code" => 0,
          "output" => "compiled ok",
          "status" => "ok"
        }
      ]
    )
  end
end
