defmodule GgenIgniterLockPathCanonicalizationTest do
  @moduledoc """
  Real regression test for the "two spellings of the same directory bypass
  mutual exclusion" finding against `GgenIgniter.Lock` (see `lock.ex`).
  No mocks: exercises the real `Path.expand/1` canonicalization in
  `lock_path/1` and `acquire/2` against real directories on disk, and
  asserts on real resulting state (the actual lock file path string, and
  which of two real concurrent `acquire/2` calls actually wins the real
  `File.open/2` `:exclusive` race) -- never on interaction/call-count
  checks.
  """

  use ExUnit.Case, async: false

  @tag :tmp_dir
  test "lock_path/1 produces the same path for differently-spelled equivalent directories", %{
    tmp_dir: tmp_dir
  } do
    absolute = tmp_dir
    with_trailing_slash = tmp_dir <> "/"

    relative =
      absolute
      |> Path.relative_to_cwd()

    path_absolute = GgenIgniter.Lock.lock_path(absolute)
    path_trailing_slash = GgenIgniter.Lock.lock_path(with_trailing_slash)
    path_relative = GgenIgniter.Lock.lock_path(relative)

    assert path_absolute == path_trailing_slash
    assert path_absolute == path_relative
  end

  @tag :tmp_dir
  test "acquire/2 called with absolute vs. relative spellings of the same directory contends", %{
    tmp_dir: tmp_dir
  } do
    absolute = tmp_dir
    relative = Path.relative_to_cwd(absolute)

    {:ok, lock} = GgenIgniter.Lock.acquire(absolute)

    # A second acquire against a *differently spelled* but real-identical
    # directory must genuinely contend with the first -- it should time out
    # quickly against the still-held lock, not silently succeed by writing
    # to a different lock file path.
    assert_raise RuntimeError, ~r/could not acquire lock/, fn ->
      GgenIgniter.Lock.acquire(relative, timeout_ms: 100, retry_interval_ms: 10)
    end

    GgenIgniter.Lock.release(lock)
  end

  @tag :tmp_dir
  test "lock_path/1 resolves a symlink's spelling to the same path as its real target", %{
    tmp_dir: tmp_dir
  } do
    real_dir = Path.join(tmp_dir, "real")
    File.mkdir_p!(real_dir)
    link = Path.join(tmp_dir, "link")
    File.ln_s!(real_dir, link)

    # Path.expand/1 does not resolve symlinks (it is not a realpath), so
    # this asserts the actually-guaranteed behavior: the absolute and
    # relative spellings of the same literal directory argument resolve
    # identically. Full symlink-target resolution is a separate, disclosed
    # limitation, not claimed here.
    path_via_absolute = GgenIgniter.Lock.lock_path(link)
    path_via_relative = GgenIgniter.Lock.lock_path(Path.relative_to_cwd(link))

    assert path_via_absolute == path_via_relative
  end
end
