defmodule GgenIgniterSleepGateTest do
  @moduledoc """
  Chicago-style court for `GgenIgniter.SleepGate`: real files in a real tmp
  dir, real AST parse, plus the live repo scan. A gate that accepts an
  unannotated sleep is reported as VACUOUS GATE.
  """

  use ExUnit.Case, async: true

  alias GgenIgniter.SleepGate

  @moduletag :tmp_dir

  defp put(root, rel, body) do
    path = Path.join(root, rel)
    File.mkdir_p!(Path.dirname(path))
    File.write!(path, body)
  end

  test "unannotated lib sleep is exactly one violation (non-vacuity)", %{tmp_dir: root} do
    put(root, "lib/a.ex", "defmodule A do\n  def f, do: Process.sleep(1)\nend\n")

    case SleepGate.scan(root) do
      [] -> flunk("VACUOUS GATE: unannotated lib sleep was accepted")
      [v] -> assert %{file: "lib/a.ex", line: 2, kind: :unclassified_lib} = v
      other -> flunk("expected exactly one violation, got #{inspect(other)}")
    end
  end

  test ":timer.sleep in lib is also caught", %{tmp_dir: root} do
    put(root, "lib/a.ex", "defmodule A do\n  def f, do: :timer.sleep(1)\nend\n")
    assert [%{kind: :unclassified_lib}] = SleepGate.scan(root)
  end

  test "annotated lib sleep passes", %{tmp_dir: root} do
    put(root, "lib/a.ex", """
    defmodule A do
      def f do
        # SLEEP-CLASS: POLL-STEP
        Process.sleep(1)
      end

      def g do
        # SLEEP-CLASS: SCHEDULING
        :timer.sleep(1)
      end
    end
    """)

    assert SleepGate.scan(root) == []
  end

  test "unknown class is :bad_class", %{tmp_dir: root} do
    put(root, "lib/a.ex", """
    defmodule A do
      def f do
        # SLEEP-CLASS: WHATEVER
        Process.sleep(1)
      end
    end
    """)

    assert [%{kind: :bad_class, line: 4}] = SleepGate.scan(root)
  end

  test "test/ sleep outside the allowlist is :test_sleep", %{tmp_dir: root} do
    put(root, "test/x_test.exs", "defmodule XTest do\n  def f, do: Process.sleep(1)\nend\n")
    assert [%{file: "test/x_test.exs", kind: :test_sleep}] = SleepGate.scan(root)
  end

  test "allowlisted audited helper may sleep", %{tmp_dir: root} do
    [path] = SleepGate.allowlist()
    put(root, path, "defmodule H do\n  def f, do: Process.sleep(1)\nend\n")
    assert SleepGate.scan(root) == []
  end

  test "sleep inside heredoc, string, or comment is not a hit", %{tmp_dir: root} do
    put(root, "lib/a.ex", ~S'''
    defmodule A do
      @moduledoc """
      Never call Process.sleep(10) here.
      """

      # Process.sleep(5) in a comment
      def s, do: "Process.sleep(1) in a string"
    end
    ''')

    put(root, "test/x_test.exs", ~S'''
    defmodule XTest do
      @script "Process.sleep(300)"
      def s, do: @script
    end
    ''')

    assert SleepGate.scan(root) == []
  end

  test "the real repo is clean" do
    assert SleepGate.scan(File.cwd!()) == []
  end
end
