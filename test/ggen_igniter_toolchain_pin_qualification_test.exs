defmodule GgenIgniter.ToolchainPinQualificationTest do
  @moduledoc """
  GC23-11 exact-head qualification under this repository's own
  `.tool-versions` pin (PRD section 12 GC23-11 and PR-013; ARD section 20
  `BUILD_BROKEN(toolchain)`, section 25 verification ladder, section 27
  toolchain identity). Release defect lane R1-GI-PIN, repair round 1.

  The v26.9.23 release qualification of this repo passed only under the
  ambient Elixir 1.19.5 / OTP 28.3.1, while `.tool-versions` and CI pin
  elixir 1.18.4-otp-27 / erlang 27.2.4; the pinned formatter refused the
  frozen subject the ambient run admitted (F3/F4, repaired by R1-GI-FMT).
  The pinned qualification (`receipts/v26.9.23/R1-GI-PIN.json`) was evidence
  no gate read, so reverting it left every gate green (court verdict
  REVERT-MUTATION refuted, `admission_vacuous`). These tests make the suite
  consume it:

    * the running VM is the pin, so a green full suite is a pinned run (an
      ambient run fails, typed `BUILD_BROKEN(toolchain)`), and CI's
      setup-beam pin is the `.tool-versions` pin;
    * the pinned-qualification receipt is admitted by the fleet R-schema
      check (`GgenIgniter.SemanticJira.Bootstrap.Receipts.check/1`), ALIVE,
      records the pin read from `.tool-versions`, and cites committed logs
      whose sha256 is the recorded `output_sha256`; its lane-gate log shows
      the pinned VM banner and a zero-failure full suite.

  Deleting the receipt or a log, editing a log, or bumping `.tool-versions`
  without a new pinned qualification fails the suite (standing holds only
  within its validity scope: the pin it was observed under).

  Chicago-style: the real checkout files (`.tool-versions`,
  `.github/workflows/ci.yml`, the committed receipt and its logs), real
  sha256 over their real bytes, the real `Bootstrap.Receipts.check/1` and the
  real running VM; no test doubles.
  """
  use ExUnit.Case, async: true

  alias GgenIgniter.SemanticJira.Bootstrap.Receipts

  @root Path.expand("..", __DIR__)
  @receipt "receipts/v26.9.23/R1-GI-PIN.json"
  @lane_gate_role "lane gate on committed head"

  describe "running VM and CI vs .tool-versions (toolchain pin)" do
    test "the running VM is the .tool-versions pin (else BUILD_BROKEN(toolchain))" do
      pin = pin()
      vm = running_vm()

      assert Map.take(vm, [:elixir, :elixir_otp, :erlang]) ==
               Map.take(pin, [:elixir, :elixir_otp, :erlang]),
             "BUILD_BROKEN(toolchain): running Elixir #{vm.elixir} (compiled with OTP " <>
               "#{vm.elixir_otp}) on Erlang/OTP #{vm.erlang}; .tool-versions pins elixir " <>
               "#{pin.elixir_tool}, erlang #{pin.erlang} -- run under the pin (as CI does)"
    end

    test "CI's setup-beam step pins the .tool-versions toolchain" do
      pin = pin()
      ci = @root |> Path.join(".github/workflows/ci.yml") |> File.read!()

      assert ci =~ "elixir-version: '#{pin.elixir}'"
      assert ci =~ "otp-version: '#{pin.erlang}'"
    end
  end

  describe "Receipts.check/1 and cited logs (receipts/v26.9.23/R1-GI-PIN.json)" do
    test "the pinned-qualification receipt is R-schema admitted and ALIVE at an exact subject" do
      receipt = receipt()

      assert Receipts.check(receipt) == []
      assert receipt["standing"]["value"] == "ALIVE"
      assert receipt["identity"]["subject_sha"] =~ ~r/\A[0-9a-f]{40}\z/
    end

    test "the receipt's toolchain identity is the .tool-versions pin" do
      pin = pin()
      toolchain = receipt()["toolchain"]

      assert toolchain["tool_versions_pin_used"] == true
      assert toolchain["elixir"] == banner(pin)
      assert toolchain["otp_release"] == pin.erlang_major
      assert toolchain["otp_version"] == pin.erlang

      assert toolchain["pin_source"] ==
               ".tool-versions: elixir #{pin.elixir_tool}, erlang #{pin.erlang}"
    end

    test "every log the receipt cites is committed and hashes to its recorded sha256" do
      receipt = receipt()
      toolchain = receipt["toolchain"]

      cited =
        [{toolchain["build_identity_log"], toolchain["build_identity_sha256"]}] ++
          for entry <- receipt["replay"]["commands"] ++ Map.get(receipt, "falsifiers", []),
              is_binary(entry["log"]),
              do: {entry["log"], entry["output_sha256"]}

      assert length(cited) >= 3

      for {log, recorded} <- cited do
        path = Path.join(@root, log)
        assert File.regular?(path), "cited log #{log} is not committed"

        assert sha256(File.read!(path)) == recorded,
               "cited log #{log} does not hash to #{recorded}"
      end
    end

    test "the lane-gate log is a zero-failure full suite on the pinned VM" do
      pin = pin()
      commands = receipt()["replay"]["commands"]
      gates = Enum.filter(commands, &(&1["role"] == @lane_gate_role))

      assert [gate] = gates
      assert gate["exit"] == 0
      assert gate["cmd"] =~ "/elixir/#{pin.elixir_tool}/bin"
      assert gate["cmd"] =~ "/erlang/#{pin.erlang}/bin"
      assert gate["cmd"] =~ "mix format --check-formatted"
      assert gate["cmd"] =~ "mix compile --warnings-as-errors --force"
      assert gate["cmd"] =~ "mix credo && mix test"

      log = @root |> Path.join(gate["log"]) |> File.read!()

      assert log =~ "Erlang/OTP #{pin.erlang_major} ["
      assert log =~ banner(pin)
      assert log =~ ~r/^\d+ doctests?, \d+ properties, \d+ tests?, 0 failures\b/m
      assert log =~ ~r/^# ended=\S+ exit=0$/m
    end
  end

  # `.tool-versions` -> %{elixir_tool: "1.18.4-otp-27", elixir: "1.18.4",
  # elixir_otp: "27", erlang: "27.2.4", erlang_major: "27"}.
  defp pin do
    tools =
      for line <- @root |> Path.join(".tool-versions") |> File.read!() |> String.split("\n"),
          [tool, version | _] <- [String.split(line)],
          into: %{},
          do: {tool, version}

    [_, elixir, elixir_otp] = Regex.run(~r/\A(\d+\.\d+\.\d+)-otp-(\d+)\z/, tools["elixir"])
    erlang = tools["erlang"]

    %{
      elixir_tool: tools["elixir"],
      elixir: elixir,
      elixir_otp: elixir_otp,
      erlang: erlang,
      erlang_major: erlang |> String.split(".") |> hd()
    }
  end

  defp running_vm do
    otp_release = :otp_release |> :erlang.system_info() |> List.to_string()

    otp_version =
      [List.to_string(:code.root_dir()), "releases", otp_release, "OTP_VERSION"]
      |> Path.join()
      |> File.read!()
      |> String.trim()

    %{
      elixir: System.version(),
      elixir_otp: System.build_info()[:otp_release],
      erlang: otp_version
    }
  end

  defp banner(pin), do: "Elixir #{pin.elixir} (compiled with Erlang/OTP #{pin.elixir_otp})"

  defp receipt do
    @root |> Path.join(@receipt) |> File.read!() |> Jason.decode!()
  end

  defp sha256(bytes), do: :sha256 |> :crypto.hash(bytes) |> Base.encode16(case: :lower)
end
