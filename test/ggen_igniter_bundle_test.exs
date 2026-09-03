defmodule GgenIgniterBundleTest do
  @moduledoc """
  Real-collaborator, state-based tests for `GgenIgniter.Bundle`
  (`docs/jira/v26.9.1/03-BUNDLE-MANIFEST-AND-MERGE.md`, GGEN-1801 manifest +
  GGEN-1803 dedupe merge). No `Mock`/`mock(`/`patch(`/`monkeypatch` anywhere
  in this file -- real `Jason.decode!/1` over the real
  `priv/bundles/fortune5_ready.json` on disk, real `Toml.decode/1` (via
  `GgenIgniter.SchemaDispatch.load_raw/1`) over real fixture files copied
  from beam4pm's actual `ggen.toml`.
  """
  use ExUnit.Case, async: true

  @fixtures_dir Path.join(__DIR__, "fixtures/bundle")

  describe "load!/1 -- manifest (GGEN-1801)" do
    test "loads the real priv/bundles/fortune5_ready.json and returns exactly the fortune5_ready bundle" do
      bundles = GgenIgniter.Bundle.load!()

      assert Map.has_key?(bundles, "fortune5_ready")

      bundle = Map.fetch!(bundles, "fortune5_ready")
      assert bundle.manifest_version == "1.0.0"
      assert is_list(bundle.packs)
    end

    test "the loaded bundle is a typed struct, not a raw string-keyed Map decoded from JSON" do
      bundle = GgenIgniter.Bundle.load!() |> Map.fetch!("fortune5_ready")

      # Real struct field access -- this would raise KeyError against a raw
      # %{"packs" => [...]}-shaped map with unconverted string keys.
      assert is_list(bundle.packs)
      [first_pack | _] = bundle.packs
      assert %GgenIgniter.Bundle.Pack{} = first_pack
      assert is_binary(first_pack.name)
      assert is_binary(first_pack.path_hint)
    end

    test "v1 packs list has exactly 2 entries: fortune5-architecture and fortune5-deployment-blocks" do
      packs = GgenIgniter.Bundle.load_packs!()

      names = Enum.map(packs, & &1.name)

      assert length(packs) == 2
      assert names == ["fortune5-architecture", "fortune5-deployment-blocks"]
    end

    test "fortune5-required-capabilities and fortune5-testing-bblock are NOT present in the v1 manifest" do
      names = GgenIgniter.Bundle.load_packs!() |> Enum.map(& &1.name)

      refute "fortune5-required-capabilities" in names
      refute "fortune5-testing-bblock" in names
      refute "fortune5-enterprise-architecture" in names
    end

    test "the moduledoc records both resolved design decisions (manifest location, domain-aware composition)" do
      {:docs_v1, _, _, _, %{"en" => moduledoc}, _, _} = Code.fetch_docs(GgenIgniter.Bundle)

      assert moduledoc =~ "manifest location"
      assert moduledoc =~ "ggen_igniter` itself"
      assert moduledoc =~ "domain-aware"
      assert moduledoc =~ "name-keyed map"
    end
  end

  describe "merge/2 -- dedupe (GGEN-1803)" do
    test "Test 1: real merge against beam4pm's actual ggen.toml produces exactly 5 existing + 2 new = 7 entries" do
      {:frontmatter, config} = load_fixture!("beam4pm_ggen.toml")
      bundle_packs = GgenIgniter.Bundle.load_packs!()

      to_add = GgenIgniter.Bundle.merge(config, bundle_packs)
      added_names = Enum.map(to_add, & &1.name) |> Enum.sort()

      assert added_names == ["fortune5-architecture", "fortune5-deployment-blocks"]

      # Full resulting pack set (existing ∪ added) is exactly the 5 real
      # beam4pm entries plus the 2 new fortune5-* entries -- 7 total.
      resulting_names =
        (Map.keys(config.packs) ++ added_names) |> Enum.uniq() |> Enum.sort()

      expected =
        Enum.sort([
          "beam4pm-process-model",
          "beam4pm-pro-infra",
          "github-actions-pack",
          "beam4pm-ai-contracts",
          "beam4pm-pro-entitlement",
          "fortune5-architecture",
          "fortune5-deployment-blocks"
        ])

      assert resulting_names == expected
      assert length(resulting_names) == 7
      # No duplicates.
      assert length(resulting_names) == length(Enum.uniq(resulting_names))

      # No path collisions: neither new entry's path_hint matches any
      # existing entry's real path.
      existing_paths =
        config.packs
        |> Map.values()
        |> Enum.map(fn {:path, %{path: path}} -> path end)

      for pack <- to_add do
        refute pack.path_hint in existing_paths
      end
    end

    test "Test 2: idempotency -- merging an already-fortune5-wired ggen.toml a second time is a true no-op" do
      {:frontmatter, config} = load_fixture!("beam4pm_ggen.toml")
      bundle_packs = GgenIgniter.Bundle.load_packs!()

      first_run = GgenIgniter.Bundle.merge(config, bundle_packs)

      # Simulate the first run's real output being wired into ggen.toml:
      # the resulting config now has all 7 entries.
      config_after_first_run = %{
        config
        | packs:
            Enum.reduce(first_run, config.packs, fn pack, acc ->
              Map.put(
                acc,
                pack.name,
                {:path, %{path: pack.path_hint, extra_ontologies: [], lock: true}}
              )
            end)
      }

      second_run = GgenIgniter.Bundle.merge(config_after_first_run, bundle_packs)

      assert second_run == []
    end

    test "Test 3: partial-install dedup -- only the missing bundle pack is reported as new" do
      {:frontmatter, config} = load_fixture!("beam4pm_partial_install.toml")
      bundle_packs = GgenIgniter.Bundle.load_packs!()

      to_add = GgenIgniter.Bundle.merge(config, bundle_packs)

      assert length(to_add) == 1
      assert [%GgenIgniter.Bundle.Pack{name: "fortune5-deployment-blocks"}] = to_add
    end

    test "Test 4: dedup key is name, not path -- a path collision under a different name is still added" do
      {:frontmatter, config} = load_fixture!("path_collision_different_name.toml")
      bundle_packs = GgenIgniter.Bundle.load_packs!()

      # Sanity: the fixture really does have a path collision with the
      # fortune5-architecture bundle pack's path_hint, under a different name.
      # lock: true is the correct Rust-aligned default (GI-PARITY-1); see
      # ggen_igniter_ggen_toml_io_test.exs's matching fix for the full
      # rationale.
      assert config.packs["my-renamed-architecture-fork"] ==
               {:path,
                %{
                  path: "vendor/ggen-marketplace/packs/fortune5-architecture-pack",
                  extra_ontologies: [],
                  lock: true
                }}

      refute Map.has_key?(config.packs, "fortune5-architecture")

      to_add = GgenIgniter.Bundle.merge(config, bundle_packs)
      added_names = Enum.map(to_add, & &1.name) |> Enum.sort()

      assert "fortune5-architecture" in added_names
      assert added_names == ["fortune5-architecture", "fortune5-deployment-blocks"]
    end
  end

  describe "GgenToml.IO.splice_added_packs!/2 -- addition-only write-back (GI-07)" do
    test "merging fortune5-ready into beam4pm's real ggen.toml produces an addition-only diff, including the gh-terraform-pack decline comment surviving byte-for-byte" do
      original = File.read!(Path.join(@fixtures_dir, "beam4pm_ggen.toml"))
      {:frontmatter, config} = GgenIgniter.SchemaDispatch.load_raw(original)
      bundle_packs = GgenIgniter.Bundle.load_packs!()

      to_add = GgenIgniter.Bundle.merge(config, bundle_packs)

      assert Enum.map(to_add, & &1.name) |> Enum.sort() ==
               ["fortune5-architecture", "fortune5-deployment-blocks"]

      spliced = GgenIgniter.GgenToml.IO.splice_added_packs!(original, to_add)

      original_lines = String.split(original, "\n")
      spliced_lines = String.split(spliced, "\n")

      # Addition-only: every original line still appears in the spliced
      # output, in the same relative order (a real subsequence check, not
      # just a length/count assertion) -- and the only lines the spliced
      # output has beyond the original are the 2 new pack-entry lines.
      assert subsequence?(original_lines, spliced_lines)
      assert length(spliced_lines) == length(original_lines) + 2

      # The new pack-entry lines are present, verbatim, in the expected
      # inline-table shape.
      assert "fortune5-architecture = { path = \"vendor/ggen-marketplace/packs/fortune5-architecture-pack\" }" in spliced_lines

      assert "fortune5-deployment-blocks = { path = \"vendor/ggen-marketplace/packs/fortune5-deployment-blocks-pack\" }" in spliced_lines

      # The gh-terraform-pack decline comment block survives byte-for-byte,
      # including its exact original line contents and relative position
      # (still directly after the pack entries, still before [templates]).
      assert spliced =~ """
             # gh-terraform-pack: investigated 2026-08-30, NOT wired -- ships unscoped
             # reference-repo instance data that hard-collides (family "repository") or
             # pollutes (families "milestones"/"labels") any second consumer's output.
             # See the "gh-terraform-pack consumption -- INVESTIGATED AND DECLINED"
             # comment block in ontology.ttl for the full, confirmed finding.
             """

      # Existing 5 entries keep their original relative order (no
      # alphabetical reorder -- unlike serialize!/1's Map-based re-render).
      existing_order =
        Enum.filter(spliced_lines, fn l ->
          String.starts_with?(l, "beam4pm-") or String.starts_with?(l, "github-actions-pack")
        end)

      assert existing_order == [
               "beam4pm-process-model = { path = \"vendor/ggen-marketplace/packs/beam4pm-process-model-pack\" }",
               "beam4pm-pro-infra = { path = \"vendor/ggen-marketplace/packs/beam4pm-pro-infra-pack\" }",
               "github-actions-pack = { path = \"vendor/ggen-marketplace/packs/github-actions-pack\" }",
               "beam4pm-ai-contracts = { path = \"vendor/ggen-marketplace/packs/beam4pm-ai-contracts-pack\" }",
               "beam4pm-pro-entitlement = { path = \"vendor/ggen-marketplace/packs/beam4pm-pro-entitlement-pack\" }"
             ]

      # The new entries were spliced in right after the last existing
      # entry, before the comment block -- not appended at EOF or dropped
      # into the middle of the existing entries.
      last_existing_idx =
        Enum.find_index(
          spliced_lines,
          &(&1 ==
              "beam4pm-pro-entitlement = { path = \"vendor/ggen-marketplace/packs/beam4pm-pro-entitlement-pack\" }")
        )

      assert Enum.at(spliced_lines, last_existing_idx + 1) ==
               "fortune5-architecture = { path = \"vendor/ggen-marketplace/packs/fortune5-architecture-pack\" }"

      assert Enum.at(spliced_lines, last_existing_idx + 2) ==
               "fortune5-deployment-blocks = { path = \"vendor/ggen-marketplace/packs/fortune5-deployment-blocks-pack\" }"

      assert Enum.at(spliced_lines, last_existing_idx + 3) =~ "gh-terraform-pack: investigated"

      # The spliced text still parses cleanly through the real classifier,
      # and the resulting config's pack set is the full expected 7.
      {:frontmatter, reparsed} = GgenIgniter.SchemaDispatch.load_raw(spliced)

      assert Map.keys(reparsed.packs) |> Enum.sort() ==
               Enum.sort([
                 "beam4pm-process-model",
                 "beam4pm-pro-infra",
                 "github-actions-pack",
                 "beam4pm-ai-contracts",
                 "beam4pm-pro-entitlement",
                 "fortune5-architecture",
                 "fortune5-deployment-blocks"
               ])
    end

    test "idempotent re-splice against an already-fortune5-wired file adds nothing (merge/2 already returns [])" do
      original = File.read!(Path.join(@fixtures_dir, "beam4pm_ggen.toml"))
      {:frontmatter, config} = GgenIgniter.SchemaDispatch.load_raw(original)
      bundle_packs = GgenIgniter.Bundle.load_packs!()

      first_to_add = GgenIgniter.Bundle.merge(config, bundle_packs)
      once_spliced = GgenIgniter.GgenToml.IO.splice_added_packs!(original, first_to_add)

      {:frontmatter, config_after_first} = GgenIgniter.SchemaDispatch.load_raw(once_spliced)
      second_to_add = GgenIgniter.Bundle.merge(config_after_first, bundle_packs)

      assert second_to_add == []
      twice_spliced = GgenIgniter.GgenToml.IO.splice_added_packs!(once_spliced, second_to_add)
      assert twice_spliced == once_spliced
    end
  end

  defp subsequence?([], _list), do: true

  defp subsequence?([h | t], list) do
    case Enum.find_index(list, &(&1 == h)) do
      nil -> false
      idx -> subsequence?(t, Enum.drop(list, idx + 1))
    end
  end

  defp load_fixture!(filename) do
    Path.join(@fixtures_dir, filename)
    |> File.read!()
    |> GgenIgniter.SchemaDispatch.load_raw()
  end
end
