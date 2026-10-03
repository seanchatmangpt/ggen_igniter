defmodule GgenIgniter.ToolchainPinQualificationTest do
  @moduledoc """
  GC23-11 exact-head qualification under this repository's own
  `.tool-versions` pin (PRD section 12 GC23-11 and PR-013; ARD section 20
  `BUILD_BROKEN(toolchain)`, section 25 verification ladder, section 27
  toolchain identity). Release defect lane R1-GI-PIN, repair round 1;
  re-qualified at v26.10.2 as lane D8 (`R2-GI-PIN`) after the pin moved.

  The pin moved 1.18.4-otp-27 -> 1.19.5-otp-27 in the v26.10.2 epoch
  (ash_a2a 26.9.31 requires elixir "~> 1.19"; 1.18.4 can no longer compile
  the dep tree). The v26.9.23 qualification
  (`receipts/v26.9.23/R1-GI-PIN.json`) was observed under the OLD pin and
  refuses under fleet R v2 with typed reasons -- committed evidence, never
  edited to chase a schema. The v26.10.2 re-qualification
  (`receipts/v26.10.2/R2-GI-PIN.json`) was observed under the NEW pin and
  ADMITS clean under `Bootstrap.Receipts.check/1` (it carries the v2 keys
  and namespaced extensions). These tests make the suite consume both:

    * the running VM is the pin, so a green full suite is a pinned run (an
      ambient run fails, typed `BUILD_BROKEN(toolchain)`), and CI's
      setup-beam pin is the `.tool-versions` pin;
    * the v26.10.2 pinned-qualification receipt is structurally admitted
      (`check/1 == []`), records the pin read from `.tool-versions`, and
      cites committed logs whose sha256 is the recorded `output_sha256`; its
      lane-gate log shows the pinned VM banner and a zero-failure full suite
      (with the disclosed zero-test-stub exclusion of this self-referential
      court, logged in the gate log's header);
    * the predecessor v26.9.23 receipt remains as historical evidence: under
      v2 it refuses with exactly the typed reasons (one string per missing
      v2 key plus one reason per un-namespaced top-level extension key).

  Deleting the receipt or a cited log, editing a log, or bumping
  `.tool-versions` without a new pinned qualification fails the suite
  (standing holds only within its validity scope: the pin it was observed
  under).

  Chicago-style: the real checkout files (`.tool-versions`,
  `.github/workflows/ci.yml`, the committed receipts and their logs), real
  sha256 over their real bytes, the real `Bootstrap.Receipts.check/1` and the
  real running VM; no test doubles.
  """
  use ExUnit.Case, async: true

  alias GgenIgniter.SemanticJira.Bootstrap.Receipts

  @root Path.expand("..", __DIR__)
  @receipt "receipts/v26.10.2/R2-GI-PIN.json"
  @predecessor_receipt "receipts/v26.9.23/R1-GI-PIN.json"
  @ext "provider_ext.r2gi"
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

  describe "Receipts.check/1 and cited logs (receipts/v26.10.2/R2-GI-PIN.json)" do
    test "the pinned-qualification receipt admits clean under fleet R v2 (Receipts.check/1 == [])" do
      receipt = receipt()

      # R2-GI-PIN was qualified under the fleet R v2 law: it carries the v2
      # keys (work_order_id / origin_authority / provider /
      # provider_execution_id) and namespaces every extension (toolchain,
      # exclusions, observations, findings) under "provider_ext.r2gi", so the
      # real check/1 admits it with zero errors.
      assert Receipts.check(receipt) == []

      # The recorded standing is unchanged in kind -- the pin moved, the
      # admission law did not.
      assert receipt["standing"]["value"] == "ALIVE"
      assert receipt["identity"]["subject_sha"] =~ ~r/\A[0-9a-f]{40}\z/
    end

    test "the predecessor receipt (receipts/v26.9.23/R1-GI-PIN.json) still refuses under fleet R v2 (typed reasons)" do
      receipt = predecessor_receipt()

      # The predecessor is evidence qualified under the v1-era law; v2's
      # check/1 refuses it with exactly those typed reasons. It is never
      # edited to chase a schema.
      errors = Receipts.check(receipt)

      for key <- ~w(work_order_id origin_authority provider provider_execution_id) do
        assert Enum.any?(errors, &String.contains?(&1, key <> ":")),
               "expected a typed v2 reason naming #{key}, got: #{inspect(errors)}"
      end

      for key <- ~w(falsifiers findings observations toolchain work_order) do
        assert Enum.any?(errors, &String.contains?(&1, "\"#{key}\"")),
               "expected a namespace reason naming #{key}, got: #{inspect(errors)}"
      end

      # The recorded standing is unchanged -- the refusal is about v2
      # admission, not about what the pinned run observed.
      assert receipt["standing"]["value"] == "ALIVE"
      assert receipt["identity"]["subject_sha"] =~ ~r/\A[0-9a-f]{40}\z/
    end

    test "the receipt's toolchain identity is the .tool-versions pin" do
      pin = pin()
      toolchain = receipt()[@ext]["toolchain"]

      assert toolchain["tool_versions_pin_used"] == true
      assert toolchain["elixir"] == banner(pin)
      assert toolchain["otp_release"] == pin.erlang_major
      assert toolchain["otp_version"] == pin.erlang

      assert toolchain["pin_source"] ==
               ".tool-versions: elixir #{pin.elixir_tool}, erlang #{pin.erlang}"
    end

    test "every log the receipt cites is committed and hashes to its recorded sha256" do
      receipt = receipt()
      toolchain = receipt[@ext]["toolchain"]

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

  # `.tool-versions` -> %{elixir_tool: "1.19.5-otp-27", elixir: "1.19.5",
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

  defp predecessor_receipt do
    @root |> Path.join(@predecessor_receipt) |> File.read!() |> Jason.decode!()
  end

  defp sha256(bytes), do: :sha256 |> :crypto.hash(bytes) |> Base.encode16(case: :lower)
end
