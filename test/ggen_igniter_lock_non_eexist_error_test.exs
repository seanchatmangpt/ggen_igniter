defmodule GgenIgniter.LockNonEexistErrorTest do
  @moduledoc """
  Chicago-style: no Mock/mox/patch/monkeypatch of `File.open/2`. Forces the
  real third `File.open/2` clause in `GgenIgniter.Lock.do_acquire/4` (any
  error other than `:eexist`) by making the lock file's own path on disk
  already be a real directory, so the real BEAM `File.open/2` call returns
  the real `{:error, :eisdir}` -- not a fabricated return value.
  """

  use ExUnit.Case, async: false

  @lock_subpath ".ggen_igniter/.sync.lock"

  defp scratch_dir!(tag) do
    dir =
      Path.join(
        System.tmp_dir!(),
        "ggen_igniter_lock_non_eexist_#{tag}_#{System.unique_integer([:positive])}"
      )

    File.rm_rf!(dir)
    File.mkdir_p!(dir)
    on_exit(fn -> File.rm_rf!(dir) end)
    dir
  end

  test "raises 'could not create lock file' when File.open fails with a non-:eexist reason" do
    tmp_dir = scratch_dir!("eisdir")
    lock_path = Path.join(tmp_dir, @lock_subpath)

    # Pre-create the lock file's own path as a real directory. `acquire/2`
    # will `File.mkdir_p!(Path.dirname(lock_path))` (a no-op here, it already
    # exists) and then call the real `File.open(lock_path, [:write,
    # :exclusive])`, which on a real filesystem returns `{:error, :eisdir}`
    # for a path that is a directory -- a genuine non-:eexist failure, not a
    # mocked one.
    File.mkdir_p!(lock_path)

    assert_raise RuntimeError, ~r/could not create lock file/, fn ->
      GgenIgniter.Lock.acquire(tmp_dir)
    end
  end
end
