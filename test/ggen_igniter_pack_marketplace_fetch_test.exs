defmodule GgenIgniter.PackMarketplaceFetchTest do
  @moduledoc """
  Chicago-style: real tar.gz archives built on disk with `:erl_tar`, extracted
  by the real `GgenIgniter.Pack.extract_archive!/3` into real tmp dirs, and
  real `Pack.resolve_dir!/1` / `Pack.missing_dir_message/1` lookups against
  real directories (including this package's own shipped `priv/ggen`). No
  network: GitHub's archive endpoint is blocked in CI sandboxes, so the
  monorepo `github:owner/repo[@ref]#subpath` logic is exercised on a
  locally-built archive shaped exactly like GitHub's (one top-level
  `<repo>-<ref>/` directory). No test doubles.
  """
  use ExUnit.Case, async: true

  alias GgenIgniter.Pack

  setup do
    root =
      Path.join(
        System.tmp_dir!(),
        "ggen_igniter_pack_marketplace_fetch_#{System.unique_integer([:positive])}"
      )

    File.rm_rf!(root)
    File.mkdir_p!(root)
    on_exit(fn -> File.rm_rf!(root) end)
    {:ok, root: root}
  end

  # Builds a GitHub-shaped archive: everything under `repo-main/`.
  defp build_archive!(root, files) do
    src = Path.join(root, "src")
    File.mkdir_p!(src)

    for {rel, content} <- files do
      path = Path.join([src, "repo-main", rel])
      File.mkdir_p!(Path.dirname(path))
      File.write!(path, content)
    end

    archive = Path.join(root, "archive.tar.gz")

    :ok =
      :erl_tar.create(
        to_charlist(archive),
        [{~c"repo-main", to_charlist(Path.join(src, "repo-main"))}],
        [:compressed]
      )

    File.read!(archive)
  end

  describe "parse_spec/1 (monorepo subpath)" do
    test "github spec without subpath keeps subpath nil" do
      assert Pack.parse_spec("github:o/r") == {:github, "o", "r", "main", nil}
      assert Pack.parse_spec("github:o/r@v1") == {:github, "o", "r", "v1", nil}
    end

    test "github spec with #subpath and //subpath" do
      assert Pack.parse_spec("github:o/r@main#packs/ash-extension-pack") ==
               {:github, "o", "r", "main", "packs/ash-extension-pack"}

      assert Pack.parse_spec("github:o/r#packs/x") == {:github, "o", "r", "main", "packs/x"}
      assert Pack.parse_spec("github:o/r//packs/x") == {:github, "o", "r", "main", "packs/x"}
      assert Pack.parse_spec("github:o/r@dev//packs/x") == {:github, "o", "r", "dev", "packs/x"}
    end

    test "empty subpath after # is refused as an unrecognized spec" do
      assert Pack.parse_spec("github:o/r#") == :error
    end
  end

  describe "extract_archive!/3 with subpath" do
    test "returns the subdirectory as the pack root", %{root: root} do
      body =
        build_archive!(root, [
          {"packs/ash-extension-pack/pack.toml", "[pack]\n"},
          {"packs/ash-extension-pack/templates/a.tmpl", "A"},
          {"packs/other/pack.toml", "other"},
          {"README.md", "top"}
        ])

      dest = Path.join(root, "dest")

      assert Pack.extract_archive!(body, dest,
               strip_top_dir: true,
               subpath: "packs/ash-extension-pack"
             ) == dest

      assert File.read!(Path.join(dest, "pack.toml")) == "[pack]\n"
      assert File.read!(Path.join(dest, "templates/a.tmpl")) == "A"
      refute File.exists?(Path.join(dest, "README.md"))
      refute File.exists?(Path.join(dest, "packs"))
    end

    test "no subpath keeps the whole repo as the root (unchanged behaviour)", %{root: root} do
      body = build_archive!(root, [{"packs/x/pack.toml", "x"}, {"README.md", "top"}])
      dest = Path.join(root, "dest")
      Pack.extract_archive!(body, dest, strip_top_dir: true)
      assert File.exists?(Path.join(dest, "README.md"))
      assert File.exists?(Path.join(dest, "packs/x/pack.toml"))
    end

    test "a missing subpath raises naming the subpath", %{root: root} do
      body = build_archive!(root, [{"packs/x/pack.toml", "x"}])

      assert_raise ArgumentError, ~r/subpath "packs\/nope" not found/, fn ->
        Pack.extract_archive!(body, Path.join(root, "dest"),
          strip_top_dir: true,
          subpath: "packs/nope"
        )
      end
    end

    test "path traversal in subpath is refused and nothing outside dest is written", %{
      root: root
    } do
      body = build_archive!(root, [{"packs/x/pack.toml", "x"}])
      File.write!(Path.join(root, "secret.txt"), "secret")

      for bad <- ["../..", "packs/../../..", "/etc", "packs/x/../../../src", ".."] do
        dest = Path.join(root, "dest_#{System.unique_integer([:positive])}")

        assert_raise ArgumentError, ~r/refusing subpath/, fn ->
          Pack.extract_archive!(body, dest, strip_top_dir: true, subpath: bad)
        end

        refute File.exists?(dest)
      end
    end

    test "an archive carrying a symlink out of the extraction dir is refused", %{root: root} do
      outside = Path.join(root, "outside")
      File.mkdir_p!(outside)
      File.write!(Path.join(outside, "pack.toml"), "outside")

      src = Path.join(root, "symsrc/repo-main")
      File.mkdir_p!(src)
      File.write!(Path.join(src, "ok.txt"), "ok")
      :ok = File.ln_s(outside, Path.join(src, "escape"))

      archive = Path.join(root, "sym.tar.gz")

      :ok =
        :erl_tar.create(to_charlist(archive), [{~c"repo-main", to_charlist(src)}], [:compressed])

      assert_raise ArgumentError, ~r/refusing (archive|subpath)/, fn ->
        Pack.extract_archive!(File.read!(archive), Path.join(root, "dest"),
          strip_top_dir: true,
          subpath: "escape"
        )
      end
    end
  end

  describe "pack.fetch docs" do
    test "moduledoc states the consumer needs :tesla" do
      {:docs_v1, _, _, _, %{"en" => moduledoc}, _, _} = Code.fetch_docs(GgenIgniter.Pack)
      assert moduledoc =~ "{:tesla,"
      assert moduledoc =~ "#packs/"

      {:docs_v1, _, _, _, %{"en" => task_doc}, _, _} =
        Code.fetch_docs(Mix.Tasks.GgenIgniter.Pack.Fetch)

      assert task_doc =~ "{:tesla,"
    end
  end

  describe "resolve_dir!/1 for --pack NAME (cwd-relative, then shipped fallback)" do
    test "cwd-relative priv/ggen/NAME wins when it exists" do
      assert Pack.resolve_dir!(pack: "semantic-jira-pack") ==
               Path.join(["priv", "ggen", "semantic-jira-pack"])
    end

    test "falls back to the shipped package path when the cwd has no such pack", %{root: root} do
      File.cd!(root, fn ->
        resolved = Pack.resolve_dir!(pack: "semantic-jira-pack")
        assert resolved == Path.join(:code.priv_dir(:ggen_igniter), "ggen/semantic-jira-pack")
        assert File.exists?(Path.join(resolved, "ontology.ttl"))
      end)
    end

    test "unknown pack: message names the searched path AND the shipped path", %{root: root} do
      File.cd!(root, fn ->
        dir = Pack.resolve_dir!(pack: "no-such-pack-xyz")
        message = Pack.missing_dir_message(pack: "no-such-pack-xyz")

        assert is_binary(message)
        assert message =~ "pack directory #{dir} does not exist"
        assert message =~ Path.join(["priv", "ggen", "no-such-pack-xyz"])
        assert message =~ Path.join(:code.priv_dir(:ggen_igniter), "ggen/no-such-pack-xyz")
      end)
    end

    test "existing pack dir yields no missing-dir message" do
      assert Pack.missing_dir_message(pack: "semantic-jira-pack") == nil
      assert Pack.missing_dir_message(pack_dir: "test/fixtures/sample-pack") == nil
    end

    test "explicit missing --pack-dir is named" do
      message = Pack.missing_dir_message(pack_dir: "/nonexistent/pack/dir")
      assert message =~ "/nonexistent/pack/dir"
    end
  end
end
