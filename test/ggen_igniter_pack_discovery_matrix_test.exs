defmodule GgenIgniter.PackDiscoveryMatrixTest do
  @moduledoc """
  Combinatorial, Chicago-style discovery matrix for `GgenIgniter.Pack` against
  EVERY real fixture pack directory currently present under `test/fixtures/`.

  No mocking, no StreamData: the input space here is "every real pack
  directory that actually exists on disk right now", which is small and
  enumerable, not something worth randomly generating. The combinatorial
  requirement is instead satisfied by driving the whole matrix off a real
  `Path.wildcard("test/fixtures/*")` enumeration (see `@fixture_pack_dirs`
  below) rather than a hand-typed list of the three packs known today --
  so a fourth fixture pack added later gets real discovery coverage
  automatically, with zero edits to this file required.

  Two layers of assertion, both against real files, none mocked:

    1. **Generic invariants**, generated once per real pack directory found
       by the wildcard (`discover_queries/1`'s output must equal the real,
       independently-`Path.wildcard`'d `gates/*.rq` files; `discover_template/1`'s
       result shape must match the real on-disk template count;
       `default_ontology/1` must point at the real `<pack_dir>/ontology.ttl`
       path). These hold for ANY pack, known or future.
    2. **Pinned assertions** for the three packs this matrix was authored
       against (`sample-pack`, `broken-pack`, `ash-lifecycle-pack`), asserting
       the exact real tuples/paths/counts verified by a real directory listing
       at authoring time -- so a regression that silently changes discovery
       behavior for a specific, known-shape pack is caught precisely, not just
       generically.

  Verified real, current on-disk shape (re-confirmed via `find`/`ls` immediately
  before writing this file -- not assumed from memory or from prior test files):

    * `test/fixtures/sample-pack/gates/{010_spec,020_sections,030_entities,040_fields}.rq`
      + `test/fixtures/sample-pack/templates/extension.ex.eex` (exactly one
      template) + `test/fixtures/sample-pack/ontology.ttl`.
    * `test/fixtures/broken-pack/gates/010_bad.rq` only -- no `templates/`
      directory at all, no `ontology.ttl` on disk (path construction in
      `default_ontology/1` doesn't check existence, so this is still asserted).
    * `test/fixtures/ash-lifecycle-pack/gates/{010_resource,020_attributes,
      030_actions,040_relationships,050_domain_resources}.rq` +
      `test/fixtures/ash-lifecycle-pack/templates/{domain.ex.eex,resource.ex.eex}`
      (exactly two templates -> the real `{:error, {:ambiguous, paths}}` case)
      + `test/fixtures/ash-lifecycle-pack/ontology.ttl`.

  Checked for a concurrent `--pack NAME:TEMPLATE`-style disambiguation feature
  that might change ash-lifecycle-pack's default-discovery outcome: as of this
  read, `GgenIgniter.Pack.discover_template/1` still takes a single `pack_dir`
  argument with no template-name/selector parameter, and neither
  `mix ggen_igniter.sync` nor `mix ggen_igniter.doctor` pass one through to it
  -- so the real current behavior is still "2 templates -> ambiguous", asserted
  below as such. If a future agent adds that feature, the generic-invariant
  layer above will still hold (it derives its expectation from the real
  on-disk template count, not a hardcoded number); only the pinned
  ash-lifecycle-pack assertion would need revisiting.
  """
  use ExUnit.Case, async: true

  alias GgenIgniter.Pack

  @fixtures_root Path.join(__DIR__, "fixtures")

  @fixture_pack_dirs @fixtures_root
                     |> Path.join("*")
                     |> Path.wildcard()
                     |> Enum.filter(&File.dir?/1)
                     |> Enum.sort()

  # -- Sanity on the enumeration itself --------------------------------------

  test "fixture pack enumeration is real, non-empty, and includes the known packs" do
    refute Enum.empty?(@fixture_pack_dirs)

    names = Enum.map(@fixture_pack_dirs, &Path.basename/1)
    assert "sample-pack" in names
    assert "broken-pack" in names
    assert "ash-lifecycle-pack" in names

    # Every discovered "pack dir" really is a directory on disk (the
    # `File.dir?/1` filter above is exercised here as a repeated real check,
    # not just at compile time).
    Enum.each(@fixture_pack_dirs, fn dir -> assert File.dir?(dir) end)
  end

  # -- Generic, per-real-pack invariants --------------------------------------
  #
  # Generated once for EVERY directory `Path.wildcard("test/fixtures/*")`
  # finds right now -- this is the part that stays real coverage as new
  # fixture packs get added, with no edits to this file.

  for pack_dir <- @fixture_pack_dirs do
    pack_name = Path.basename(pack_dir)

    test "#{pack_name}: discover_queries/1 matches the real gates/*.rq files on disk" do
      pack_dir = unquote(pack_dir)

      real_rq_paths =
        pack_dir
        |> Path.join("gates/*.rq")
        |> Path.wildcard()
        |> Enum.sort()

      queries = Pack.discover_queries(pack_dir)

      assert Enum.map(queries, fn {_name, path} -> path end) == real_rq_paths
      assert length(queries) == length(real_rq_paths)

      Enum.each(queries, fn {name, path} ->
        assert File.regular?(path)
        expected_name = path |> Path.basename(".rq") |> String.replace(~r/^\d+_/, "")
        assert name == expected_name
      end)
    end

    test "#{pack_name}: discover_template/1 matches the real templates/*.{eex,tmpl} count on disk" do
      pack_dir = unquote(pack_dir)

      real_template_paths =
        [
          Path.wildcard(Path.join(pack_dir, "templates/*.eex")),
          Path.wildcard(Path.join(pack_dir, "templates/*.tmpl"))
        ]
        |> List.flatten()
        |> Enum.sort()

      result = Pack.discover_template(pack_dir)

      case real_template_paths do
        [] ->
          assert result == {:error, :none}

        [single] ->
          assert result == {:ok, single}
          assert File.regular?(single)

        many ->
          assert {:error, {:ambiguous, paths}} = result
          assert Enum.sort(paths) == many
          assert length(paths) == length(many)
          Enum.each(paths, fn p -> assert File.regular?(p) end)
      end
    end

    test "#{pack_name}: default_ontology/1 points at the real <pack_dir>/ontology.ttl path" do
      pack_dir = unquote(pack_dir)
      assert Pack.default_ontology(pack_dir) == Path.join(pack_dir, "ontology.ttl")
    end
  end

  # -- Pinned assertions for the three packs known at authoring time ----------
  #
  # These encode the EXACT real tuples/paths verified by a real directory
  # listing immediately before writing this file (see moduledoc). They catch
  # a regression that changes discovery for one specific, known-shape pack
  # even if it happens to preserve the generic invariants above (e.g. a
  # sorting bug that reorders two same-count templates identically under the
  # generic check but differs from the real, previously-verified order).

  describe "pinned: sample-pack (single template, 4 gate queries)" do
    @sample_pack_dir Path.join(@fixtures_root, "sample-pack")

    test "discover_queries/1 returns the real, ordered {name, path} tuples" do
      assert Pack.discover_queries(@sample_pack_dir) == [
               {"spec", Path.join([@sample_pack_dir, "gates", "010_spec.rq"])},
               {"sections", Path.join([@sample_pack_dir, "gates", "020_sections.rq"])},
               {"entities", Path.join([@sample_pack_dir, "gates", "030_entities.rq"])},
               {"fields", Path.join([@sample_pack_dir, "gates", "040_fields.rq"])}
             ]
    end

    test "discover_template/1 returns {:ok, path} for the single real template" do
      assert Pack.discover_template(@sample_pack_dir) ==
               {:ok, Path.join([@sample_pack_dir, "templates", "extension.ex.eex"])}
    end

    test "default_ontology/1 returns the real ontology.ttl path" do
      assert Pack.default_ontology(@sample_pack_dir) ==
               Path.join(@sample_pack_dir, "ontology.ttl")

      assert File.regular?(Pack.default_ontology(@sample_pack_dir))
    end
  end

  describe "pinned: broken-pack (1 gate query, zero templates)" do
    @broken_pack_dir Path.join(@fixtures_root, "broken-pack")

    test "discover_queries/1 returns the single real {name, path} tuple" do
      assert Pack.discover_queries(@broken_pack_dir) == [
               {"bad", Path.join([@broken_pack_dir, "gates", "010_bad.rq"])}
             ]
    end

    test "discover_template/1 returns {:error, :none} (no templates/ dir at all on disk)" do
      refute File.dir?(Path.join(@broken_pack_dir, "templates"))
      assert Pack.discover_template(@broken_pack_dir) == {:error, :none}
    end

    test "default_ontology/1 constructs the path even though ontology.ttl doesn't exist on disk" do
      expected = Path.join(@broken_pack_dir, "ontology.ttl")
      assert Pack.default_ontology(@broken_pack_dir) == expected
      refute File.exists?(expected)
    end
  end

  describe "pinned: ash-lifecycle-pack (5 gate queries, 2 templates -> ambiguous)" do
    @ash_pack_dir Path.join(@fixtures_root, "ash-lifecycle-pack")

    test "discover_queries/1 returns all 5 real, ordered {name, path} tuples" do
      assert Pack.discover_queries(@ash_pack_dir) == [
               {"resource", Path.join([@ash_pack_dir, "gates", "010_resource.rq"])},
               {"attributes", Path.join([@ash_pack_dir, "gates", "020_attributes.rq"])},
               {"actions", Path.join([@ash_pack_dir, "gates", "030_actions.rq"])},
               {"relationships", Path.join([@ash_pack_dir, "gates", "040_relationships.rq"])},
               {"domain_resources",
                Path.join([@ash_pack_dir, "gates", "050_domain_resources.rq"])}
             ]
    end

    test "discover_template/1 returns the real {:error, {:ambiguous, paths}} for its 2 real templates" do
      expected_paths =
        Enum.sort([
          Path.join([@ash_pack_dir, "templates", "domain.ex.eex"]),
          Path.join([@ash_pack_dir, "templates", "resource.ex.eex"])
        ])

      assert Pack.discover_template(@ash_pack_dir) == {:error, {:ambiguous, expected_paths}}
    end

    test "default_ontology/1 returns ontology.ttl specifically, not one of the versioned variants" do
      # ash-lifecycle-pack also carries ontology_v2_add_attribute.ttl and
      # ontology_v3_rename.ttl on disk (lifecycle-migration fixtures) --
      # default_ontology/1 must still resolve to the base ontology.ttl, not
      # either versioned variant.
      assert Pack.default_ontology(@ash_pack_dir) == Path.join(@ash_pack_dir, "ontology.ttl")
      assert File.regular?(Path.join(@ash_pack_dir, "ontology.ttl"))
      assert File.regular?(Path.join(@ash_pack_dir, "ontology_v2_add_attribute.ttl"))
      assert File.regular?(Path.join(@ash_pack_dir, "ontology_v3_rename.ttl"))
    end
  end
end
