defmodule GgenIgniter.InTreePackLoadTest do
  @moduledoc """
  Chicago load/validate court for every in-tree `priv/ggen/*` pack except
  `semantic-jira-pack` (owned by a separate finish lane).

  Locks three invariants against real on-disk packs (no mocks):

    1. Every present `pack.toml` parses under RFC-GPACK-001 §7.1
       (`GgenIgniter.Pack.parse_manifest/1` → `{:ok, _}`).
    2. `GgenIgniter.PackCatalog.list/0` never reports `:invalid_manifest`
       for those packs (catalog surfaces the same parser).
    3. Every pack that ships `ontology.ttl` also ships ≥1 `gates/*.rq` and
       ≥1 `templates/*.{eex,tmpl}` — the sync discovery surface.
  """
  use ExUnit.Case, async: true

  alias GgenIgniter.{Pack, PackCatalog}

  @priv "priv/ggen"
  # Lane-owned exclusion; semantic-jira has its own health court.
  @excluded ~w(semantic-jira-pack)

  defp pack_dirs do
    @priv
    |> File.ls!()
    |> Enum.filter(&File.dir?(Path.join(@priv, &1)))
    |> Enum.reject(&(&1 in @excluded))
    |> Enum.sort()
  end

  test "every present pack.toml under priv/ggen (excl. semantic-jira) is §7.1-valid" do
    tomls =
      for name <- pack_dirs(),
          path = Path.join([@priv, name, "pack.toml"]),
          File.regular?(path),
          do: {name, path}

    refute tomls == [], "sanity: at least one owned pack ships pack.toml"

    for {name, _path} <- tomls do
      assert {:ok, %Pack.Manifest{name: ^name}} = Pack.parse_manifest(Path.join(@priv, name)),
             "#{name}/pack.toml must parse as [pack] name/version/description only"
    end
  end

  test "PackCatalog reports no invalid_manifest for owned in-tree packs" do
    invalid =
      PackCatalog.list()
      |> Enum.filter(&(&1.metadata_source == :invalid_manifest))
      |> Enum.reject(&(Path.basename(&1.dir) in @excluded))

    assert invalid == [],
           "invalid_manifest packs: " <>
             Enum.map_join(invalid, ", ", &"#{Path.basename(&1.dir)} (#{&1.manifest_error})")
  end

  test "every owned pack with ontology.ttl has gates and templates" do
    for name <- pack_dirs(),
        ontology = Path.join([@priv, name, "ontology.ttl"]),
        File.regular?(ontology) do
      gates = Path.wildcard(Path.join([@priv, name, "gates", "*.rq"]))

      templates =
        Path.wildcard(Path.join([@priv, name, "templates", "*.eex"])) ++
          Path.wildcard(Path.join([@priv, name, "templates", "*.tmpl"]))

      assert gates != [], "#{name}: missing gates/*.rq"
      assert templates != [], "#{name}: missing templates/*.{eex,tmpl}"
    end
  end
end
