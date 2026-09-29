defmodule GgenIgniter.TaskContractTest do
  @moduledoc """
  Chicago-style: pure state-based assertions over the real `GgenIgniter.TaskContract` module
  and the real `docs/reference/cli/exit-codes.md` file on disk (no doubles anywhere).
  """
  use ExUnit.Case, async: true

  alias GgenIgniter.TaskContract

  test "envelope has exactly the documented keys" do
    env = TaskContract.envelope("sync", :ok, data: %{"a" => 1})

    assert Map.keys(env) |> Enum.sort() ==
             ~w(data exit_code ok refusal schema_version standing task)

    assert env["schema_version"] == 1
    assert env["ok"] == true
    assert env["exit_code"] == 0
    assert env["refusal"] == nil
  end

  test "refusal is {code, detail} with an uppercased code" do
    env = TaskContract.envelope("sync", :refusal, refusal: {:pack_digest_mismatch, "x != y"})
    assert env["refusal"] == %{"code" => "PACK_DIGEST_MISMATCH", "detail" => "x != y"}
    assert env["exit_code"] == 1
    assert env["ok"] == false

    assert TaskContract.refusal_text({:pack_digest_mismatch, "x != y"}) ==
             "REFUSED:PACK_DIGEST_MISMATCH x != y"
  end

  test "encode is deterministic and key-sorted regardless of insertion order" do
    a =
      TaskContract.envelope("t", :drift,
        data: %{"z" => 1, "a" => %{"y" => 2, "b" => [%{"q" => 1, "c" => 2}]}}
      )

    b =
      TaskContract.envelope("t", :drift,
        data: %{"a" => %{"b" => [%{"c" => 2, "q" => 1}], "y" => 2}, "z" => 1}
      )

    assert TaskContract.encode(a) == TaskContract.encode(b)
    json = TaskContract.encode(a)
    assert json =~ ~s("data":{"a":{"b":[{"c":2,"q":1}],"y":2},"z":1})
    assert Jason.decode!(json) == a
    # top-level keys are sorted too
    assert String.starts_with?(json, ~s({"data":))
  end

  test "exit-code table is 0..4, unique, and each name maps to its code" do
    assert TaskContract.documented_codes() == [0, 1, 2, 3, 4]
    names = Enum.map(TaskContract.exit_codes(), & &1.name)
    assert names == [:ok, :refusal, :invocation, :unsupported, :drift]
    assert TaskContract.exit_code(:drift) == 4

    assert_raise ArgumentError, fn -> TaskContract.exit_code(:nope) end
  end

  test "docs/reference/cli/exit-codes.md documents every code in the table" do
    doc = File.read!("docs/reference/cli/exit-codes.md")

    for %{code: code, name: name} <- TaskContract.exit_codes() do
      assert doc =~ ~r/\|\s*#{code}\s*\|/,
             "exit code #{code} (#{name}) missing from exit-codes.md"
    end
  end
end
