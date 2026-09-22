defmodule Mix.Tasks.GgenIgniter.PackFetchTaskTest do
  @moduledoc """
  Chicago-style tests for `mix ggen_igniter.pack.fetch`, the CLI wiring around
  `GgenIgniter.Pack.fetch_pack!/2` (see `lib/mix/tasks/ggen_igniter.pack.fetch.ex`).
  Real `System.cmd("mix", [...])` subprocess against THIS project's own real
  compiled task -- no mocked HTTP layer, no mocked `Pack` module.

  Invalid-invocation and bad-spec cases need no network and always run.
  The real successful-fetch case hits GitHub's real archive endpoint (same
  fixture repo `test/ggen_igniter_pack_fetch_test.exs` already uses) and is
  tagged `:requires_network`, same convention as that file.
  """
  use ExUnit.Case, async: true

  @cache_dir_base Path.join(System.tmp_dir!(), "ggen_igniter_pack_fetch_task_test")

  defp run_task(args, cd \\ File.cwd!()) do
    System.cmd("mix", ["ggen_igniter.pack.fetch" | args], cd: cd, stderr_to_stdout: true)
  end

  # `--json` output is pretty-printed (multi-line), and stdout/stderr are
  # interleaved with Mix's own compiler warnings via `stderr_to_stdout: true`
  # -- taking the LAST line truncates a pretty-printed object to its closing
  # `}` alone. Nor is "first `{`" sound: BEAM alarm_handler notices such as
  # `{:set, {{:disk_almost_full, ...}, []}}` (emitted on a host with a
  # nearly-full volume) start with `{` and contain `}` themselves. The JSON
  # document is the payload starting at a column-0 `{` line and ending at the
  # last line containing `}`; try each candidate start in order and return the
  # first slice that really decodes as a JSON object (falling back to the last
  # candidate so a genuine failure still surfaces as a real Jason error).
  defp extract_json(output) do
    lines = String.split(output, "\n")

    stop =
      lines
      |> Enum.with_index()
      |> Enum.filter(fn {line, _} -> String.contains?(line, "}") end)
      |> List.last()
      |> elem(1)

    candidates =
      for {line, i} <- Enum.with_index(lines), i <= stop, String.starts_with?(line, "{") do
        lines |> Enum.slice(i..stop) |> Enum.join("\n")
      end

    Enum.find(candidates, List.last(candidates), fn c ->
      match?({:ok, %{}}, Jason.decode(c))
    end)
  end

  describe "invalid invocation" do
    test "exits 2 with no <spec> positional argument" do
      {output, code} = run_task([])

      assert code == 2
      assert output =~ "usage: mix ggen_igniter.pack.fetch <spec>"
    end

    test "exits 2 on an unrecognized flag" do
      {output, code} = run_task(["hex:jason", "--bogus-flag"])

      assert code == 2
      assert output =~ "unrecognized flag"
    end

    test "--json invalid invocation emits parseable JSON with an error key" do
      {output, code} = run_task(["--json"])

      assert code == 2
      assert {:ok, %{"error" => _}} = Jason.decode(extract_json(output))
    end
  end

  describe "fetch failure (real Pack.fetch_pack!/2 raise, no network needed)" do
    test "exits 1 and reports the real ArgumentError message on a bad spec" do
      cache_dir = unique_cache_dir()
      on_exit(fn -> File.rm_rf!(cache_dir) end)

      {output, code} = run_task(["npm:left-pad", "--cache-dir", cache_dir])

      assert code == 1
      assert output =~ "unrecognized pack spec"
      refute File.dir?(cache_dir |> Path.join("npm-left-pad"))
    end

    test "--json fetch failure emits parseable JSON with an error key" do
      cache_dir = unique_cache_dir()
      on_exit(fn -> File.rm_rf!(cache_dir) end)

      {output, code} = run_task(["npm:left-pad", "--cache-dir", cache_dir, "--json"])

      assert code == 1

      assert {:ok, %{"error" => message, "spec" => "npm:left-pad"}} =
               Jason.decode(extract_json(output))

      assert message =~ "unrecognized pack spec"
    end
  end

  describe "real successful fetch" do
    @tag :requires_network
    test "fetches a real public GitHub repo and prints the resolved path" do
      cache_dir = unique_cache_dir()
      on_exit(fn -> File.rm_rf!(cache_dir) end)

      {output, code} =
        run_task(["github:octocat/Hello-World@master", "--cache-dir", cache_dir])

      expected_dest = Path.join(cache_dir, "github-octocat-Hello-World-master")

      assert code == 0
      assert output =~ expected_dest
      assert File.dir?(expected_dest)
      assert "README" in File.ls!(expected_dest)
    end

    @tag :requires_network
    test "--json success emits a parseable JSON object with spec and path" do
      cache_dir = unique_cache_dir()
      on_exit(fn -> File.rm_rf!(cache_dir) end)

      {output, code} =
        run_task(["github:octocat/Hello-World@master", "--cache-dir", cache_dir, "--json"])

      expected_dest = Path.join(cache_dir, "github-octocat-Hello-World-master")

      assert code == 0

      assert {:ok, %{"spec" => "github:octocat/Hello-World@master", "path" => path}} =
               Jason.decode(extract_json(output))

      assert path == expected_dest
    end
  end

  defp unique_cache_dir do
    Path.join(@cache_dir_base, "run_#{System.unique_integer([:positive])}")
  end
end
