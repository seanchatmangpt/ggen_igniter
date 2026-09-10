defmodule GgenIgniterManifestPruneTest do
  @moduledoc """
  Direct unit tests for `GgenIgniter.Manifest.prune!/1`'s three real
  outcomes, exercising the two branches not covered by
  `test/ggen_igniter_manifest_destructive_evolution_test.exs` (which only
  ever prunes paths that really exist, i.e. only the `:pruned` outcome):

  1. `:absent` -- pruning a path that is already gone (`File.rm/1` returns
     `{:error, :enoent}`).
  2. The `RuntimeError` raise branch -- `File.rm/1` fails for any other
     reason (here, a real permissions error: the parent directory is
     chmod'd to strip write permission, so deleting the file inside it
     really fails with `{:error, :eacces}`).

  No mocks -- every scenario uses real files/directories on a real tmp dir
  and asserts on `Manifest.prune!/1`'s real return value or the real raised
  exception message.
  """
  use ExUnit.Case, async: true

  alias GgenIgniter.Manifest

  setup do
    tmp_dir =
      Path.join(
        System.tmp_dir!(),
        "ggen_igniter_manifest_prune_#{System.unique_integer([:positive])}"
      )

    File.mkdir_p!(tmp_dir)
    on_exit(fn -> File.rm_rf!(tmp_dir) end)
    %{base_dir: tmp_dir}
  end

  test "prune!/1 returns :absent for a path that does not exist", %{base_dir: base_dir} do
    missing_path = Path.join(base_dir, "never_written.ex")

    refute File.exists?(missing_path)

    assert Manifest.prune!([missing_path]) == [{missing_path, :absent}]
  end

  @tag :unix_permissions
  test "prune!/1 raises RuntimeError when File.rm/1 fails for a reason other than :enoent",
       %{base_dir: base_dir} do
    locked_dir = Path.join(base_dir, "locked")
    File.mkdir_p!(locked_dir)
    file_path = Path.join(locked_dir, "output.ex")
    File.write!(file_path, "content")

    # Strip write+execute permission from the parent directory so the
    # kernel really refuses the unlink -- File.rm/1 on the file inside it
    # fails with a real {:error, :eacces}, not a simulated one.
    File.chmod!(locked_dir, 0o555)

    on_exit(fn ->
      # Restore permissions before the outer on_exit's File.rm_rf! runs,
      # or the recursive delete of tmp_dir would itself fail.
      File.chmod!(locked_dir, 0o755)
    end)

    assert_raise RuntimeError,
                 ~r/ggen_igniter: --on-stale prune could not delete stale output #{Regex.escape(file_path)}: /,
                 fn -> Manifest.prune!([file_path]) end
  end
end
