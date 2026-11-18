defmodule GgenIgniterShippedPacksFenceTest do
  @moduledoc """
  Fast (no `mix hex.build`) Chicago fence for `mix.exs` `shipped_packs/0`:

  * `Mix.Project.config()[:package][:files]` is the real package file list
    Hex will publish — assert it admits `ash-manufacture-pack` and rejects
    every other on-disk ash-named pack under `priv/ggen/`.
  * `GgenIgniter.PackCatalog` `hex_shipped` must mirror that same rule.

  The heavier unpacked-tarball court lives in
  `test/ggen_igniter_package_ash_free_test.exs` (`:package`).
  """
  use ExUnit.Case, async: true

  test "Mix package files ship ash-manufacture-pack only among ash-named packs" do
    pack_roots = package_pack_roots()
    on_disk_packs = on_disk_pack_dirs()
    ash_on_disk = Enum.filter(on_disk_packs, &String.contains?(&1, "ash"))

    assert "ash-manufacture-pack" in ash_on_disk,
           "sanity: ash-manufacture-pack must exist on disk"

    assert "ash-manufacture-pack" in pack_roots

    for pack <- ash_on_disk, pack != "ash-manufacture-pack" do
      refute pack in pack_roots, "#{pack} must be excluded from Hex package files"
    end

    assert "semantic-jira-pack" in pack_roots, "sanity: non-ash packs still ship"
    refute Enum.any?(pack_roots, &String.contains?(&1, "priv/native")),
           "sanity: package files must not list priv/native"
  end

  test "PackCatalog.hex_shipped mirrors Mix shipped_packs for every priv/ggen pack" do
    pack_roots = MapSet.new(package_pack_roots())

    for entry <- GgenIgniter.PackCatalog.list() do
      basename = Path.basename(entry.dir)
      expected = MapSet.member?(pack_roots, basename)
      assert entry.hex_shipped == expected,
             "#{basename}: PackCatalog.hex_shipped=#{entry.hex_shipped} but Mix package files #{if expected, do: "include", else: "exclude"} it"
    end
  end

  test "ash-named packs currently on disk match the known reject set (anti-vacuity)" do
    ash_on_disk =
      on_disk_pack_dirs()
      |> Enum.filter(&String.contains?(&1, "ash"))
      |> Enum.sort()

    # If this set shrinks to only manufacture, the reject half of the fence
    # has nothing left to exclude — that would be a vacuous pass.
    assert "ash-manufacture-pack" in ash_on_disk
    assert length(ash_on_disk) > 1, "need ≥1 rejected ash pack on disk to enforce the fence"

    expected_rejects =
      ash_on_disk
      |> Enum.reject(&(&1 == "ash-manufacture-pack"))
      |> Enum.sort()

    for pack <- expected_rejects do
      refute pack in package_pack_roots()
    end

    # Named samples — refuse silent renames that would dodge the substring fence.
    for pack <- [
          "ash-igniter-api-pack",
          "ash-notifier-load2-pack",
          "ash-lifecycle-pack-inprocess-dispatch-test"
        ] do
      assert pack in expected_rejects, "expected reject sample missing on disk: #{pack}"
    end
  end

  defp package_pack_roots do
    Mix.Project.config()
    |> Keyword.fetch!(:package)
    |> Keyword.fetch!(:files)
    |> Enum.filter(&String.starts_with?(&1, "priv/ggen/"))
    |> Enum.map(fn
      "priv/ggen/" <> rest -> rest |> Path.split() |> hd()
      other -> other
    end)
    |> Enum.uniq()
    |> Enum.sort()
  end

  defp on_disk_pack_dirs do
    "priv/ggen"
    |> File.ls!()
    |> Enum.filter(&File.dir?(Path.join("priv/ggen", &1)))
    |> Enum.sort()
  end
end
