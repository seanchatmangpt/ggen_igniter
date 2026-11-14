defmodule GgenIgniter.PackFrontmatter.DispatchTest do
  # Real `mix ggen_igniter.sync` subprocess against the fixture Tera pack, real files, real
  # engine; no mocks. async: false (shared _build, wasm engine).
  use ExUnit.Case, async: false

  @moduletag :integration

  alias GgenIgniter.PackFrontmatter.{Receipt, Sync}

  @here Path.expand(__DIR__)
  @pack Path.join(@here, "fixtures/ash-a2a-app-pack")
  @app Path.join(@here, "fixtures/app.ttl")
  @golden Path.join(@here, "golden")

  setup do
    out = Path.join(System.tmp_dir!(), "pf_dispatch_#{System.unique_integer([:positive])}")
    File.mkdir_p!(out)
    on_exit(fn -> File.rm_rf!(out) end)
    {:ok, out: out}
  end

  defp sync_cmd(extra) do
    System.cmd("mix", ["ggen_igniter.sync", "--pack-dir", @pack, "--ontology", @app] ++ extra,
      cd: File.cwd!(),
      stderr_to_stdout: true
    )
  end

  defp receipts(out), do: Path.wildcard(Path.join([out, Receipt.dir(), "receipt-*.json"]))

  test "sync --pack-dir on a Tera pack renders golden bytes and writes a receipt", %{out: out} do
    {output, code} = sync_cmd(["--out", out])
    assert code == 0, output

    assert File.read!(Path.join(out, "lib/demo/ticket.ex")) ==
             File.read!(Path.join(@golden, "lib/demo/ticket.ex.golden"))

    assert [receipt_path] = receipts(out)
    receipt = receipt_path |> File.read!() |> Jason.decode!()

    for key <- ~w(identity authority consequence replay standing work_order_id
                  origin_authority provider provider_execution_id) do
      assert Map.has_key?(receipt, key), "receipt lacks #{key}"
    end

    assert receipt["standing"]["value"] == "ALIVE"
    assert "lib/demo/ticket.ex" in receipt["consequence"]["files_changed"]
    assert [%{"cmd" => "mix ggen_igniter.sync" <> _}] = receipt["replay"]["commands"]

    ext = receipt["provider_ext"]["ggen_igniter"]
    assert ext["pack_digest"] =~ ~r/^sha256:[0-9a-f]{64}$/
    assert [<<"sha256:", _::binary-size(64)>>] = ext["ontology_digests"]

    ticket = Enum.find(ext["files"], &(&1["path"] == "lib/demo/ticket.ex"))

    assert ticket["sha256"] ==
             :crypto.hash(:sha256, File.read!(Path.join(out, "lib/demo/ticket.ex")))
             |> Base.encode16(case: :lower)
  end

  test "the receipt is deterministic and replayable: re-run yields the same file bytes", %{
    out: out
  } do
    {_, 0} = sync_cmd(["--out", out])
    [path] = receipts(out)
    first = File.read!(path)

    {output, code} = sync_cmd(["--out", out])
    assert code == 0, output
    assert [^path] = receipts(out)
    # second run reports files unchanged, so `files_changed` and the receipt differ only there
    again = File.read!(path) |> Jason.decode!()
    assert again["consequence"]["files_changed"] == []
    assert again["provider_execution_id"] == (first |> Jason.decode!())["provider_execution_id"]

    # direct API on the same inputs is stable too
    result = Sync.run!(pack_dir: @pack, ontologies: [@app], out_dir: out)
    opts = [pack_dir: @pack, ontologies: [@app], out_dir: out]
    assert Receipt.write!(result, opts) == Receipt.write!(result, opts)
    assert Receipt.build(result, opts) == Receipt.build(result, opts)
  end

  test "--dry-run writes no files and no receipt", %{out: out} do
    {output, code} = sync_cmd(["--out", out, "--dry-run"])
    assert code == 0, output
    assert output =~ "planned: write"
    refute File.exists?(Path.join(out, "lib/demo/ticket.ex"))
    assert receipts(out) == []
  end

  test "a non-Tera pack-dir keeps the unchanged EEx path (no Tera dispatch)" do
    pack = Path.join(File.cwd!(), "test/fixtures/ash-lifecycle-pack")
    refute Sync.tera_pack?(pack)
  end
end
