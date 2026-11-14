defmodule Mix.Tasks.GgenIgniterSyncPackFrontmatterTest do
  # Real `mix ggen_igniter.sync --pack <dir>` subprocess against a tiny real Tera frontmatter
  # pack built in a temp dir; assertions are on bytes on disk and the process exit code.
  use ExUnit.Case, async: false

  @moduletag :integration

  setup do
    root = Path.join(System.tmp_dir!(), "pf_sync_pack_#{System.unique_integer([:positive])}")
    pack = Path.join(root, "tiny-pack")
    out = Path.join(root, "out")
    File.mkdir_p!(Path.join(pack, "templates"))
    File.mkdir_p!(out)
    on_exit(fn -> File.rm_rf!(root) end)

    File.write!(Path.join(pack, "ontology.ttl"), "@prefix t: <https://example.com/tiny#> .\n")

    File.write!(Path.join(root, "app.ttl"), """
    @prefix t: <https://example.com/tiny#> .
    t:p1 a t:Thing ; t:label "alpha" .
    """)

    File.write!(Path.join([pack, "templates", "thing.txt.tmpl"]), """
    ---
    to: "things/{{ label }}.txt"
    force: true
    sparql:
      things: |
        PREFIX t: <https://example.com/tiny#>
        SELECT ?label WHERE { ?s a t:Thing ; t:label ?label . }
    for_each: things
    ---
    thing={{ label }}
    """)

    {:ok, root: root, pack: pack, out: out, app: Path.join(root, "app.ttl")}
  end

  defp sync(args),
    do: System.cmd("mix", ["ggen_igniter.sync" | args], cd: File.cwd!(), stderr_to_stdout: true)

  test "--pack <dir> on a Tera pack renders bytes to --out", %{pack: pack, out: out, app: app} do
    {output, code} = sync(["--pack", pack, "--ontology", app, "--out", out])
    assert code == 0, output

    assert File.read!(Path.join(out, "things/alpha.txt")) |> String.trim_trailing() ==
             "thing=alpha"
  end

  test "--dry-run via --pack writes nothing", %{pack: pack, out: out, app: app} do
    {output, code} = sync(["--pack", pack, "--ontology", app, "--out", out, "--dry-run"])
    assert code == 0, output
    refute File.exists?(Path.join(out, "things/alpha.txt"))
  end

  test "REFUSED:WRITE_WITHOUT_FORCE maps to exit 1 and leaves the file untouched",
       %{pack: pack, out: out, app: app} do
    tmpl = Path.join([pack, "templates", "thing.txt.tmpl"])
    File.write!(tmpl, String.replace(File.read!(tmpl), "force: true\n", ""))
    target = Path.join(out, "things/alpha.txt")
    File.mkdir_p!(Path.dirname(target))
    File.write!(target, "hand-edited\n")

    {output, code} = sync(["--pack", pack, "--ontology", app, "--out", out])
    assert code == 1, output
    assert output =~ "REFUSED:WRITE_WITHOUT_FORCE"
    assert File.read!(target) == "hand-edited\n"
  end

  test "missing --ontology is an invocation error (exit 2)", %{pack: pack, out: out} do
    {output, code} = sync(["--pack", pack, "--out", out])
    assert code == 2, output
    assert output =~ "--ontology is required"
  end
end
