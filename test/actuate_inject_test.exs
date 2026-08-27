defmodule GgenIgniter.ActuateInjectTest do
  @moduledoc """
  Chicago-style: real tmp dir, real File reads/writes, no mocks/patches.
  Covers GgenIgniter.Actuate.inject_content!/5.
  """
  use ExUnit.Case, async: true

  alias GgenIgniter.Actuate

  setup do
    tmp_dir =
      Path.join(
        System.tmp_dir!(),
        "ggen_igniter_inject_test_#{System.unique_integer([:positive])}"
      )

    File.mkdir_p!(tmp_dir)
    on_exit(fn -> File.rm_rf!(tmp_dir) end)
    {:ok, tmp_dir: tmp_dir}
  end

  describe "inject_content!/5 - :before" do
    test "inserts content immediately before the matched literal marker line", %{
      tmp_dir: tmp_dir
    } do
      path = Path.join(tmp_dir, "f.txt")
      File.write!(path, "one\ntwo\n")

      assert {:ok, :injected} = Actuate.inject_content!(path, "two", "middle", :before)
      assert File.read!(path) == "one\nmiddle\ntwo\n"
    end

    test "inserts content immediately before the matched regex marker line", %{
      tmp_dir: tmp_dir
    } do
      path = Path.join(tmp_dir, "mod.ex")
      File.write!(path, "header\n  # GGEN:SLOT:COMMANDS  \nfooter\n")

      assert {:ok, :injected} =
               Actuate.inject_content!(
                 path,
                 ~r/^\s*# GGEN:SLOT:COMMANDS\s*$/,
                 "generated",
                 :before
               )

      assert File.read!(path) == "header\ngenerated\n  # GGEN:SLOT:COMMANDS  \nfooter\n"
    end
  end

  describe "inject_content!/5 - :after" do
    test "inserts content immediately after the matched marker line", %{tmp_dir: tmp_dir} do
      path = Path.join(tmp_dir, "mod.ex")
      File.write!(path, "# modules\npub mod a\n")

      assert {:ok, :injected} = Actuate.inject_content!(path, "# modules", "pub mod b", :after)
      assert File.read!(path) == "# modules\npub mod b\npub mod a\n"
    end
  end

  describe "inject_content!/5 - :at_line" do
    test "inserts content at the given 1-based line number", %{tmp_dir: tmp_dir} do
      path = Path.join(tmp_dir, "f.txt")
      File.write!(path, "one\ntwo\n")

      assert {:ok, :injected} = Actuate.inject_content!(path, nil, "zero", :at_line, line: 1)
      assert File.read!(path) == "zero\none\ntwo\n"
    end

    test "at end-of-file + 1 appends", %{tmp_dir: tmp_dir} do
      path = Path.join(tmp_dir, "f.txt")
      File.write!(path, "one\ntwo\n")

      assert {:ok, :injected} = Actuate.inject_content!(path, nil, "three", :at_line, line: 3)
      assert File.read!(path) == "one\ntwo\nthree\n"
    end
  end

  describe "inject_content!/5 - fails closed: missing target file" do
    test "raises rather than creating the file", %{tmp_dir: tmp_dir} do
      path = Path.join(tmp_dir, "nope.ex")

      assert_raise ArgumentError, ~r/does not exist/, fn ->
        Actuate.inject_content!(path, "anything", "x", :after)
      end

      refute File.exists?(path)
    end
  end

  describe "inject_content!/5 - fails closed: missing anchor" do
    test "raises when the marker matches no line, file left untouched", %{tmp_dir: tmp_dir} do
      path = Path.join(tmp_dir, "f.txt")
      File.write!(path, "one\n")

      assert_raise ArgumentError, ~r/matched no line/, fn ->
        Actuate.inject_content!(path, "// nowhere", "x", :after)
      end

      assert File.read!(path) == "one\n"
    end
  end

  describe "inject_content!/5 - fails closed: duplicate/ambiguous anchor" do
    test "raises when the marker matches more than one line, file left untouched", %{
      tmp_dir: tmp_dir
    } do
      path = Path.join(tmp_dir, "mod.ex")
      File.write!(path, "// SLOT\nbody\n// SLOT\n")

      assert_raise ArgumentError, ~r/matched 2 lines \(ambiguous\)/, fn ->
        Actuate.inject_content!(path, "// SLOT", "generated", :before)
      end

      assert File.read!(path) == "// SLOT\nbody\n// SLOT\n"
    end
  end

  describe "inject_content!/5 - idempotent re-run" do
    test "second identical injection is a no-op returning {:ok, :unchanged}", %{tmp_dir: tmp_dir} do
      path = Path.join(tmp_dir, "mod.ex")
      File.write!(path, "// modules\npub mod a\n")

      assert {:ok, :injected} = Actuate.inject_content!(path, "// modules", "pub mod b", :after)
      assert File.read!(path) == "// modules\npub mod b\npub mod a\n"

      # Re-run against the SAME original marker: the anchor line is still
      # unique ("// modules" occurs once), and the content that would be
      # spliced right after it is already there -> no duplication.
      assert {:ok, :unchanged} = Actuate.inject_content!(path, "// modules", "pub mod b", :after)
      assert File.read!(path) == "// modules\npub mod b\npub mod a\n"
    end

    test "idempotent re-run for :at_line", %{tmp_dir: tmp_dir} do
      path = Path.join(tmp_dir, "f.txt")
      File.write!(path, "one\ntwo\n")

      assert {:ok, :injected} = Actuate.inject_content!(path, nil, "zero", :at_line, line: 1)
      assert File.read!(path) == "zero\none\ntwo\n"

      assert {:ok, :unchanged} = Actuate.inject_content!(path, nil, "zero", :at_line, line: 1)
      assert File.read!(path) == "zero\none\ntwo\n"
    end
  end

  describe "inject_content!/5 - :dry_run option" do
    test "on a not-yet-injected target: real anchor resolution runs, {:ok, :injected} is returned, but the file is untouched",
         %{tmp_dir: tmp_dir} do
      path = Path.join(tmp_dir, "mod.ex")
      File.write!(path, "# modules\npub mod a\n")
      original = File.read!(path)
      original_mtime = File.stat!(path).mtime

      assert {:ok, :injected} =
               Actuate.inject_content!(path, "# modules", "pub mod b", :after, dry_run: true)

      assert File.read!(path) == original
      assert File.stat!(path).mtime == original_mtime
    end

    test "on an already-injected target: the real idempotency check runs, {:ok, :unchanged} is returned",
         %{tmp_dir: tmp_dir} do
      path = Path.join(tmp_dir, "mod.ex")
      File.write!(path, "# modules\npub mod b\npub mod a\n")

      assert {:ok, :unchanged} =
               Actuate.inject_content!(path, "# modules", "pub mod b", :after, dry_run: true)

      assert File.read!(path) == "# modules\npub mod b\npub mod a\n"
    end

    test "a real ambiguous-anchor failure still raises under dry_run -- a preview never suppresses a real error",
         %{tmp_dir: tmp_dir} do
      path = Path.join(tmp_dir, "mod.ex")
      File.write!(path, "// SLOT\nbody\n// SLOT\n")

      assert_raise ArgumentError, ~r/matched 2 lines \(ambiguous\)/, fn ->
        Actuate.inject_content!(path, "// SLOT", "generated", :before, dry_run: true)
      end

      assert File.read!(path) == "// SLOT\nbody\n// SLOT\n"
    end

    test "a real missing-target-file failure still raises under dry_run", %{tmp_dir: tmp_dir} do
      path = Path.join(tmp_dir, "nope.ex")

      assert_raise ArgumentError, ~r/does not exist/, fn ->
        Actuate.inject_content!(path, "anything", "x", :after, dry_run: true)
      end

      refute File.exists?(path)
    end
  end
end
