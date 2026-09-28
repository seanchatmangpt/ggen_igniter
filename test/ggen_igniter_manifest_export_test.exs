defmodule GgenIgniter.ManifestExportTest do
  @moduledoc """
  Chicago-style: real tmp dirs holding a real `GgenIgniter.Manifest` written
  by `persist!/2` and real `GgenIgniter.Receipt`s written by `append!/2`,
  exported by the real `GgenIgniter.ManifestExport` and, for exit codes, by a
  real `mix ggen_igniter.manifest.dump` subprocess. Assertions are on the
  returned/printed bytes and exit statuses. No doubles.
  """
  use ExUnit.Case, async: true

  alias GgenIgniter.{Manifest, ManifestExport, Receipt}

  @repo Path.expand("..", __DIR__)

  setup do
    dir = Path.join(System.tmp_dir!(), "manifest_export_#{System.unique_integer([:positive])}")
    File.rm_rf!(dir)
    File.mkdir_p!(dir)
    on_exit(fn -> File.rm_rf!(dir) end)
    {:ok, dir: dir}
  end

  defp seed(dir) do
    entry =
      Manifest.build_entry("t.eex", "out/<%= n %>.ex", nil, %{
        "out/b.ex" => "sha256:bb",
        "out/a.ex" => "sha256:aa"
      })

    %{"entries" => %{}} |> Manifest.put("t.eex=>out", entry) |> Manifest.persist!(dir)

    for {id, at} <- [{"r2", "2026-09-28T10:00:00Z"}, {"r1", "2026-09-28T09:00:00Z"}] do
      Receipt.append!(
        dir,
        Receipt.new(%{
          id: id,
          recipe_key: "t.eex=>out",
          standing: :alive,
          started_at: at,
          finished_at: at,
          files: ["out/a.ex"]
        })
      )
    end

    dir
  end

  describe "dump/1 (real manifest + receipts)" do
    test "exports manifest, digest, and receipts ordered by started_at", %{dir: dir} do
      seed(dir)
      assert {:ok, json} = ManifestExport.dump(dir)
      doc = Jason.decode!(json)

      assert doc["format"] == "ggen_igniter.manifest_export/1"
      assert Map.keys(doc["manifest"]["entries"]) == ["t.eex=>out"]
      assert Enum.map(doc["receipts"], & &1["id"]) == ["r1", "r2"]
      assert doc["manifest_sha256"] == GgenIgniter.Digest.sha256(File.read!(Manifest.path(dir)))
    end

    test "same input is byte-identical, even from a different directory", %{dir: dir} do
      seed(dir)
      copy = dir <> "_copy"
      File.rm_rf!(copy)
      File.cp_r!(dir, copy)
      on_exit(fn -> File.rm_rf!(copy) end)

      {:ok, a} = ManifestExport.dump(dir)
      {:ok, b} = ManifestExport.dump(dir)
      {:ok, c} = ManifestExport.dump(copy)
      assert a == b
      assert a == c
    end

    test "object keys are sorted at every depth" do
      out = ManifestExport.encode(%{"b" => %{"z" => 1, "a" => 2}, "a" => [%{"y" => 1, "x" => 2}]})

      assert out ==
               "{\n  \"a\": [\n    {\n      \"x\": 2,\n      \"y\": 1\n    }\n  ],\n  \"b\": {\n    \"a\": 2,\n    \"z\": 1\n  }\n}\n"
    end
  end

  describe "dump/1 (typed refusals)" do
    test "missing manifest", %{dir: dir} do
      assert {:error, {:missing_manifest, path}} = ManifestExport.dump(dir)
      assert path == Manifest.path(dir)
    end

    test "malformed manifest", %{dir: dir} do
      File.mkdir_p!(Path.dirname(Manifest.path(dir)))
      File.write!(Manifest.path(dir), "{not json")
      assert {:error, {:corrupt_manifest, _}} = ManifestExport.dump(dir)
    end

    test "malformed receipt line", %{dir: dir} do
      seed(dir)
      [file | _] = Path.wildcard(Path.join(Receipt.dir(dir), "*.jsonl"))
      File.write!(file, File.read!(file) <> "garbage\n")
      assert {:error, {:corrupt_receipt, detail}} = ManifestExport.dump(dir)
      assert detail =~ Path.basename(file)
    end
  end

  describe "mix ggen_igniter.manifest.dump (subprocess exit codes)" do
    defp mix(args),
      do:
        System.cmd("mix", ["ggen_igniter.manifest.dump" | args],
          cd: @repo,
          stderr_to_stdout: true,
          env: [{"MIX_ENV", "test"}]
        )

    test "exit 0 to --out, and file equals library dump", %{dir: dir} do
      seed(dir)
      out = Path.join(dir, "export.json")
      assert {_, 0} = mix(["--path", dir, "--out", out])
      assert File.read!(out) == elem(ManifestExport.dump(dir), 1)
    end

    test "exit 1 on missing manifest", %{dir: dir} do
      assert {out, 1} = mix(["--path", dir])
      assert out =~ "REFUSED:MISSING_MANIFEST"
    end

    test "exit 2 on bad invocation", %{dir: dir} do
      assert {out, 2} = mix(["--path", dir, "--bogus"])
      assert out =~ "invalid invocation"
    end
  end
end
