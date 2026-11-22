defmodule GgenIgniter.SpatialCourtTest do
  @moduledoc """
  Chicago: real Turtle on disk → `SpatialCourt.from_ontology/1` → `render`/`emit`
  via the shipped EEx template. No Semantic Jira court maps; no doubles.

  Collaborators:
    * court-ready CCS twin under `test/fixtures/spatial_court/`
    * marketplace pack ontology (blank-node CCS + shui:selector → emit)
    * `priv/ggen/spatial-court-pack/templates/spatial_court.spec.ts.eex`
  """
  use ExUnit.Case, async: true

  alias GgenIgniter.SpatialCourt

  @fixture Path.expand("fixtures/spatial_court/property_groups.ttl", __DIR__)
  @ccs_court Path.expand("fixtures/spatial_court/mobile_ui_layout_court.ttl", __DIR__)

  @pack_ontology Path.expand(
                   "../../ggen-marketplace/packs/mobile-ui-layout-pack/ontology.ttl",
                   __DIR__
                 )
  @blank_no_sel Path.expand("fixtures/spatial_court/blank_groups_no_selectors.ttl", __DIR__)

  @viewport_sweep [320, 375, 393, 414, 600, 768, 840, 1024, 1280]

  test "viewports match the Step-3 sweep matrix" do
    assert SpatialCourt.viewports() == @viewport_sweep
  end

  test "shipped template path exists under priv/ggen/spatial-court-pack" do
    assert File.regular?(SpatialCourt.template_path()),
           "missing Spatial Court EEx at #{SpatialCourt.template_path()}"
  end

  test "from_ontology extracts ordered PropertyGroups with selectors" do
    assert File.regular?(@fixture), "missing fixture #{@fixture}"
    assert {:ok, court} = SpatialCourt.from_ontology(@fixture)
    assert length(court.groups) == 2
    assert hd(court.groups).id == "PrimaryActions"
    assert hd(court.groups).selector == "[data-spatial-group='primary-actions']"
    assert length(hd(court.groups).members) == 2
    assert hd(hd(court.groups).members).touch? == true
    assert Enum.at(hd(court.groups).members, 1).touch? == true
    assert Enum.at(court.groups, 1).id == "MetaCluster"
    assert hd(Enum.at(court.groups, 1).members).touch? == false
    assert court.viewports == @viewport_sweep
    assert court.min_touch == 44
    assert court.min_gap == 8
  end

  test "emit from CCS court ontology writes Playwright with viewport/overflow/touch/anti-vacuity markers" do
    assert File.regular?(@ccs_court), "missing CCS court fixture #{@ccs_court}"

    dir =
      Path.join(System.tmp_dir!(), "spatial_court_ccs_#{System.unique_integer([:positive])}")

    File.mkdir_p!(dir)
    on_exit(fn -> File.rm_rf!(dir) end)

    assert {:ok, court} = SpatialCourt.from_ontology(@ccs_court)
    assert length(court.groups) == 3

    assert Enum.map(court.groups, & &1.id) == [
             "SightGlass",
             "HumanCircuitBreaker",
             "BottomNavigation"
           ]

    assert {:ok, path} = SpatialCourt.emit(court, out: dir)
    assert String.ends_with?(path, ".spatial-court.spec.ts")
    assert File.regular?(path)

    body = File.read!(path)

    # viewport sweep — env consumer (adapter UI_LAYOUT_*) + 9-wide fallback
    assert body =~ "UI_LAYOUT_PLAYWRIGHT_VIEWPORTS"
    assert body =~ "UI_LAYOUT_VIEWPORTS"
    assert body =~ "parseViewportCsv"
    assert body =~ "DEFAULT_VIEWPORTS"
    assert body =~ "[320,375,393,414,600,768,840,1024,1280]"
    assert body =~ "viewport"

    # overflow (WCAG 1.4.10 / horizontal scrollWidth floor)
    assert body =~ "assertNoHorizontalOverflow"
    assert body =~ "horizontal overflow"

    # touch (≥44) + gap (≥8)
    assert body =~ "assertTouchAndGap"
    assert body =~ "const MIN_TOUCH = 44"
    assert body =~ "const MIN_GAP = 8"
    assert body =~ "touch"

    # anti-vacuity LIVE mutants (not comment-only) + rRLG-lite / Gestalt floors
    assert body =~ "Anti-vacuity"
    assert body =~ "ANTI-VACUITY: Gestalt inter < 2·intra must FAIL proximity ratio"
    assert body =~ "LOUD_SKIP: Gestalt ratio subjects missing"
    assert body =~ "LOUD_SKIP: CI_MUTATION=0"
    assert body =~ "assertRrLgLite"
    assert body =~ "assertGestaltRatio"
    assert body =~ "assertTextSpacing"
    refute body =~ ~r/if \(intraGaps\.length === 0 \|\| groupBoxes\.length < 2\) return;/

    # CCS selectors landed in the court model JSON
    assert body =~ "sight-glass"
    assert body =~ "hcb-armed"
    assert body =~ "nav-home"
  end

  test "render embeds viewport sweep and court floors from property_groups fixture" do
    assert {:ok, court} = SpatialCourt.from_ontology(@fixture)
    assert {:ok, body} = SpatialCourt.render(court)

    assert body =~ "UI_LAYOUT_PLAYWRIGHT_VIEWPORTS"
    assert body =~ "UI_LAYOUT_VIEWPORTS"
    assert body =~ "parseViewportCsv"
    assert body =~ "[320,375,393,414,600,768,840,1024,1280]"
    assert body =~ "viewport"
    assert body =~ "assertNoHorizontalOverflow"
    assert body =~ "overflow"
    assert body =~ "assertTouchAndGap"
    assert body =~ "touch"
    assert body =~ "Anti-vacuity"
    assert body =~ "ANTI-VACUITY: Gestalt inter < 2·intra must FAIL proximity ratio"
    assert body =~ "LOUD_SKIP: Gestalt ratio subjects missing"
    assert body =~ "data-testid='save'"
  end

  test "emit writes *.spatial-court.spec.ts from property_groups fixture" do
    dir = Path.join(System.tmp_dir!(), "spatial_court_#{System.unique_integer([:positive])}")
    File.mkdir_p!(dir)
    on_exit(fn -> File.rm_rf!(dir) end)

    assert {:ok, court} = SpatialCourt.from_ontology(@fixture)
    assert {:ok, path} = SpatialCourt.emit(court, out: dir)
    assert String.ends_with?(path, ".spatial-court.spec.ts")
    assert File.regular?(path)

    body = File.read!(path)
    assert body =~ "spatial court"
    assert body =~ "viewport"
    assert body =~ "overflow"
    assert body =~ "touch"
    assert body =~ "Anti-vacuity"
  end

  test "refuses empty RDF graph" do
    assert {:error, {:spatial_court_refused, :no_property_groups}} =
             SpatialCourt.from_graph(RDF.Graph.new())
  end

  test "refuses empty court model on render" do
    assert {:error, {:spatial_court_refused, :empty_court}} =
             SpatialCourt.render(%{groups: []})
  end

  test "refuses ontology with no PropertyGroup" do
    path = Path.join(System.tmp_dir!(), "empty_#{System.unique_integer([:positive])}.ttl")
    File.write!(path, "@prefix ex: <https://example.test#> .\nex:x a ex:NotAGroup .\n")
    on_exit(fn -> File.rm!(path) end)

    assert {:error, {:spatial_court_refused, :no_property_groups}} =
             SpatialCourt.from_ontology(path)
  end

  test "refuses missing ontology path" do
    missing =
      Path.join(System.tmp_dir!(), "missing_spatial_#{System.unique_integer([:positive])}.ttl")

    assert {:error, {:spatial_court_refused, {:ontology_missing, ^missing}}} =
             SpatialCourt.from_ontology(missing)
  end

  test "marketplace pack ontology emits Playwright Spatial Court (blank-node + shui:selector)" do
    assert File.regular?(@pack_ontology),
           "marketplace ontology missing at #{@pack_ontology} — expected real collaborator"

    dir =
      Path.join(System.tmp_dir!(), "spatial_court_pack_#{System.unique_integer([:positive])}")

    File.mkdir_p!(dir)
    on_exit(fn -> File.rm_rf!(dir) end)

    # Pack ontology.ttl now annotates blank-node CCS with shui:selector
    # (including empty container _:disclosureRoot). Expect emit, not refuse.
    assert {:ok, court} = SpatialCourt.from_ontology(@pack_ontology)
    assert length(court.groups) == 6

    labels = Enum.map(court.groups, & &1.label)
    assert "Sight Glass" in labels
    assert "Human Circuit Breaker" in labels
    assert "Progressive Disclosure" in labels
    assert "Bottom Navigation" in labels

    # Disclosure root carries a lawful toggle member (pack ontology).
    disclosure =
      Enum.find(court.groups, &(&1.label == "Progressive Disclosure"))

    assert Enum.any?(disclosure.members, &(&1.selector =~ "disclosure-toggle"))
    assert disclosure.selector =~ "progressive-disclosure"

    assert {:ok, path} = SpatialCourt.emit(court, out: dir)
    assert String.ends_with?(path, ".spatial-court.spec.ts")
    body = File.read!(path)
    assert body =~ "assertNoHorizontalOverflow"
    assert body =~ "assertTouchAndGap"
    assert body =~ "sight-glass"
    assert body =~ "hcb-armed"
    assert body =~ "nav-home"
    assert body =~ "progressive-disclosure"
  end

  test "blank-node PropertyGroup members without selectors are refused" do
    assert File.regular?(@blank_no_sel), "missing fixture #{@blank_no_sel}"

    # Mixed graph keeps one ok group so refuse is typed :group_errors
    # (not the all-fail collapse to :no_property_groups).
    assert {:error, {:spatial_court_refused, {:group_errors, errs}}} =
             SpatialCourt.from_ontology(@blank_no_sel)

    assert [{:member_errors, [{:selector_required, id}]}] = errs
    assert is_binary(id) and id != ""
  end

  test "emit refuses without :out" do
    assert {:ok, court} = SpatialCourt.from_ontology(@fixture)

    assert {:error, {:spatial_court_refused, :missing_out}} =
             SpatialCourt.emit(court, [])
  end
end
