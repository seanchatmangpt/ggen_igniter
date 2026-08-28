defmodule GgenIgniter.PackFetchTest do
  @moduledoc """
  Chicago-style tests for `GgenIgniter.Pack.fetch_pack!/2` against REAL public
  HTTP endpoints -- GitHub's archive endpoint and hex.pm/repo.hex.pm -- no
  mocked HTTP layer. Tagged `:requires_network`, same pattern as
  `:requires_qlever_server` in `test/ggen_igniter_sync_qlever_engine_test.exs`
  and `test/ash_r2rml_gate_qlever_test.exs`, so `mix test --exclude
  requires_network` runs clean offline/in CI without network access.

  `octocat/Hello-World` (GitHub's own canonical minimal public test repo) and
  `jason` on hex.pm are used as small, stable, real fixtures -- not fabricated
  registries.
  """
  use ExUnit.Case, async: true

  alias GgenIgniter.Pack

  setup do
    cache_dir =
      Path.join(
        System.tmp_dir!(),
        "ggen_igniter_pack_fetch_test_#{System.unique_integer([:positive])}"
      )

    File.rm_rf!(cache_dir)
    on_exit(fn -> File.rm_rf!(cache_dir) end)
    {:ok, cache_dir: cache_dir}
  end

  describe "fetch_pack!/2 spec parsing" do
    test "raises ArgumentError on an unrecognized spec", %{cache_dir: cache_dir} do
      assert_raise ArgumentError, ~r/unrecognized pack spec/, fn ->
        Pack.fetch_pack!("npm:left-pad", cache_dir: cache_dir)
      end
    end

    test "raises ArgumentError on a malformed github spec (missing repo)", %{cache_dir: cache_dir} do
      assert_raise ArgumentError, ~r/unrecognized pack spec/, fn ->
        Pack.fetch_pack!("github:owner-only", cache_dir: cache_dir)
      end
    end
  end

  describe "fetch_pack!/2 with github: (real HTTP GET, print-only verification)" do
    @tag :requires_network
    test "downloads and extracts a real public GitHub repo archive", %{cache_dir: cache_dir} do
      dest = Pack.fetch_pack!("github:octocat/Hello-World@master", cache_dir: cache_dir)

      assert dest == Path.join(cache_dir, "github-octocat-Hello-World-master")
      assert File.dir?(dest)

      # The top-level "Hello-World-master/" wrapper directory from GitHub's
      # archive must be stripped, so real repo files sit directly in `dest`.
      entries = File.ls!(dest)
      assert entries != []
      refute Enum.any?(entries, &String.starts_with?(&1, "Hello-World"))
      assert "README" in entries
    end

    @tag :requires_network
    test "re-fetching the same spec replaces the previous extraction cleanly", %{
      cache_dir: cache_dir
    } do
      dest1 = Pack.fetch_pack!("github:octocat/Hello-World@master", cache_dir: cache_dir)
      File.write!(Path.join(dest1, "stale-marker.txt"), "should be gone after re-fetch")

      dest2 = Pack.fetch_pack!("github:octocat/Hello-World@master", cache_dir: cache_dir)

      assert dest1 == dest2
      refute "stale-marker.txt" in File.ls!(dest2)
    end
  end

  describe "fetch_pack!/2 with hex: (real HTTP GET, fail-closed checksum verification)" do
    @tag :requires_network
    test "downloads, verifies, and extracts a real hex.pm package tarball", %{
      cache_dir: cache_dir
    } do
      dest = Pack.fetch_pack!("hex:jason@1.4.1", cache_dir: cache_dir)

      assert dest == Path.join(cache_dir, "hex-jason-1.4.1")
      assert File.dir?(dest)

      # contents.tar.gz for jason 1.4.1 is a real Elixir package source tree.
      assert File.exists?(Path.join(dest, "mix.exs"))
      assert File.dir?(Path.join(dest, "lib"))
    end

    @tag :requires_network
    test "resolves the latest stable version when none is given", %{cache_dir: cache_dir} do
      dest = Pack.fetch_pack!("hex:jason", cache_dir: cache_dir)

      assert File.dir?(dest)
      assert File.exists?(Path.join(dest, "mix.exs"))
      assert String.starts_with?(Path.basename(dest), "hex-jason-")
    end

    @tag :requires_network
    test "the extracted pack directory is usable directly with resolve_dir!/1", %{
      cache_dir: cache_dir
    } do
      dest = Pack.fetch_pack!("hex:jason@1.4.1", cache_dir: cache_dir)

      assert Pack.resolve_dir!(pack_dir: dest) == dest
    end
  end

  describe "fetch_pack!/2 against a real nonexistent target (real 404, not a leaked raw HTTP/Tesla error)" do
    @tag :requires_network
    test "github: with a real nonexistent owner/repo names the spec, the URL tried, and next steps",
         %{cache_dir: cache_dir} do
      spec = "github:ggen-igniter-nonexistent-owner-f3a91c7d/nonexistent-repo-8e2b5a10"

      message =
        try do
          Pack.fetch_pack!(spec, cache_dir: cache_dir)
          flunk("expected fetch_pack!/2 to raise for a nonexistent github spec")
        rescue
          e -> Exception.message(e)
        end

      assert message =~ "HTTP 404"
      assert message =~ spec |> String.replace("github:", "") |> String.split("@") |> hd()
      assert message =~ "user-correctable"
      refute message =~ "Tesla.Env"
      refute message =~ "%HTTPoison"
    end

    @tag :requires_network
    test "hex: with a real nonexistent package name names the package and next steps", %{
      cache_dir: cache_dir
    } do
      name = "ggen-igniter-nonexistent-package-c9f2e6b4"
      spec = "hex:#{name}"

      message =
        try do
          Pack.fetch_pack!(spec, cache_dir: cache_dir)
          flunk("expected fetch_pack!/2 to raise for a nonexistent hex package")
        rescue
          e -> Exception.message(e)
        end

      assert message =~ "HTTP 404"
      assert message =~ name
      assert message =~ "user-correctable"
      refute message =~ "Tesla.Env"
      refute message =~ "%HTTPoison"
    end
  end
end
