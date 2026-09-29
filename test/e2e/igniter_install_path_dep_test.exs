defmodule GgenIgniter.E2e.IgniterInstallPathDepTest do
  @moduledoc """
  Chicago-style: real `mix new` consumer project in a real tmp dir, real `mix deps.get`
  (HEX_OFFLINE=1 against the local hex cache first, one online read-only retry), a real
  compile of the `{:ggen_igniter, path: <this repo>}` dependency, and real
  `mix ggen_igniter.install` subprocesses. Assertions are on the bytes the installer wrote
  (`.formatter.exs`, `mix.exs`, `config/config.exs`, `lib/demo/application.ex`) and on
  exit codes -- no test doubles.

  Why `mix ggen_igniter.install` and not `mix igniter.install ggen_igniter`: measured
  2026-09-28 (docs/jira/v26.9.28/install-e2e-report.md), `igniter.install <pkg>` treats the
  package as a Hex package and rewrites an existing path dep to `{:ggen_igniter, "~> 26.0"}`
  (unpublished), so the installer task itself is exercised directly once the path dep is
  present, which is the sequence `igniter.install` runs after adding the dep.

  Tagged `:integration` (excluded from the default fast lane; slow: compiles the whole dep
  tree). Skips with a named reason when `mix`, the hex cache, or the repo's `deps/igniter`
  is unavailable; a resolution failure after the online retry fails with `BLOCKED: <error>`.
  """

  use ExUnit.Case, async: false

  @repo Path.expand("../..", __DIR__)

  @skip_reason (cond do
                  System.find_executable("mix") == nil ->
                    "SKIP(toolchain): `mix` not on PATH"

                  not File.dir?(Path.expand("~/.hex/packages")) ->
                    "SKIP(hex-cache): ~/.hex/packages missing; offline resolution impossible"

                  not File.dir?(Path.join(@repo, "deps/igniter")) ->
                    "SKIP(repo-deps): #{@repo}/deps/igniter missing (run mix deps.get in the repo)"

                  true ->
                    nil
                end)

  @moduletag :integration
  @moduletag :e2e
  @moduletag timeout: 1_800_000
  if @skip_reason, do: @moduletag(skip: @skip_reason)

  setup do
    dir =
      Path.join(System.tmp_dir!(), "ggen_igniter_w5_#{System.unique_integer([:positive])}")

    File.rm_rf!(dir)
    File.mkdir_p!(dir)
    on_exit(fn -> File.rm_rf!(dir) end)
    {:ok, dir: dir}
  end

  defp mix(project, args, extra_env) do
    t0 = System.monotonic_time(:millisecond)

    {out, code} =
      System.cmd("mix", args,
        cd: project,
        stderr_to_stdout: true,
        env:
          [
            {"MIX_BUILD_ROOT", Path.join(Path.dirname(project), "_build")},
            {"MIX_ENV", "dev"},
            {"MIX_DEPS_PATH", nil},
            {"MIX_TARGET", nil}
          ] ++ extra_env
      )

    elapsed = System.monotonic_time(:millisecond) - t0
    IO.puts("[w5] mix #{Enum.join(args, " ")} -> exit #{code} in #{elapsed}ms")
    {out, code}
  end

  defp make_consumer(dir) do
    {_, 0} = System.cmd("mix", ["new", "demo", "--sup"], cd: dir, stderr_to_stdout: true)
    project = Path.join(dir, "demo")
    mix_exs = Path.join(project, "mix.exs")

    File.write!(
      mix_exs,
      mix_exs
      |> File.read!()
      |> String.replace(
        "# {:dep_from_hexpm",
        "{:igniter, \"~> 0.8\"},\n      {:ggen_igniter, path: #{inspect(@repo)}}\n      # {:dep_from_hexpm",
        global: false
      )
    )

    project
  end

  defp resolve!(project) do
    case mix(project, ["deps.get"], [{"HEX_OFFLINE", "1"}]) do
      {_, 0} ->
        :offline

      {offline_out, _} ->
        case mix(project, ["deps.get"], [{"HEX_OFFLINE", "0"}]) do
          {_, 0} ->
            :online

          {online_out, code} ->
            flunk(
              "BLOCKED: deps.get failed offline and online (exit #{code}).\n" <>
                "offline: #{String.slice(offline_out, -600, 600)}\nonline: #{String.slice(online_out, -600, 600)}"
            )
        end
    end
  end

  test "mix ggen_igniter.install on a path-dep consumer: import_deps, idempotent rerun, ash wiring",
       %{dir: dir} do
    project = make_consumer(dir)
    formatter = Path.join(project, ".formatter.exs")
    mix_exs = Path.join(project, "mix.exs")
    config = Path.join(project, "config/config.exs")
    app = Path.join(project, "lib/demo/application.ex")

    resolve!(project)
    {out, 0} = mix(project, ["compile"], [{"HEX_OFFLINE", "1"}])
    assert out =~ "Generated demo app"

    refute File.read!(formatter) =~ ":ggen_igniter"

    # Stage 1: thin install.
    {out1, code1} = mix(project, ["ggen_igniter.install", "--yes"], [{"HEX_OFFLINE", "1"}])
    assert code1 == 0, out1
    fmt1 = File.read!(formatter)
    assert fmt1 =~ ~r/import_deps:\s*\[[^\]]*:ggen_igniter/
    mix1 = File.read!(mix_exs)
    refute mix1 =~ ":ash,"

    # Stage 2: rerun is a byte-level no-op.
    {out2, code2} = mix(project, ["ggen_igniter.install", "--yes"], [{"HEX_OFFLINE", "1"}])
    assert code2 == 0, out2
    assert File.read!(formatter) == fmt1
    assert File.read!(mix_exs) == mix1
    refute File.exists?(config) and File.read!(config) =~ "ash_domains"

    # Stage 3: opt-in Ash wiring touches mix.exs, config, and the supervision tree.
    {out3, code3} =
      mix(project, ["ggen_igniter.install", "--with-ash-domain", "--yes"], [
        {"HEX_OFFLINE", "1"}
      ])

    assert code3 == 0, out3
    assert File.read!(mix_exs) =~ ~r/\{:ash,\s*"~> 3\.0"\}/
    assert File.read!(config) =~ "ash_domains"
    assert File.read!(config) =~ "Demo.Ash.Domain"
    assert File.read!(app) =~ "Demo.Ash.Domain"
    assert File.read!(formatter) == fmt1
  end
end
