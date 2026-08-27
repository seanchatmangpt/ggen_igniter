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

    # `System.unique_integer/1` resets per-BEAM-VM, so across separate `mix
    # test` invocations this path can collide with a stale directory left
    # over from a prior run. Force a clean slate and clean up after.
    File.rm_rf!(tmp_dir)
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

  describe "inject_content!/5 - format preservation (real Elixir source parses before and after)" do
    test "injecting a new function into a real module keeps the file valid Elixir", %{
      tmp_dir: tmp_dir
    } do
      path = Path.join(tmp_dir, "sample.ex")

      source = """
      defmodule Sample do
        # ggen:functions
        def existing, do: :ok
      end
      """

      File.write!(path, source)
      assert {:ok, _quoted} = Code.string_to_quoted(source)

      assert {:ok, :injected} =
               Actuate.inject_content!(
                 path,
                 "# ggen:functions",
                 "  def injected, do: :new",
                 :after
               )

      new_source = File.read!(path)
      assert {:ok, quoted} = Code.string_to_quoted(new_source)

      # The injected function is really present in the parsed AST (not just
      # in the raw text), and the pre-existing function survived untouched.
      {_ast, defs} =
        Macro.prewalk(quoted, [], fn
          {:def, _, [{name, _, _} | _]} = node, acc -> {node, [name | acc]}
          node, acc -> {node, acc}
        end)

      assert :injected in defs
      assert :existing in defs
    end

    test "injecting before a module attribute anchor preserves surrounding real Elixir source", %{
      tmp_dir: tmp_dir
    } do
      path = Path.join(tmp_dir, "sample2.ex")

      source = """
      defmodule Sample2 do
        @moduledoc "hi"

        def foo(x) do
          x + 1
        end
      end
      """

      File.write!(path, source)
      assert {:ok, _} = Code.string_to_quoted(source)

      assert {:ok, :injected} =
               Actuate.inject_content!(
                 path,
                 "def foo(x) do",
                 "  def bar(y), do: y * 2\n",
                 :before
               )

      new_source = File.read!(path)
      assert {:ok, _} = Code.string_to_quoted(new_source)
      assert new_source =~ "def bar(y), do: y * 2"
      assert new_source =~ "def foo(x) do"
      assert new_source =~ "x + 1"
    end
  end

  describe "inject_content!/5 - idempotency composition: mu(mu(O)) = mu(O)" do
    test "applying the same :after injection twice yields the identical real file content as applying it once",
         %{tmp_dir: tmp_dir} do
      path = Path.join(tmp_dir, "compose_after.ex")
      File.write!(path, "# modules\npub mod a\n")

      {:ok, :injected} = Actuate.inject_content!(path, "# modules", "pub mod b", :after)
      once = File.read!(path)

      {:ok, :unchanged} = Actuate.inject_content!(path, "# modules", "pub mod b", :after)
      twice = File.read!(path)

      assert once == twice
      assert twice == "# modules\npub mod b\npub mod a\n"
    end

    test "applying the same :before injection twice yields the identical real file content as applying it once",
         %{tmp_dir: tmp_dir} do
      path = Path.join(tmp_dir, "compose_before.ex")
      File.write!(path, "one\ntwo\n")

      {:ok, :injected} = Actuate.inject_content!(path, "two", "middle", :before)
      once = File.read!(path)

      {:ok, :unchanged} = Actuate.inject_content!(path, "two", "middle", :before)
      twice = File.read!(path)

      assert once == twice
      assert twice == "one\nmiddle\ntwo\n"
    end

    test "applying the same :at_line injection twice yields the identical real file content as applying it once",
         %{tmp_dir: tmp_dir} do
      path = Path.join(tmp_dir, "compose_at_line.ex")
      File.write!(path, "one\ntwo\n")

      {:ok, :injected} = Actuate.inject_content!(path, nil, "zero", :at_line, line: 1)
      once = File.read!(path)

      {:ok, :unchanged} = Actuate.inject_content!(path, nil, "zero", :at_line, line: 1)
      twice = File.read!(path)

      assert once == twice
      assert twice == "zero\none\ntwo\n"
    end

    test "three consecutive applications remain fixed after the first (mu is a true idempotent projection)",
         %{tmp_dir: tmp_dir} do
      path = Path.join(tmp_dir, "compose_thrice.ex")
      File.write!(path, "# modules\npub mod a\n")

      {:ok, :injected} = Actuate.inject_content!(path, "# modules", "pub mod b", :after)
      first = File.read!(path)

      {:ok, :unchanged} = Actuate.inject_content!(path, "# modules", "pub mod b", :after)
      second = File.read!(path)

      {:ok, :unchanged} = Actuate.inject_content!(path, "# modules", "pub mod b", :after)
      third = File.read!(path)

      assert first == second
      assert second == third
    end
  end
end
