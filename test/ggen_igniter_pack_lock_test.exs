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

  describe "digest/1 symlink handling (audit F3-1)" do
    test "symlink to an outside file is refused PACK_SYMLINK_ESCAPE, outside swap cannot go unnoticed",
         %{tmp_dir: tmp} do
      a = make_pack(Path.join(tmp, "a"))
      outside = Path.join(tmp, "outside.eex")
      File.write!(outside, "v1")
      lock_path = Path.join(tmp, "x.lock")

      File.mkdir_p!(Path.join(a, "templates"))
      # The fixture tmp lives inside this repo, so an in-repo target is the
      # LAWFUL in-repo canonical form under the 26.10.2 symlink law: allowed,
      # but content-hashed (tag "L") — an outside swap moves the digest. The
      # lock entry is built AFTER the symlink exists, so it pins the
      # symlink-inclusive digest and check can honestly compare against it.
      File.ln_s!(outside, Path.join(a, "templates/t.eex"))

      {:ok, _} =
        PackLock.update(lock_path, fn l ->
          {:ok, PackLock.put(l, "demo-pack", PackLock.entry(a, "x"))}
        end)

      assert {:ok, d1} = PackLock.digest_checked(a)
      assert :ok = PackLock.check(a, lock_path)

      File.write!(outside, "v2")
      assert {:ok, d2} = PackLock.digest_checked(a)
      refute d1 == d2, "an in-repo target's swap must move the content digest"
      assert {:error, {:pack_digest_mismatch, _}} = PackLock.check(a, lock_path)
      File.write!(outside, "v1")

      # A target that leaves the git toplevel entirely is still an escape.
      repo_out = Path.join(System.tmp_dir!(), "pack_lock_out_#{System.unique_integer([:positive])}")
      File.mkdir_p!(repo_out)
      File.write!(Path.join(repo_out, "e.eex"), "v1")
      File.rm_rf!(Path.join(a, "templates/t.eex"))
      File.ln_s!(Path.join(repo_out, "e.eex"), Path.join(a, "templates/t.eex"))
      on_exit(fn -> File.rm_rf!(repo_out) end)

      assert {:error, {:pack_symlink_escape, detail}} = PackLock.digest_checked(a)

      # The lock refuses the escape through every entry point, and the raising
      # twin keeps its law. (Re-pointing at the in-repo `outside` would not be
      # an escape — the 26.10.2 law hashes in-repo targets with tag "L".)
      assert {:error, {:pack_symlink_escape, _}} = PackLock.check(a, lock_path)

      assert PackLock.refusal_text({:pack_symlink_escape, detail}) =~
               "REFUSED:PACK_SYMLINK_ESCAPE "

      assert_raise PackLock.Refusal, fn -> PackLock.digest(a) end
    end

    test "directory symlink (even to an outside dir named templates) is refused", %{tmp_dir: tmp} do
      a = make_pack(Path.join(tmp, "a"))
      out_dir = Path.join(tmp, "outdir")
      File.mkdir_p!(out_dir)
      File.write!(Path.join(out_dir, "t.eex"), "x")
      File.ln_s!(out_dir, Path.join(a, "templates"))
      assert {:error, {:pack_symlink_escape, _}} = PackLock.digest_checked(a)

      inner = Path.join(tmp, "b")
      b = make_pack(inner)
      File.mkdir_p!(Path.join(b, "real"))
      File.ln_s!(Path.join(b, "real"), Path.join(b, "linkdir"))
      assert {:error, {:pack_symlink_escape, _}} = PackLock.digest_checked(b)
    end

    test "symlink loop is a typed refusal, not a hang", %{tmp_dir: tmp} do
      a = make_pack(tmp)
      File.ln_s!(Path.join(a, "l2"), Path.join(a, "l1"))
      File.ln_s!(Path.join(a, "l1"), Path.join(a, "l2"))
      assert {:error, {:pack_symlink_escape, _}} = PackLock.digest_checked(a)
    end

    test "in-pack symlink to a regular file hashes resolved content", %{tmp_dir: tmp} do
      a = make_pack(tmp)
      File.mkdir_p!(Path.join(a, "templates"))
      File.write!(Path.join(a, "shared.eex"), "one")
      File.ln_s!(Path.join(a, "shared.eex"), Path.join(a, "templates/t.eex"))
      {:ok, d1} = PackLock.digest_checked(a)
      File.write!(Path.join(a, "shared.eex"), "two")
      {:ok, d2} = PackLock.digest_checked(a)
      refute d1 == d2

      # relative link form resolves the same way
      File.rm!(Path.join(a, "templates/t.eex"))
      File.ln_s!("../shared.eex", Path.join(a, "templates/t.eex"))
      assert {:ok, _} = PackLock.digest_checked(a)
    end

    test "a symlink and a regular file holding the link text never collide", %{tmp_dir: tmp} do
      a = make_pack(Path.join(tmp, "a"))
      b = make_pack(Path.join(tmp, "b"))
      File.write!(Path.join(a, "target.txt"), "same")
      File.write!(Path.join(b, "target.txt"), "same")
      File.ln_s!("target.txt", Path.join(a, "alias.txt"))
      File.write!(Path.join(b, "alias.txt"), "same")
      {:ok, da} = PackLock.digest_checked(a)
      {:ok, db} = PackLock.digest_checked(b)
      refute da == db
    end
  end

  describe "digest/1 unreadable file (audit F3-4)" do
    @tag :unix_perms
    test "chmod 000 file -> typed PACK_FILE_UNREADABLE", %{tmp_dir: tmp} do
      a = make_pack(tmp)
      f = Path.join(a, "ontology.ttl")
      File.chmod!(f, 0o000)
      on_exit(fn -> File.chmod(f, 0o644) end)

      if match?({:ok, _}, File.read(f)) do
        :ok
      else
        assert {:error, {:pack_file_unreadable, detail}} = PackLock.digest_checked(a)
        assert detail =~ "ontology.ttl"

        assert PackLock.refusal_text({:pack_file_unreadable, detail}) =~
                 "REFUSED:PACK_FILE_UNREADABLE "
      end
    end
  end

  describe "lockfile concurrency (audit F3-2)" do
    test "concurrent reader never observes partial JSON during 8 writers", %{tmp_dir: tmp} do
      l = Path.join(tmp, "race.lock")

      big =
        Enum.reduce(1..300, PackLock.empty(), fn i, acc ->
          PackLock.put(acc, "p#{i}", %{
            "name" => "p#{i}",
            "sha256" => String.duplicate("a", 64),
            "source" => "x",
            "version" => nil,
            "locked_by" => "t"
          })
        end)

      PackLock.write(l, big)
      done = :atomics.new(1, [])

      reader =
        Task.async(fn ->
          loop = fn loop, bad, n ->
            if :atomics.get(done, 1) == 1 and n > 200 do
              bad
            else
              case PackLock.read(l) do
                {:ok, _} -> loop.(loop, bad, n + 1)
                _ -> loop.(loop, bad + 1, n + 1)
              end
            end
          end

          loop.(loop, 0, 0)
        end)

      writers =
        for _ <- 1..8 do
          Task.async(fn -> for _ <- 1..150, do: PackLock.write(l, big) end)
        end

      Enum.each(writers, &Task.await(&1, 120_000))
      :atomics.put(done, 1, 1)
      assert Task.await(reader, 120_000) == 0
      assert File.ls!(tmp) |> Enum.filter(&String.contains?(&1, ".tmp")) == []
    end

    test "8 concurrent update/3 puts all land, none lost", %{tmp_dir: tmp} do
      l = Path.join(tmp, "put.lock")

      1..8
      |> Enum.map(fn i ->
        Task.async(fn ->
          PackLock.update(l, fn lock ->
            Process.sleep(5)
            {:ok, PackLock.put(lock, "p#{i}", %{"name" => "p#{i}", "sha256" => "x"})}
          end)
        end)
      end)
      |> Enum.each(fn t -> assert {:ok, _} = Task.await(t, 60_000) end)

      {:ok, lock} = PackLock.read(l)

      assert lock["packs"] |> Map.keys() |> Enum.sort() ==
               Enum.map(1..8, &"p#{&1}") |> Enum.sort()

      refute File.exists?(l <> ".lockdir")
    end
  end

  describe "invalid lock is not fail-open (audit F3-3)" do
    test "check returns lock_invalid distinct from lock_missing; update refuses without force",
         %{tmp_dir: tmp} do
      a = make_pack(tmp)
      l = Path.join(tmp, "bad.lock")
      File.write!(l, "{ not json")

      assert {:error, {:lock_invalid, ^l}} = PackLock.check(a, l)
      assert PackLock.refusal_text({:lock_invalid, l}) == "REFUSED:PACK_LOCK_INVALID #{l}"

      assert {:error, {:lock_invalid, ^l}} = PackLock.update(l, fn x -> {:ok, x} end)
      assert File.read!(l) == "{ not json"

      assert {:ok, lock} = PackLock.update(l, [force: true], fn x -> {:ok, x} end)
      assert lock == PackLock.empty()
      assert {:ok, _} = PackLock.read(l)
    end
  end

  describe "with_staging/1 (audit F3-6)" do
    test "staging dir removed on success and on raise", %{tmp_dir: _} do
      seen =
        PackLock.with_staging(fn dir ->
          assert File.dir?(dir)
          dir
        end)

      refute File.exists?(seen)

      raised = self()

      assert_raise RuntimeError, fn ->
        PackLock.with_staging(fn dir ->
          send(raised, {:dir, dir})
          raise "boom"
        end)
      end

      assert_received {:dir, dir}
      refute File.exists?(dir)
    end
  end

  describe "mix tasks refuse invalid locks (subprocess)" do
    @describetag :integration

    test "pack.lock write mode refuses a garbled lock, --force-regenerate overwrites",
         %{tmp_dir: tmp} do
      root = Path.join(tmp, "packs")
      make_pack(root)
      lock = Path.join(tmp, "g.lock")
      File.write!(lock, "garbage")

      {out, 1} =
        System.cmd("mix", ["ggen_igniter.pack.lock", "--path", root, "--lock", lock],
          cd: File.cwd!(),
          stderr_to_stdout: true,
          env: [{"MIX_QUIET", "1"}]
        )

      assert out =~ "REFUSED:PACK_LOCK_INVALID"
      assert File.read!(lock) == "garbage"

      {out, 1} =
        System.cmd("mix", ["ggen_igniter.pack.lock", "--path", root, "--lock", lock, "--check"],
          cd: File.cwd!(),
          stderr_to_stdout: true,
          env: [{"MIX_QUIET", "1"}]
        )

      assert out =~ "REFUSED:PACK_LOCK_INVALID"

      {_, 0} =
        System.cmd(
          "mix",
          ["ggen_igniter.pack.lock", "--path", root, "--lock", lock, "--force-regenerate"],
          cd: File.cwd!(),
          stderr_to_stdout: true,
          env: [{"MIX_QUIET", "1"}]
        )

      assert {:ok, _} = PackLock.read(lock)
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
describe "digest_checked/1 (in-repo canonical symlink law, 26.10.2)" do
  @sha ~r/\A[0-9a-f]{64}\z/

  test "an in-repo canonical symlink (pack ontology -> repo-root ontology) digests; outside-the-repo still refuses" do
    base = Path.join(System.tmp_dir!(), "pack_lock_symlink_#{System.unique_integer([:positive])}")
    File.rm_rf!(base)
    File.mkdir_p!(Path.join(base, "priv/ggen/p"))
    File.mkdir_p!(Path.join(base, "priv/ggen/q"))

    git! = fn args, cwd ->
      {out, 0} = System.cmd("git", args, cd: cwd, env: [{"GIT_AUTHOR_NAME", "t"}, {"GIT_AUTHOR_EMAIL", "t@t"}, {"GIT_COMMITTER_NAME", "t"}, {"GIT_COMMITTER_EMAIL", "t@t"}])
      String.trim(out)
    end

    git!.(["init", "-q"], base)
    git!.(["config", "user.email", "t@t"], base)
    git!.(["config", "user.name", "t"], base)
    File.write!(Path.join(base, "ontology.ttl"), "<urn:r> a <urn:Root> .\n")
    # p: in-repo canonical symlink to the repo-root ontology (lawful per ash_pplan's law)
    File.write!(Path.join(base, "priv/ggen/p/other.ttl"), "<urn:p> a <urn:P> .\n")
    # q: symlink leaving the repo entirely
    outside = Path.join(System.tmp_dir!(), "pack_lock_outside_#{System.unique_integer([:positive])}")
    File.mkdir_p!(outside)
    File.write!(Path.join(outside, "evil.ttl"), "<urn:e> a <urn:E> .\n")

    on_exit(fn ->
      File.rm_rf!(base)
      File.rm_rf!(outside)
    end)

    {top, 0} = System.cmd("git", ["-C", Path.join(base, "priv/ggen/p"), "rev-parse", "--show-toplevel"])
    assert String.trim(top) == Path.expand(base)

    File.ln_s!(Path.join(base, "ontology.ttl"), Path.join(base, "priv/ggen/p/ontology.ttl"))
    File.ln_s!(outside <> "/evil.ttl", Path.join(base, "priv/ggen/q/ontology.ttl"))

    assert {:ok, d1} = GgenIgniter.PackLock.digest_checked(Path.join(base, "priv/ggen/p"))
    assert d1 =~ @sha

    # digest is a function of the TARGET content: mutate the root ontology -> digest moves
    File.write!(Path.join(base, "ontology.ttl"), "<urn:r> a <urn:Root2> .\n")
    assert {:ok, d2} = GgenIgniter.PackLock.digest_checked(Path.join(base, "priv/ggen/p"))
    refute d1 == d2

    assert {:error, {:pack_symlink_escape, detail}} =
             GgenIgniter.PackLock.digest_checked(Path.join(base, "priv/ggen/q"))

    assert detail =~ "outside pack root"
  end
end
end
