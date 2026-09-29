defmodule GgenIgniterPackLockTest do
  @moduledoc """
  Chicago-style tests for `GgenIgniter.PackLock`, `mix ggen_igniter.pack.lock`
  and the receipt `pack_digest` fields. Every collaborator is real: pack trees
  are real files in real temp dirs, the lockfile is a real file whose bytes are
  compared, one byte of a pack file is really flipped, the mix task is a real
  subprocess whose exit codes are asserted, and the receipt schema is the real
  `priv/schema/receipt.schema.json` checked against the real fixture and a real
  `GgenIgniter.Receipt` (structural subset check: required, additionalProperties,
  pattern -- the same subset the repo's receipt schema test implements). No
  mocks, stubs or interaction assertions.
  """
  use ExUnit.Case, async: true

  alias GgenIgniter.PackLock
  alias GgenIgniter.Receipt

  @moduletag :tmp_dir

  defp make_pack(dir, name \\ "demo-pack") do
    root = Path.join(dir, name)
    File.mkdir_p!(Path.join(root, "gates"))
    File.write!(Path.join(root, "ontology.ttl"), "@prefix ex: <http://e/> .\nex:a ex:b ex:c .\n")
    File.write!(Path.join(root, "gates/one.rq"), "SELECT * WHERE { ?s ?p ?o }\n")
    File.write!(Path.join(root, "pack.toml"), ~s(name = "#{name}"\nversion = "1.2.3"\n))
    root
  end

  describe "digest/1" do
    test "same tree in two dirs with different mtimes -> same digest", %{tmp_dir: tmp} do
      a = make_pack(Path.join(tmp, "a"))
      b = make_pack(Path.join(tmp, "b"))
      File.touch!(Path.join(b, "ontology.ttl"), {{2001, 1, 1}, {0, 0, 0}})
      assert PackLock.digest(a) == PackLock.digest(b)
      assert PackLock.digest(a) =~ ~r/^[0-9a-f]{64}$/
    end

    test "ignores .git, _build and .DS_Store", %{tmp_dir: tmp} do
      a = make_pack(tmp)
      before = PackLock.digest(a)
      File.mkdir_p!(Path.join(a, ".git"))
      File.write!(Path.join(a, ".git/HEAD"), "x")
      File.mkdir_p!(Path.join(a, "_build"))
      File.write!(Path.join(a, "_build/x"), "x")
      File.write!(Path.join(a, ".DS_Store"), "x")
      assert PackLock.digest(a) == before
    end

    test "sensitive to content and to path", %{tmp_dir: tmp} do
      a = make_pack(Path.join(tmp, "a"))
      base = PackLock.digest(a)
      File.rename!(Path.join(a, "gates/one.rq"), Path.join(a, "gates/two.rq"))
      renamed = PackLock.digest(a)
      refute renamed == base
      File.write!(Path.join(a, "gates/two.rq"), "SELECT * WHERE { ?s ?p ?o }\n ")
      refute PackLock.digest(a) in [base, renamed]
    end
  end

  describe "lockfile" do
    test "round-trip is byte-identical", %{tmp_dir: tmp} do
      a = make_pack(tmp)
      lock_path = Path.join(tmp, "ggen_igniter.pack.lock")
      lock = PackLock.put(PackLock.empty(), "demo-pack", PackLock.entry(a, "priv/ggen/demo-pack"))
      :ok = PackLock.write(lock_path, lock)
      first = File.read!(lock_path)
      {:ok, read} = PackLock.read(lock_path)
      assert read == lock
      :ok = PackLock.write(lock_path, read)
      assert File.read!(lock_path) == first
      assert read["packs"]["demo-pack"]["version"] == "1.2.3"
      assert read["packs"]["demo-pack"]["sha256"] == PackLock.digest(a)
    end

    test "check: ok, mismatch after flipping one byte, lock_missing", %{tmp_dir: tmp} do
      a = make_pack(tmp)
      lock_path = Path.join(tmp, "ggen_igniter.pack.lock")

      assert {:error, {:lock_missing, ^lock_path}} = PackLock.check(a, lock_path)

      expected = PackLock.digest(a)

      :ok =
        PackLock.write(
          lock_path,
          PackLock.put(PackLock.empty(), "demo-pack", PackLock.entry(a, "x"))
        )

      assert :ok = PackLock.check(a, lock_path)

      f = Path.join(a, "ontology.ttl")
      <<first, rest::binary>> = File.read!(f)
      File.write!(f, <<Bitwise.bxor(first, 1), rest::binary>>)

      assert {:error,
              {:pack_digest_mismatch, %{pack: "demo-pack", expected: ^expected, actual: actual}}} =
               PackLock.check(a, lock_path)

      refute actual == expected

      other = make_pack(Path.join(tmp, "o"), "unlisted")
      assert {:error, {:lock_missing, ^lock_path}} = PackLock.check(other, lock_path)
    end
  end

  describe "mix ggen_igniter.pack.lock (subprocess)" do
    @describetag :integration

    defp mix(args, _cwd) do
      System.cmd("mix", ["ggen_igniter.pack.lock" | args],
        cd: File.cwd!(),
        stderr_to_stdout: true,
        env: [{"MIX_QUIET", "1"}]
      )
    end

    test "exit codes 0 / 1 / 2", %{tmp_dir: tmp} do
      root = Path.join(tmp, "packs")
      pack = make_pack(root)
      lock = Path.join(tmp, "x.lock")

      {out, 1} = mix(["--path", root, "--lock", lock, "--check"], tmp)
      assert out =~ "REFUSED:PACK_LOCK_MISSING"

      {_, 0} = mix(["--path", root, "--lock", lock], tmp)
      assert File.exists?(lock)
      {_, 0} = mix(["--path", root, "--lock", lock, "--check", "--json"], tmp)

      File.write!(Path.join(pack, "gates/one.rq"), "tampered")
      {out, 1} = mix(["--path", root, "--pack", "demo-pack", "--lock", lock, "--check"], tmp)
      assert out =~ "REFUSED:PACK_DIGEST_MISMATCH"
      assert out =~ "pack=demo-pack"

      {_, 2} = mix(["--bogus"], tmp)
      {_, 2} = mix(["--path", Path.join(tmp, "nope"), "--lock", lock], tmp)
    end
  end

  describe "receipt pack_digest" do
    @schema Path.join([__DIR__, "..", "priv", "schema", "receipt.schema.json"])

    defp schema_ok?(schema, data) do
      props = schema["properties"]

      Enum.all?(schema["required"], &Map.has_key?(data, &1)) and
        Enum.all?(Map.keys(data), &Map.has_key?(props, &1)) and
        Enum.all?(["pack_digest", "pack_name"], fn k ->
          case {data[k], props[k]["pattern"]} do
            {v, p} when is_binary(v) and is_binary(p) -> Regex.match?(Regex.compile!(p), v)
            _ -> true
          end
        end)
    end

    test "old receipts still validate; new fields accepted; bad digest rejected", %{tmp_dir: _} do
      schema = @schema |> File.read!() |> Jason.decode!()

      old =
        Path.join([__DIR__, "fixtures", "receipts", "valid.json"])
        |> File.read!()
        |> Jason.decode!()

      assert schema_ok?(schema, old)

      digest = String.duplicate("ab", 32)
      r = Receipt.new(%{standing: :alive, pack_name: "demo-pack", pack_digest: digest})
      json = Receipt.to_json_map(r)
      assert json["pack_digest"] == digest and json["pack_name"] == "demo-pack"
      assert schema_ok?(schema, json)
      refute schema_ok?(schema, Map.put(json, "pack_digest", "sha256:zz"))

      plain = Receipt.to_json_map(Receipt.new(%{standing: :alive}))
      refute Map.has_key?(plain, "pack_digest")
      assert schema_ok?(schema, plain)
    end

    test "pack_digest participates in receipt_hash" do
      a =
        Receipt.new(%{
          standing: :alive,
          id: "rcpt_0000000000000000",
          started_at: "t",
          finished_at: "t",
          tool_version: "v"
        })

      b =
        Receipt.new(%{
          standing: :alive,
          id: "rcpt_0000000000000000",
          started_at: "t",
          finished_at: "t",
          tool_version: "v",
          pack_digest: String.duplicate("0", 64)
        })

      refute a.receipt_hash == b.receipt_hash
    end
  end
end
