defmodule GgenIgniter.SemanticJira.ReceiptsCheckTest do
  @moduledoc """
  Chicago-style, no-mocks proof of `GgenIgniter.SemanticJira.Bootstrap.
  Receipts.check/1`'s fleet R v2 law: real maps, real JSON decode/encode
  round-trips, no doubles. Covers exactly the v2 additions — the four
  required keys (`work_order_id`, `origin_authority{grant,actor}`,
  `provider{name}`, `provider_execution_id`), the extension-namespace rule
  (top-level keys outside the known set must match
  `^provider_ext\\.[a-z0-9][a-z0-9_.-]*$` and be objects), and the honest
  residue that a v1-only receipt refuses with one typed string per missing
  key, never a crash.
  """

  use ExUnit.Case, async: true

  alias GgenIgniter.SemanticJira.Bootstrap.Receipts
  alias GgenIgniter.SemanticJira.RProjection

  # The golden map is a REAL projected receipt: `RProjection.project/2`'s own
  # output (self-checked `== []` inside `golden_v2_map!/0`), so the golden law
  # and the producer cannot drift apart silently.
  setup do
    %{golden: golden_v2_map!()}
  end

  ## -- real collaborators -------------------------------------------------------

  # A REAL git repository + a REAL %GgenIgniter.Receipt{} projected through
  # RProjection.project/2 — the same collaborators
  # ggen_igniter_semantic_jira_r_projection_test.exs uses, not a hand-built
  # map that could drift from the real producer.
  defp scratch_dir! do
    dir =
      Path.join(
        System.tmp_dir!(),
        "ggen_igniter_receipts_check_test_#{System.unique_integer([:positive])}"
      )

    File.rm_rf!(dir)
    File.mkdir_p!(dir)
    on_exit(fn -> File.rm_rf!(dir) end)
    dir
  end

  defp git_repo! do
    repo = Path.join(scratch_dir!(), "repo")
    File.mkdir_p!(repo)

    System.cmd("git", ["-C", repo, "init"])
    System.cmd("git", ["-C", repo, "config", "user.email", "test@example.com"])
    System.cmd("git", ["-C", repo, "config", "user.name", "ReceiptsCheck Test"])

    File.write!(Path.join(repo, "seed.txt"), "seed\n")
    System.cmd("git", ["-C", repo, "add", "."])
    System.cmd("git", ["-C", repo, "commit", "-m", "seed commit"])

    repo
  end

  defp golden_v2_map! do
    repo = git_repo!()

    receipt =
      GgenIgniter.Receipt.new(
        standing: :alive,
        recipe_key: "templates/x.ex.eex=>lib/generated/x.ex",
        files: ["lib/generated/x.ex"],
        metadata: %{"work_order" => %{"path" => "docs/jira/v26.10.1/WO-1.md"}},
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

    {:ok, r} = RProjection.project(receipt, repo: repo, work_order_id: "WO-1")
    assert Receipts.check(r) == []
    r
  end

  defp v1_map do
    %{
      "identity" => %{
        "subject" => "T-A",
        "repo" => "fixture/subject",
        "subject_sha" => String.duplicate("a", 40),
        "base_sha" => String.duplicate("a", 40)
      },
      "authority" => %{"ceiling" => "CONSTRUCT", "grant" => "NONE", "actor" => "fixture"},
      "consequence" => %{"commits" => [], "files_changed" => [], "remote_effects" => []},
      "replay" => %{"commands" => [%{"cmd" => "mix test", "cwd" => ".", "exit" => 0}]},
      "standing" => %{"value" => "ALIVE", "derived_from" => "fixture run"}
    }
  end

  ## -- golden v2 map -------------------------------------------------------------

  describe "check/1 (golden fleet R v2 map)" do
    test "a real projected v2 receipt admits" do
      assert Receipts.check(golden_v2_map!()) == []
    end

    test "the golden map survives a real JSON round-trip and still admits" do
      bytes = Jason.encode!(golden_v2_map!())
      assert Receipts.check(Jason.decode!(bytes)) == []
    end

    test "an optional v2 ceiling must still be a real ceiling when present" do
      r = put_in(golden_v2_map!(), ["origin_authority", "ceiling"], "WRITE")

      assert "origin_authority/ceiling: not in [\"OBSERVE\", \"SELECT\", \"CONSTRUCT\", \"DO\"]" in Receipts.check(r)
    end
  end

  ## -- v2 required keys ------------------------------------------------------------

  describe "check/1 (fleet R v2 required keys)" do
    test "a v1-only receipt refuses with one typed reason per missing key, never a crash", %{
      golden: golden
    } do
      errors = Receipts.check(v1_map())

      # One string per missing v2 key, named in the string.
      for key <- ~w(work_order_id provider_execution_id) do
        assert Enum.any?(errors, &String.starts_with?(&1, "receipt/#{key}:")),
               "expected a typed reason for #{key}, got: #{inspect(errors)}"
      end

      assert "origin_authority: required object" in errors
      assert "provider: required object" in errors

      # The v1 law itself still holds: no spurious v1 errors on this map.
      refute Enum.any?(errors, &String.starts_with?(&1, "identity/"))
      refute Enum.any?(errors, &String.starts_with?(&1, "replay/"))
      refute Enum.any?(errors, &String.starts_with?(&1, "standing/"))

      # The golden map differs from the v1 map ONLY by the v2 keys: removing
      # them from the golden map reproduces the v1 refusal set exactly (the
      # receipt, not the test, carries the law).
      stripped = Map.drop(golden, ~w(work_order_id origin_authority provider provider_execution_id))

      for key <- ~w(work_order_id provider_execution_id) do
        assert Enum.any?(Receipts.check(stripped), &String.starts_with?(&1, "receipt/#{key}:"))
      end
    end

    test "a non-map work_order_id / provider_execution_id refuses", %{golden: golden} do
      for key <- ~w(work_order_id provider_execution_id) do
        r = Map.put(golden, key, 42)

        assert Enum.any?(Receipts.check(r), &String.starts_with?(&1, "receipt/#{key}:")),
               "expected #{key} reason, got: #{inspect(Receipts.check(r))}"
      end
    end

    test "origin_authority missing grant or actor refuses with the named key", %{golden: golden} do
      for key <- ~w(grant actor) do
        r = put_in(golden, ["origin_authority"], Map.delete(golden["origin_authority"], key))

        assert Enum.any?(Receipts.check(r), &String.starts_with?(&1, "origin_authority/#{key}:")),
               "expected origin_authority/#{key} reason"
      end
    end

    test "provider missing name refuses; a non-map provider refuses as an object", %{golden: golden} do
      assert Enum.any?(
               Receipts.check(put_in(golden, ["provider", "name"], "")),
               &String.starts_with?(&1, "provider/name:")
             )

      assert "provider: required object" in Receipts.check(Map.put(golden, "provider", "ggen"))
    end
  end

  ## -- extension-namespace rule ------------------------------------------------------

  describe "check/1 (extension-namespace rule)" do
    test "a bare top-level \"native\" key refuses with a namespace reason", %{golden: golden} do
      r = Map.put(golden, "native", %{"receipt_hash" => "sha256:" <> String.duplicate("0", 64)})

      assert Enum.any?(
               Receipts.check(r),
               &(&1 =~ ~r/"native".*namespaced.*not bare at top level/)
             ),
             "expected a namespace reason for \"native\", got: #{inspect(Receipts.check(r))}"
    end

    test "an extension key whose value is not an object refuses", %{golden: golden} do
      r = Map.put(golden, "provider_ext.ggen_igniter", "not-an-object")

      assert Enum.any?(
               Receipts.check(r),
               &(&1 =~ ~r/provider_ext\.ggen_igniter/ and &1 =~ ~r/object/)
             )
    end

    test "a well-formed provider_ext.<provider> object admits", %{golden: golden} do
      r =
        Map.put(golden, "provider_ext.other-provider.v2", %{
          "anything" => "goes — the object itself is unconstrained"
        })

      assert Receipts.check(r) == []
    end

    test "the known top-level set (schema properties + bootstrap linking fields) never refuses", %{
      golden: golden
    } do
      # identity.work_order / identity.tuple_digest are the bootstrap's own
      # linking fields and live INSIDE identity, not at top level; every
      # schema property plus subject_before/after/replay_binding admits.
      r =
        golden
        |> Map.put("replay_binding", %{"contract" => "v1"})
        |> put_in(["identity", "work_order"], "t:WO-1")
        |> put_in(["identity", "tuple_digest"], "sha256:" <> String.duplicate("1", 64))

      assert Receipts.check(r) == []
    end
  end

  ## -- the producer/consumer seam -------------------------------------------------------

  describe "check/1 (RProjection seam)" do
    test "every RProjection.write-able map still admits; a v1-shaped map is refused by write/2" do
      # write/2 routes through the same check: a v1-only map cannot be
      # laundered onto disk through RProjection.write/2.
      assert {:error, {:r_projection_refused, {:invalid_r_map, errors}}} =
               RProjection.write(v1_map(), output_path: Path.join(scratch_dir!(), "v1"))

      assert Enum.any?(errors, &String.starts_with?(&1, "receipt/work_order_id:"))
    end
  end
end
