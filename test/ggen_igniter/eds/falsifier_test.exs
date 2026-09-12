defmodule GgenIgniter.EDS.FalsifierTest do
  @moduledoc """
  Chicago-style: real check functions are executed for real (including a
  real `raise` to prove exception-to-falsified handling); no mock of a
  falsifier's check behavior.
  """

  use ExUnit.Case, async: true

  alias GgenIgniter.EDS.Falsifier

  test "run/2 returns the real verdict from a survived check" do
    f =
      Falsifier.new("even", "the number is odd", fn n ->
        if rem(n, 2) == 0, do: {:survived, n}, else: {:falsified, n}
      end)

    assert Falsifier.run(f, 4) == {:survived, 4}
  end

  test "run/2 returns the real verdict from a falsified check" do
    f =
      Falsifier.new("even", "the number is odd", fn n ->
        if rem(n, 2) == 0, do: {:survived, n}, else: {:falsified, n}
      end)

    assert Falsifier.run(f, 5) == {:falsified, 5}
  end

  test "run/2 treats a raised exception as falsified, not as a crash" do
    f = Falsifier.new("no-crash", "the check function itself errors", fn _ -> raise "boom" end)
    assert {:falsified, {:exception, detail}} = Falsifier.run(f, :anything)
    assert detail =~ "boom"
  end

  test "run/2 refuses a check that returns something other than a verdict tuple" do
    f = Falsifier.new("bad-shape", "check returns garbage", fn _ -> :not_a_verdict end)
    assert_raise ArgumentError, ~r/must return/, fn -> Falsifier.run(f, :x) end
  end

  test "all_survived?/1 is false if even one falsifier was falsified" do
    verdicts = [{"a", {:survived, 1}}, {"b", {:falsified, 2}}]
    refute Falsifier.all_survived?(verdicts)
  end

  test "all_survived?/1 is true only when every falsifier survived" do
    verdicts = [{"a", {:survived, 1}}, {"b", {:survived, 2}}]
    assert Falsifier.all_survived?(verdicts)
  end

  test "run_all/2 pairs each falsifier's name with its real verdict, in order" do
    fs = [
      Falsifier.new("a", "stmt a", fn _ -> {:survived, :a} end),
      Falsifier.new("b", "stmt b", fn _ -> {:falsified, :b} end)
    ]

    assert Falsifier.run_all(fs, :evidence) == [{"a", {:survived, :a}}, {"b", {:falsified, :b}}]
  end
end
