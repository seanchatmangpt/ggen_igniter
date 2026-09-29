defmodule GgenIgniter.PacksTaskTest do
  @moduledoc """
  Chicago-style, no-mocks proof of `mix ggen_igniter.packs`: a real `mix`
  subprocess runs in this checkout and its real JSON output is compared to a
  real `File.ls("priv/ggen")`, plus real tmp-dir packs (with and without
  `pack.toml`) passed through `--pack-dir`. Assertions are on stdout content and
  exit codes only.
  """
  use ExUnit.Case, async: false

  @moduletag :integration

  defp packs_json(args) do
    {out, 0} = System.cmd("mix", ["ggen_igniter.packs", "--json" | args], stderr_to_stdout: false)
    Jason.decode!(out |> String.split("\n", trim: true) |> List.last())
  end

  test "--json is structurally valid and lists every priv/ggen dir that has an ontology.ttl (others may also be listed)" do
    doc = packs_json([])
    assert doc["schema_version"] == 1

    for p <- doc["packs"] do
      assert Enum.all?(
               ~w(name version description dir ontology gates templates required_flags hex_shipped metadata_source origin),
               &Map.has_key?(p, &1)
             )
    end

    expected =
      "priv/ggen"
      |> File.ls!()
      |> Enum.filter(&File.regular?(Path.join(["priv/ggen", &1, "ontology.ttl"])))
      |> Enum.sort()

    listed = doc["packs"] |> Enum.map(&Path.basename(&1["dir"])) |> Enum.sort()
    assert expected -- listed == []
    assert Enum.sort(listed) == listed |> Enum.uniq() |> Enum.sort()
    assert Enum.map(doc["packs"], & &1["dir"]) == Enum.sort(Enum.map(doc["packs"], & &1["dir"]))
  end

  test "hex_shipped mirrors mix.exs shipped_packs (ash-named excluded)" do
    by = Map.new(packs_json([])["packs"], &{Path.basename(&1["dir"]), &1})
    assert by["ash-igniter-api-pack"]["hex_shipped"] == false
    assert by["semantic-jira-pack"]["hex_shipped"] == true
    assert by["semantic-jira-pack"]["version"] != nil
    assert by["adr-index-pack"]["metadata_source"] == "inferred"
    assert by["adr-index-pack"]["version"] == nil
    assert by["semantic-jira-pack"]["gates"] != []
    assert Enum.all?(by["semantic-jira-pack"]["templates"], &Map.has_key?(&1, "to"))
  end

  test "--name filters and unknown --name exits 2" do
    assert [%{"name" => "semantic-jira-pack"}] =
             packs_json(["--name", "semantic-jira-pack"])["packs"]

    {out, code} =
      System.cmd("mix", ["ggen_igniter.packs", "--name", "no-such-pack"], stderr_to_stdout: true)

    assert code == 2
    assert out =~ "unknown pack"
  end

  test "--pack-dir adds external packs, tolerating a missing pack.toml, and is never hex-shipped" do
    root = Path.join(System.tmp_dir!(), "packs_task_#{System.unique_integer([:positive])}")
    File.mkdir_p!(Path.join(root, "mine/templates"))
    File.mkdir_p!(Path.join(root, "mine/gates"))
    File.write!(Path.join(root, "mine/ontology.ttl"), "")
    File.write!(Path.join(root, "mine/gates/010_a.rq"), "SELECT * WHERE { ?s ?p ?o }")
    File.write!(Path.join(root, "mine/templates/x.eex"), "---\nto: out/x.txt\n---\nhi")
    on_exit(fn -> File.rm_rf!(root) end)

    mine = Enum.find(packs_json(["--pack-dir", root])["packs"], &(&1["name"] == "mine"))
    assert mine["hex_shipped"] == false
    assert mine["origin"] == "pack_dir"
    assert mine["version"] == nil
    assert [%{"name" => "a"}] = mine["gates"]
    assert [%{"stem" => "x", "to" => "out/x.txt"}] = mine["templates"]
  end

  test "human table exits 0 and names packs" do
    {out, 0} = System.cmd("mix", ["ggen_igniter.packs"], stderr_to_stdout: false)
    assert out =~ "semantic-jira-pack"
  end

  test "P1: malformed template frontmatter surfaces frontmatter_error" do
    root = Path.join(System.tmp_dir!(), "packs_fm_#{System.unique_integer([:positive])}")
    File.mkdir_p!(Path.join(root, "bad/templates"))
    File.write!(Path.join(root, "bad/ontology.ttl"), "")
    t = Path.join(root, "bad/templates")
    File.write!(Path.join(t, "yaml.eex"), "---\nto: [unclosed\n  : : :\n---\nbody")
    File.write!(Path.join(t, "nofence.eex"), "---\nto: out/x.txt\nbody without close")
    File.write!(Path.join(t, "utf8.eex"), <<"---\nto: out/", 255, 254, ".txt\n---\nb">>)
    File.write!(Path.join(t, "ok.eex"), "---\nto: out/ok.txt\n---\nhi")
    on_exit(fn -> File.rm_rf!(root) end)

    bad = Enum.find(packs_json(["--pack-dir", root])["packs"], &(&1["name"] == "bad"))
    by = Map.new(bad["templates"], &{&1["stem"], &1})
    assert is_binary(by["yaml"]["frontmatter_error"])
    assert is_binary(by["nofence"]["frontmatter_error"])
    assert is_binary(by["utf8"]["frontmatter_error"])
    assert by["ok"]["frontmatter_error"] == nil
    assert by["ok"]["to"] == "out/ok.txt"
  end

  test "P2: stray positional args exit 2" do
    {out, code} = System.cmd("mix", ["ggen_igniter.packs", "foo", "bar"], stderr_to_stdout: true)
    assert code == 2
    assert out =~ "unexpected positional"
  end

  test "P3: schema_version is the first JSON key and output is byte-identical across runs" do
    {a, 0} = System.cmd("mix", ["ggen_igniter.packs", "--json"], stderr_to_stdout: false)
    {b, 0} = System.cmd("mix", ["ggen_igniter.packs", "--json"], stderr_to_stdout: false)
    line = a |> String.split("\n", trim: true) |> List.last()
    assert String.starts_with?(line, ~s({"schema_version":1,"packs":))
    assert a == b
  end
end
