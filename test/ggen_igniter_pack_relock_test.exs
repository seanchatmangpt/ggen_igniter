defmodule GgenIgniter.PackRelockTest do
  @moduledoc """
  A changed pack re-locks in write mode without hand-deleting the lock.
  Mirrors `Mix.Tasks.GgenIgniter.Pack.Lock.write/4` (entry -> update/put) on
  real files; the task itself calls System.halt so it is exercised through the
  same PackLock API calls it makes.
  """
  use ExUnit.Case, async: true

  alias GgenIgniter.PackLock

  setup do
    base = Path.join(System.tmp_dir!(), "pack_relock_#{System.unique_integer([:positive])}")
    pack = Path.join(base, "demo")
    File.mkdir_p!(Path.join(pack, "templates"))
    File.write!(Path.join(pack, "pack.toml"), "version = \"1.0.0\"\n")
    File.write!(Path.join(pack, "ontology.ttl"), "# v1\n")
    File.write!(Path.join([pack, "templates", "a.tera"]), "hello\n")
    on_exit(fn -> File.rm_rf(base) end)
    {:ok, pack: pack, lock: Path.join(base, "ggen_igniter.pack.lock")}
  end

  defp write_mode(pack, lock) do
    entry = PackLock.entry(pack, pack)

    {:ok, _} =
      PackLock.update(lock, [force: false], fn l ->
        {:ok, PackLock.put(l, entry["name"], entry)}
      end)

    entry
  end

  test "mutated pack is refused, then write mode re-locks over the stale lock", %{
    pack: pack,
    lock: lock
  } do
    first = write_mode(pack, lock)
    assert PackLock.check(pack, lock) == :ok
    before_bytes = File.read!(lock)

    File.write!(Path.join(pack, "ontology.ttl"), "# v2 changed\n")

    assert {:error, {:pack_digest_mismatch, %{pack: "demo", expected: exp, actual: act}}} =
             PackLock.check(pack, lock)

    assert exp == first["sha256"]
    assert exp != act

    assert PackLock.refusal_text(
             {:pack_digest_mismatch, %{pack: "demo", expected: exp, actual: act}}
           ) =~
             "REFUSED:PACK_DIGEST_MISMATCH"

    second = write_mode(pack, lock)

    assert second["sha256"] == act
    assert PackLock.check(pack, lock) == :ok
    assert File.read!(lock) != before_bytes
  end
end
