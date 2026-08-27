defmodule GgenIgniter.ActuateTest do
  @moduledoc """
  Chicago-style: real tmp dir, real File reads/writes, no mocks/patches.
  """
  use ExUnit.Case, async: true

  doctest GgenIgniter.Actuate

  alias GgenIgniter.Actuate

  setup do
    tmp_dir =
      Path.join(
        System.tmp_dir!(),
        "ggen_igniter_actuate_test_#{System.unique_integer([:positive])}"
      )

    File.mkdir_p!(tmp_dir)
    on_exit(fn -> File.rm_rf!(tmp_dir) end)
    {:ok, tmp_dir: tmp_dir}
  end

  describe "write_new_file!/2 (backward compat)" do
    test "creates parent dirs and writes content", %{tmp_dir: tmp_dir} do
      path = Path.join([tmp_dir, "nested", "deep", "file.ex"])

      assert :ok = Actuate.write_new_file!(path, "hello world")
      assert File.read!(path) == "hello world"
    end

    test "overwrites existing file unconditionally", %{tmp_dir: tmp_dir} do
      path = Path.join(tmp_dir, "file.ex")
      File.write!(path, "old content")

      assert :ok = Actuate.write_new_file!(path, "new content")
      assert File.read!(path) == "new content"
    end
  end

  describe "write_file!/3 - default behavior (no opts)" do
    test "writes when target does not exist", %{tmp_dir: tmp_dir} do
      path = Path.join([tmp_dir, "a", "b.ex"])

      assert {:ok, :written} = Actuate.write_file!(path, "content")
      assert File.read!(path) == "content"
    end

    test "writes when target exists with differing content", %{tmp_dir: tmp_dir} do
      path = Path.join(tmp_dir, "b.ex")
      File.write!(path, "old")

      assert {:ok, :written} = Actuate.write_file!(path, "new")
      assert File.read!(path) == "new"
    end
  end

  describe "write_file!/3 - idempotent no-op detection (unconditional)" do
    test "returns {:ok, :unchanged} and does not rewrite when content is byte-identical", %{
      tmp_dir: tmp_dir
    } do
      path = Path.join(tmp_dir, "same.ex")
      File.write!(path, "identical content")

      {:ok, mtime_before} =
        File.stat(path, time: :posix) |> then(fn {:ok, s} -> {:ok, s.mtime} end)

      # ensure any timestamp-based detection would notice a real rewrite
      Process.sleep(10)

      assert {:ok, :unchanged} = Actuate.write_file!(path, "identical content")
      assert File.read!(path) == "identical content"

      {:ok, stat_after} = File.stat(path, time: :posix)
      assert stat_after.mtime == mtime_before
    end

    test "applies unconditionally with no flag needed", %{tmp_dir: tmp_dir} do
      path = Path.join(tmp_dir, "same2.ex")
      File.write!(path, "same")

      assert {:ok, :unchanged} =
               Actuate.write_file!(path, "same", unless_exists: false, skip_if: nil)
    end
  end

  describe "write_file!/3 - unless_exists option" do
    test "skips write when target exists regardless of content", %{tmp_dir: tmp_dir} do
      path = Path.join(tmp_dir, "exists.ex")
      File.write!(path, "original")

      assert {:ok, :skipped_exists} =
               Actuate.write_file!(path, "completely different content", unless_exists: true)

      assert File.read!(path) == "original"
    end

    test "writes when target does not exist", %{tmp_dir: tmp_dir} do
      path = Path.join(tmp_dir, "not_yet.ex")

      assert {:ok, :written} = Actuate.write_file!(path, "fresh", unless_exists: true)
      assert File.read!(path) == "fresh"
    end
  end

  describe "write_file!/3 - skip_if option" do
    test "skips when existing content contains the substring", %{tmp_dir: tmp_dir} do
      path = Path.join(tmp_dir, "marked.ex")
      File.write!(path, "defmodule Foo do\n  # ggen:keep\nend\n")

      assert {:ok, :skipped_match} =
               Actuate.write_file!(path, "brand new content", skip_if: "ggen:keep")

      assert File.read!(path) == "defmodule Foo do\n  # ggen:keep\nend\n"
    end

    test "writes when existing content does not contain the substring", %{tmp_dir: tmp_dir} do
      path = Path.join(tmp_dir, "unmarked.ex")
      File.write!(path, "defmodule Foo do\nend\n")

      assert {:ok, :written} = Actuate.write_file!(path, "new content", skip_if: "ggen:keep")
      assert File.read!(path) == "new content"
    end

    test "skips when existing content matches a regex", %{tmp_dir: tmp_dir} do
      path = Path.join(tmp_dir, "regex.ex")
      File.write!(path, "version: 1.2.3\n")

      assert {:ok, :skipped_match} =
               Actuate.write_file!(path, "new", skip_if: ~r/version: \d+\.\d+\.\d+/)

      assert File.read!(path) == "version: 1.2.3\n"
    end

    test "does not skip_if when target does not exist (nothing to match)", %{tmp_dir: tmp_dir} do
      path = Path.join(tmp_dir, "brand_new.ex")

      assert {:ok, :written} = Actuate.write_file!(path, "content", skip_if: "anything")
      assert File.read!(path) == "content"
    end
  end

  describe "write_file!/3 - decision order (unless_exists wins over skip_if and unchanged)" do
    test "unless_exists short-circuits even when content is identical", %{tmp_dir: tmp_dir} do
      path = Path.join(tmp_dir, "order.ex")
      File.write!(path, "same")

      # content is identical, which would normally be :unchanged, but
      # unless_exists is checked first per the decision order.
      assert {:ok, :skipped_exists} = Actuate.write_file!(path, "same", unless_exists: true)
    end
  end
end
