defmodule GgenIgniter.BrandThemeTest do
  @moduledoc """
  Chicago: real brand.toml fixture → BrandTheme.from_brand/1 → render/emit.
  Orthogonal to SpatialCourt (no SHACL / Playwright).
  """
  use ExUnit.Case, async: true

  alias GgenIgniter.BrandTheme

  @fixture Path.expand("fixtures/brand_theme/fourth-watch.brand.toml", __DIR__)
  @marketplace_brand "/Users/sac/ggen-marketplace/packs/mobile-ui-layout-pack/brand/fourth-watch.brand.toml"

  test "from_brand resolves space aliases to var() and touch to literals" do
    assert {:ok, brand} = BrandTheme.from_brand(@fixture)
    entries = Map.new(brand.theme_entries)

    assert entries["--spacing-0_5"] == "4px"
    assert entries["--spacing-tight"] == "var(--spacing-0_5)"
    assert entries["--spacing-fluid-inset"] == "clamp(1rem, 0.5rem + 2.5cqi, 1.5rem)"
    assert entries["--spacing-card"] == "clamp(1rem, 0.333rem + 3.333cqi, 2rem)"
    assert entries["--spacing-touch-min"] == "44px"
    assert entries["--spacing-touch-comfortable"] == "48px"
    assert entries["--spacing-shell-height"] == "100dvh"
  end

  test "render embeds @theme fluid tokens and utility shell" do
    assert {:ok, brand} = BrandTheme.from_brand(@fixture)
    assert {:ok, body} = BrandTheme.render(brand)

    assert body =~ "@theme {"
    assert body =~ "--spacing-fluid-inset: clamp(1rem, 0.5rem + 2.5cqi, 1.5rem);"
    assert body =~ "--spacing-touch-min: 44px;"
    assert body =~ "container-type: inline-size;"
    assert body =~ "min-height: 100dvh;"
    assert body =~ "touch-action: manipulation;"
    assert body =~ "font-size: max(16px, 1rem);"
    assert body =~ "@media (hover: hover) and (pointer: fine)"
    refute body =~ "@property"
  end

  test "emit writes *-theme-spacing.css" do
    dir = Path.join(System.tmp_dir!(), "brand_theme_#{System.unique_integer([:positive])}")
    File.mkdir_p!(dir)
    on_exit(fn -> File.rm_rf!(dir) end)

    assert {:ok, brand} = BrandTheme.from_brand(@fixture)
    assert {:ok, path} = BrandTheme.emit(brand, out: dir)
    assert String.ends_with?(path, "fourth-watch-theme-spacing.css")
    assert File.regular?(path)
    assert File.read!(path) =~ "--spacing-card:"
  end

  test "refuses missing brand.toml" do
    assert {:error, {:brand_theme_refused, {:brand_missing, _}}} =
             BrandTheme.from_brand("/tmp/definitely-missing-brand-#{System.unique_integer([:positive])}.toml")
  end

  test "shipped template path exists under priv/ggen/brand-theme-pack" do
    assert File.regular?(BrandTheme.template_path())
  end

  @tag :marketplace
  test "marketplace fourth-watch.brand.toml emits full fluid ladder" do
    if File.regular?(@marketplace_brand) do
      assert {:ok, brand} = BrandTheme.from_brand(@marketplace_brand)
      assert {:ok, body} = BrandTheme.render(brand)
      assert body =~ "--spacing-12: 96px;"
      assert body =~ "--spacing-fluid-section: clamp(1.5rem, 0.75rem + 3.75cqi, 3rem);"
      assert body =~ "--spacing-margin-compact: var(--spacing-2);"
    else
      flunk("marketplace brand missing at #{@marketplace_brand}")
    end
  end
end
