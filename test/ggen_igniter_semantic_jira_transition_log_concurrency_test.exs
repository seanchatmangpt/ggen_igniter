defmodule GgenIgniter.SemanticJiraTransitionLogConcurrencyTest do
  @moduledoc """
  Chicago, no-mocks stress of `TransitionLog.append/2` under real parallel
  writers: BEAM tasks (real scheduler-parallel processes) and real OS
  processes (`mix run` subprocesses) appending to ONE real ledger on disk, for
  both the ndjson-file and the directory form. Assertions are on final disk
  state: no lost, torn or duplicated event, `seq` is exactly 1..N, every
  `event_digest` recomputes (`fetch/1` accepts the ledger).
  """
  use ExUnit.Case, async: true

  alias GgenIgniter.SemanticJira.TransitionLog

  @writers 8
  @per_writer 12

  setup do
    dir = Path.join(System.tmp_dir!(), "sj_tlc_#{System.unique_integer([:positive])}")
    File.rm_rf!(dir)
    File.mkdir_p!(dir)
    on_exit(fn -> File.rm_rf!(dir) end)
    %{dir: dir}
  end

  defp event(writer, n) do
    %{
      "kind" => "standing_transition_event",
      "identity" => "WO-#{writer}-#{n}",
      "from" => "UNKNOWN",
      "to" => "ALIVE",
      "payload" => String.duplicate("x", 2_000 + n),
      "authority" => "NONE"
    }
  end

  defp assert_intact(ledger, expected_identities) do
    assert {:ok, events} = TransitionLog.fetch(ledger)
    assert Enum.sort(Enum.map(events, & &1["identity"])) == Enum.sort(expected_identities)
    assert Enum.map(events, & &1["seq"]) == Enum.to_list(1..length(expected_identities)//1)
    digests = Enum.map(events, & &1["event_digest"])
    assert length(Enum.uniq(digests)) == length(digests)
  end

  defp identities(writers, per),
    do: for(w <- 1..writers, n <- 1..per, do: "WO-#{w}-#{n}")

  for {label, name} <- [file: "ledger.ndjson", dir: "ledger-dir"] do
    test "#{label} ledger: parallel tasks lose, tear and duplicate nothing", %{dir: dir} do
      ledger = Path.join(dir, unquote(name))

      results =
        1..@writers
        |> Enum.map(fn w ->
          Task.async(fn ->
            for n <- 1..@per_writer, do: TransitionLog.append(ledger, event(w, n))
          end)
        end)
        |> Task.await_many(60_000)
        |> List.flatten()

      assert Enum.all?(results, &match?({:ok, _, :appended}, &1)), inspect(results)
      assert_intact(ledger, identities(@writers, @per_writer))
    end

    test "#{label} ledger: racing writers of the SAME event record it exactly once",
         %{dir: dir} do
      ledger = Path.join(dir, unquote(name))

      results =
        1..@writers
        |> Enum.map(fn _ -> Task.async(fn -> TransitionLog.append(ledger, event(0, 0)) end) end)
        |> Task.await_many(60_000)

      assert Enum.count(results, &match?({:ok, _, :appended}, &1)) == 1
      assert Enum.count(results, &match?({:ok, _, :already_recorded}, &1)) == @writers - 1
      assert_intact(ledger, ["WO-0-0"])
    end
  end

  test "file ledger: real OS processes appending in parallel keep the ledger intact",
       %{dir: dir} do
    ledger = Path.join(dir, "os.ndjson")
    os_writers = 4
    per = 6

    script = """
    [w] = System.argv()
    ledger = #{inspect(ledger)}
    for n <- 1..#{per} do
      {:ok, _, :appended} =
        GgenIgniter.SemanticJira.TransitionLog.append(ledger, %{
          "kind" => "standing_transition_event",
          "identity" => "WO-\#{w}-\#{n}",
          "payload" => String.duplicate("y", 3_000),
          "authority" => "NONE"
        })
    end
    """

    script_path = Path.join(dir, "writer.exs")
    File.write!(script_path, script)

    results =
      1..os_writers
      |> Enum.map(fn w ->
        Task.async(fn ->
          System.cmd(
            "mix",
            ["run", "--no-compile", "--no-deps-check", script_path, Integer.to_string(w)],
            cd: File.cwd!(),
            stderr_to_stdout: true
          )
        end)
      end)
      |> Task.await_many(300_000)

    for {out, code} <- results, do: assert(code == 0, out)
    assert_intact(ledger, identities(os_writers, per))
    refute File.exists?(ledger <> ".lock")
  end
end
