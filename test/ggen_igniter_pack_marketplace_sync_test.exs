defmodule GgenIgniter.PackMarketplaceSyncTest do
  @moduledoc """
  Chicago-style: real `mix ggen_igniter.sync` subprocesses (real oxigraph NIF,
  real WASM Tera renderer, real reconciliation manifest) against real
  marketplace-shaped fixture packs written to tmp dirs (`pack.toml`,
  `ontology.ttl`, `gates/*.rq`, `templates/*.tmpl` in Tera syntax with
  frontmatter `to: "... {{ var }} ..."`), plus in-process
  `GgenIgniter.Reconcile.run/1` and `GgenIgniter.Render.TeraWasm` calls on real
  files. Assertions are on the files written to disk. No test doubles.

  `async: false`: each test shells out to `mix` in the shared checkout.
  """
  use ExUnit.Case, async: false

  @moduletag :integration

  alias GgenIgniter.Render.TeraWasm

  @ttl """
  @prefix ex: <https://example.org/mp#> .

  ex:a a ex:Spec ; ex:packageName "alpha_pkg" .
  ex:b a ex:Spec ; ex:packageName "beta_pkg" .
  """

  @spec_query """
  PREFIX ex: <https://example.org/mp#>
  SELECT ?package_name WHERE { ?s a ex:Spec ; ex:packageName ?package_name } ORDER BY ?package_name
  """

  setup do
    root =
      Path.join(
        System.tmp_dir!(),
        "ggen_igniter_pack_marketplace_sync_#{System.unique_integer([:positive])}"
      )

    File.rm_rf!(root)
    File.mkdir_p!(root)
    on_exit(fn -> File.rm_rf!(root) end)
    {:ok, root: root}
  end

  defp write_pack!(root, templates) do
    pack = Path.join(root, "pack")
    File.mkdir_p!(Path.join(pack, "templates"))
    File.mkdir_p!(Path.join(pack, "gates"))

    File.write!(Path.join(pack, "pack.toml"), """
    [pack]
    name = "mp-fixture"
    version = "0.1.0"
    description = "marketplace-shaped fixture"
    """)

    File.write!(Path.join(pack, "ontology.ttl"), @ttl)
    File.write!(Path.join(pack, "gates/010_spec.rq"), @spec_query)

    for {name, content} <- templates do
      File.write!(Path.join([pack, "templates", name]), content)
    end

    pack
  end

  defp tera_template(to, body) do
    """
    ---
    to: "#{to}"
    for_each: "spec"
    ---
    #{body}
    """
  end

  defp sync(args, root) do
    System.cmd(
      "mix",
      ["ggen_igniter.sync", "--manifest-dir", root, "--verify-cwd", File.cwd!()] ++ args,
      cd: File.cwd!(),
      stderr_to_stdout: true
    )
  end

  describe "defect 1+2: .tmpl is Tera, frontmatter to: is rendered by the same engine" do
    test ".tmpl frontmatter `to:` with {{ var }} resolves and body renders as Tera", %{root: root} do
      pack =
        write_pack!(root, [
          {"one.txt.tmpl",
           tera_template(
             "#{root}/out/{{ package_name }}/one.txt",
             "pkg={{ package_name | upper }}"
           )}
        ])

      {output, code} = sync(["--pack-dir", pack], root)
      assert code == 0, output

      assert File.read!(Path.join(root, "out/alpha_pkg/one.txt")) =~ "pkg=ALPHA_PKG"
      assert File.read!(Path.join(root, "out/beta_pkg/one.txt")) =~ "pkg=BETA_PKG"
      refute File.exists?(Path.join(root, "out/{{ package_name }}"))
    end

    test "a .tmpl written in EEx syntax (no Tera delimiters) still renders as EEx", %{root: root} do
      pack =
        write_pack!(root, [
          {"eex.txt.tmpl",
           tera_template("#{root}/out/<%= package_name %>.eex.txt", "eex=<%= package_name %>")}
        ])

      {output, code} = sync(["--pack-dir", pack], root)
      assert code == 0, output
      assert File.read!(Path.join(root, "out/alpha_pkg.eex.txt")) =~ "eex=alpha_pkg"
    end

    test ".eex templates keep EEx even when the body contains Tera-looking text", %{root: root} do
      pack =
        write_pack!(root, [
          {"legacy.txt.eex",
           tera_template(
             "#{root}/out/<%= package_name %>.legacy.txt",
             "<%= package_name %> {{ literal }}"
           )}
        ])

      {output, code} = sync(["--pack-dir", pack], root)
      assert code == 0, output
      assert File.read!(Path.join(root, "out/alpha_pkg.legacy.txt")) =~ "alpha_pkg {{ literal }}"
    end

    test "TeraWasm.tera_template?/2: .tera and Tera-syntax .tmpl are Tera; .eex is not" do
      assert TeraWasm.tera_template?("a.txt.tera", "x")
      assert TeraWasm.tera_template?("a.txt.tmpl", "hi {{ x }}")
      assert TeraWasm.tera_template?("a.txt.tmpl", "plain text, no markers")
      assert TeraWasm.tera_template?("a.txt.tmpl", "{% if x %}y{% endif %}")
      refute TeraWasm.tera_template?("a.txt.tmpl", "<%= x %>")
      refute TeraWasm.tera_template?("a.txt.eex", "{{ x }}")
      refute TeraWasm.tera_template?(nil, "{{ x }}")
    end

    test "Reconcile.run/1 renders a .tmpl body and Tera :out through the Tera engine", %{
      root: root
    } do
      pack = write_pack!(root, [{"r.txt.tmpl", "row={{ package_name }}\n"}])
      # single-row query so bindings flatten
      File.write!(Path.join(pack, "gates/010_spec.rq"), """
      PREFIX ex: <https://example.org/mp#>
      SELECT ?package_name WHERE { ex:a ex:packageName ?package_name }
      """)

      {:ok, result} =
        GgenIgniter.Reconcile.run(
          pack_dir: pack,
          engine: "oxigraph",
          out: "#{root}/rec/{{ package_name }}.txt"
        )

      assert result.out_path == "#{root}/rec/alpha_pkg.txt"
      assert File.read!(result.out_path) == "row=alpha_pkg\n"
    end
  end

  describe "defect 3: --pack-dir fan-out over every template of a multi-template pack" do
    test "no --template: each template renders with its own frontmatter to:; second run unchanged",
         %{root: root} do
      pack =
        write_pack!(root, [
          {"a.txt.tmpl",
           tera_template("#{root}/out/{{ package_name }}/a.txt", "A {{ package_name }}")},
          {"b.txt.tmpl",
           tera_template("#{root}/out/{{ package_name }}/b.txt", "B {{ package_name }}")}
        ])

      {output, code} = sync(["--pack-dir", pack], root)
      assert code == 0, output

      for pkg <- ~w(alpha_pkg beta_pkg) do
        assert File.read!(Path.join(root, "out/#{pkg}/a.txt")) =~ "A #{pkg}"
        assert File.read!(Path.join(root, "out/#{pkg}/b.txt")) =~ "B #{pkg}"
      end

      before = File.stat!(Path.join(root, "out/alpha_pkg/a.txt")).mtime
      {output2, code2} = sync(["--pack-dir", pack], root)
      assert code2 == 0, output2
      assert File.stat!(Path.join(root, "out/alpha_pkg/a.txt")).mtime == before
      assert output2 =~ "unchanged" or output2 =~ "reconciled"
    end

    test "explicit --template on a multi-template pack-dir still renders only that template",
         %{root: root} do
      pack =
        write_pack!(root, [
          {"a.txt.tmpl", tera_template("#{root}/out/{{ package_name }}/a.txt", "A")},
          {"b.txt.tmpl", tera_template("#{root}/out/{{ package_name }}/b.txt", "B")}
        ])

      {output, code} =
        sync(["--pack-dir", pack, "--template", Path.join(pack, "templates/a.txt.tmpl")], root)

      assert code == 0, output
      assert File.exists?(Path.join(root, "out/alpha_pkg/a.txt"))
      refute File.exists?(Path.join(root, "out/alpha_pkg/b.txt"))
    end

    test "single-template pack-dir behaves as before", %{root: root} do
      pack =
        write_pack!(root, [
          {"only.txt.tmpl", tera_template("#{root}/out/{{ package_name }}/only.txt", "ONLY")}
        ])

      {output, code} = sync(["--pack-dir", pack], root)
      assert code == 0, output
      assert File.read!(Path.join(root, "out/alpha_pkg/only.txt")) =~ "ONLY"
    end

    test "plain --pack NAME with several templates still refuses (unchanged contract)", %{
      root: root
    } do
      {output, code} =
        sync(["--engine", "sparql", "--pack", "ash-lifecycle-pack-nonexistent"], root)

      refute code == 0
      assert output =~ "no *.eex/*.tmpl template found in"
    end
  end

  describe "defect 5: unknown --pack NAME error" do
    test "names the pack dir, the cwd-relative searched path and the shipped path", %{root: root} do
      {output, code} = sync(["--pack", "definitely-not-a-pack"], root)
      refute code == 0
      assert output =~ "pack directory"
      assert output =~ "does not exist"
      assert output =~ "priv/ggen/definitely-not-a-pack"
      assert output =~ "ggen/definitely-not-a-pack"
    end
  end
end
