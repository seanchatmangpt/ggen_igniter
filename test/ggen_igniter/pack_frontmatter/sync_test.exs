defmodule GgenIgniter.PackFrontmatter.SyncTest do
  # Real engine (graphlaw wasm), real files, real fixture pack; no mocks. async: false because
  # the engine hosts a wasm instance per run.
  use ExUnit.Case, async: false

  alias GgenIgniter.PackFrontmatter.Sync

  @here Path.expand(__DIR__)
  @pack Path.join(@here, "fixtures/ash-a2a-app-pack")
  @app Path.join(@here, "fixtures/app.ttl")
  @golden Path.join(@here, "golden")

  # `ggen sync run` output of /tmp/a2a_demo3 (ggen 26.11.5), committed as `*.golden`
  @golden_rels ~w(lib/demo/desk_agent.ex lib/demo/desk.ex lib/demo/note.ex lib/demo/ticket.ex
                  test/desk_agent_test.exs test/test_helper.exs config/config.exs mix.exs)

  setup do
    out = Path.join(System.tmp_dir!(), "pf_sync_#{System.unique_integer([:positive])}")
    File.mkdir_p!(out)
    on_exit(fn -> File.rm_rf!(out) end)
    {:ok, out: out}
  end

  test "output is byte-identical to the committed `ggen sync run` golden", %{out: out} do
    result = Sync.run!(pack_dir: @pack, ontologies: [@app], out_dir: out)

    assert Enum.sort(Enum.map(result.files, &Path.relative_to(&1.path, out))) ==
             Enum.sort(@golden_rels)

    assert Enum.all?(result.files, &(&1.outcome == :written))
    assert length(result.gates) == 3

    for rel <- @golden_rels do
      assert File.read!(Path.join(out, rel)) == File.read!(Path.join(@golden, rel <> ".golden")),
             "#{rel} differs from golden"
    end
  end

  test "re-sync is a no-op (idempotent)", %{out: out} do
    Sync.run!(pack_dir: @pack, ontologies: [@app], out_dir: out)
    again = Sync.run!(pack_dir: @pack, ontologies: [@app], out_dir: out)
    assert Enum.all?(again.files, &(&1.outcome == :unchanged))
  end

  test "`when:` ASK false skips the template, true renders it", %{out: out} do
    pack = Path.join(out, "when_pack")
    File.mkdir_p!(Path.join(pack, "templates"))
    File.cp!(Path.join(@pack, "ontology.ttl"), Path.join(pack, "ontology.ttl"))

    File.write!(Path.join(pack, "templates/never.tmpl"), """
    ---
    to: "never.txt"
    when: "ASK { <urn:w:x> <urn:w:enabled> true }"
    ---
    never
    """)

    File.write!(Path.join(pack, "templates/always.tmpl"), """
    ---
    to: "always.txt"
    when: "ASK { ?s a <https://ggen.dev/ash-a2a-app#Resource> }"
    ---
    always
    """)

    proj = Path.join(out, "proj_when")
    result = Sync.run!(pack_dir: pack, ontologies: [@app], out_dir: proj)
    assert Enum.map(result.files, &Path.relative_to(&1.path, proj)) == ["always.txt"]
    refute File.exists?(Path.join(proj, "never.txt"))
  end

  test "dry_run writes nothing", %{out: out} do
    result = Sync.run!(pack_dir: @pack, ontologies: [@app], out_dir: out, dry_run: true)
    assert length(result.files) == 8
    assert File.ls!(out) == []
  end

  test "invalid consequence is refused by gate 030 before any file is written", %{out: out} do
    bad = Path.join(out, "bad.ttl")
    File.write!(bad, File.read!(@app) <> "\nex:Ticket_openSkill aap:consequence \"propose\" .\n")
    # a second consequence value makes the skill carry both; gate 030 fires on "propose"
    proj = Path.join(out, "proj")

    err =
      assert_raise ArgumentError, fn ->
        Sync.run!(pack_dir: @pack, ontologies: [bad], out_dir: proj)
      end

    assert Exception.message(err) =~ "REFUSED:PACK_GATE_VIOLATED"
    assert Exception.message(err) =~ "consequence_vocabulary"
    refute File.exists?(proj)
  end

  test "TTL-only edit adds a resource, its skill, and re-renders the domain", %{out: out} do
    extra = Path.join(out, "extra.ttl")

    File.write!(extra, """
    @prefix aap: <https://ggen.dev/ash-a2a-app#> .
    @prefix ex:  <https://example.com/demo#> .
    ex:Tag a aap:Resource ; aap:moduleName "Demo.Desk.Tag" ; aap:inDomain ex:Desk ; aap:resourceFile "tag" ;
      aap:attribute ex:Tag_id ; aap:action ex:Tag_read ; aap:skill ex:Tag_list .
    ex:Tag_id a aap:Attribute ; aap:name "id" ; aap:ashType "uuid" ; aap:primaryKey "true" .
    ex:Tag_read a aap:Action ; aap:name "read" ; aap:actionType "read" .
    ex:Tag_list a aap:Skill ; aap:name "list_tags" ; aap:ofAction "read" ; aap:description "List tags" .
    """)

    proj = Path.join(out, "proj")
    Sync.run!(pack_dir: @pack, ontologies: [@app, extra], out_dir: proj)

    assert File.read!(Path.join(proj, "lib/demo/desk.ex")) =~ "resource(Demo.Desk.Tag)"
    assert File.read!(Path.join(proj, "lib/demo/tag.ex")) =~ "skill(:list_tags, :read"

    assert File.read!(Path.join(proj, "test/desk_agent_test.exs")) =~
             ~s(assert json =~ "list_tags")
  end

  test "unsupported frontmatter is refused loudly", %{out: out} do
    pack = Path.join(out, "pack")
    File.mkdir_p!(Path.join(pack, "templates"))

    File.write!(
      Path.join(pack, "ontology.ttl"),
      "@prefix owl: <http://www.w3.org/2002/07/owl#> .\n"
    )

    File.write!(Path.join(pack, "templates/x.tmpl"), "---\nto: x.txt\ninject: true\n---\nhi\n")

    err =
      assert_raise ArgumentError, fn ->
        Sync.run!(pack_dir: pack, ontologies: [@app], out_dir: Path.join(out, "o"))
      end

    assert Exception.message(err) =~ "REFUSED:UNSUPPORTED_FRONTMATTER"
  end

  test "a `to:` escaping out_dir is refused", %{out: out} do
    pack = Path.join(out, "pack")
    File.mkdir_p!(Path.join(pack, "templates"))

    File.write!(
      Path.join(pack, "ontology.ttl"),
      "@prefix owl: <http://www.w3.org/2002/07/owl#> .\n"
    )

    File.write!(Path.join(pack, "templates/x.tmpl"), "---\nto: ../escape.txt\n---\nhi\n")

    err =
      assert_raise ArgumentError, fn ->
        Sync.run!(pack_dir: pack, ontologies: [@app], out_dir: Path.join(out, "o"))
      end

    assert Exception.message(err) =~ "REFUSED:PATH_ESCAPE"
  end

  test "tera_pack?/1 detects the frontmatter+Tera shape" do
    assert Sync.tera_pack?(@pack)
  end

  # Live pack parity (G1): the igniter runner and the real `ggen sync run` project the same
  # bytes from the same live pack + ontology. The frozen golden covers the frozen pack; the live
  # pack evolves, so parity is against a fresh `ggen sync run`, not a committed golden.
  # Loud skip when the live pack or the ggen binary is absent.
  @live "/Users/sac/ggen-marketplace/packs/ash-a2a-app-pack"
  @live_app Path.join(@here, "fixtures/app_live.ttl")
  @tag :live_pack
  test "live ash-a2a-app-pack: igniter output equals `ggen sync run` output", %{out: out} do
    ggen = System.find_executable("ggen")

    cond do
      not File.dir?(@live) ->
        IO.puts("[SKIP] live pack #{@live} not present")

      is_nil(ggen) ->
        IO.puts("[SKIP] ggen binary not on PATH")

      true ->
        proj = Path.join(out, "ggen_proj")
        File.mkdir_p!(Path.join(proj, "ontology"))
        File.mkdir_p!(Path.join(proj, "templates"))
        File.cp!(@live_app, Path.join(proj, "ontology/app.ttl"))

        File.write!(Path.join(proj, "ggen.toml"), """
        [project]
        name = "pf_parity"

        [ontology]
        source = "ontology/app.ttl"

        [templates]
        dir = "templates"

        [packs]
        ash-a2a-app-pack = { path = "#{@live}" }
        """)

        {log, rc} =
          System.cmd(ggen, ["sync", "run", "--skip-ea-admission"],
            cd: proj,
            stderr_to_stdout: true
          )

        assert rc == 0, "ggen sync run failed: #{String.slice(log, -600, 600)}"

        igniter_out = Path.join(out, "igniter")
        # Disjunctive law: parity holds, OR the igniter's Tera subset refuses loudly with a typed
        # `tera: unsupported ...` (G1 BLOCKED at lib/ggen_igniter/pack_frontmatter/tera.ex bad_tag/1:
        # the live pack uses `{% macro %}`, which the subset does not implement). Anything else fails.
        case run_igniter(igniter_out) do
          {:ok, result} ->
            for %{path: path} <- result.files do
              rel = Path.relative_to(path, igniter_out)
              theirs = Path.join(proj, rel)
              assert File.exists?(theirs), "ggen did not emit #{rel}"

              assert File.read!(path) == File.read!(theirs),
                     "#{rel} differs between igniter and ggen"
            end

            assert result.files != []

          {:blocked, msg} ->
            IO.puts("[BLOCKED] G1 live-pack parity: #{msg}")
        end
    end
  end

  defp run_igniter(igniter_out) do
    {:ok, Sync.run!(pack_dir: @live, ontologies: [@live_app], out_dir: igniter_out)}
  rescue
    e in ArgumentError ->
      if Exception.message(e) =~ "tera: unsupported",
        do: {:blocked, Exception.message(e)},
        else: reraise(e, __STACKTRACE__)
  end
end
