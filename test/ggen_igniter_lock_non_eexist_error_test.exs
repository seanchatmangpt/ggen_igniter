defmodule GgenIgniter.LockNonEexistErrorTest do
  @moduledoc """
  Chicago-style: no Mock/mox/patch/monkeypatch of `File.open/2`. Forces the
  real third `File.open/2` clause in `GgenIgniter.Lock.do_acquire/4` (any
  error other than `:eexist`) by pre-creating the lock file's parent
  directory (`.ggen_igniter/`) as read-only, so `acquire/2`'s own
  `File.mkdir_p!/1` is a real no-op (the directory already exists) and the
  real BEAM `File.open(path, [:write, :exclusive])` call returns the real
  `{:error, :eacces}` for a directory it cannot write into -- not a
  fabricated return value.
  """

  use ExUnit.Case, async: false

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
    tmp_dir = scratch_dir!("eacces")
    lock_dir = Path.join(tmp_dir, ".ggen_igniter")
    File.mkdir_p!(lock_dir)

    # Strip write permission from the real parent directory on disk so the
    # real `File.open(lock_path, [:write, :exclusive])` call returns a real
    # `{:error, :eacces}` -- `acquire/2`'s own `File.mkdir_p!/1` on this same
    # directory is a genuine no-op since it already exists, so the failure
    # is forced entirely by real filesystem permissions, not a mock.
    File.chmod!(lock_dir, 0o555)

    on_exit(fn -> File.chmod(lock_dir, 0o755) end)

    assert_raise RuntimeError, ~r/could not create lock file/, fn ->
      GgenIgniter.Lock.acquire(tmp_dir)
    end
  end
end
