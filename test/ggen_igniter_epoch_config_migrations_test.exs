defmodule GgenIgniter.EpochConfigMigrationsTest do
  @moduledoc """
  Falsifier corpus for the three-plane epoch law (config/ + migrations
  courts). Real temp git repositories, real files, no test doubles: the
  stamp court is proven to bind `config/**/*.exs` and
  `priv/repo/migrations/**/*.exs` by committing REAL pre-epoch config and
  migration files and refusing edits to them; the vacuous-migrations leg
  is witnessed over a repo with NO migrations directory (this repo's real
  condition) and must report the plane as loudly vacuous, never silent.
  """

  use ExUnit.Case, async: false

  alias GgenIgniter.EpochFreshness
  alias GgenIgniter.EpochWatermark
  alias GgenIgniter.SemanticJira.EpochPlan

  @epoch "v26.10.20"
  @boundary ~U[2026-10-15 00:00:00Z]

  @lib_impl """
  defmodule Legacy.Core do
    def run(x), do: {:ok, x}
  end
  """

  @config_impl """
  import Config

  config :app, Legacy.Repo,
    username: "legacy",
    password: "legacy",
    hostname: "localhost"
  """

  @config_impl_edited """
  import Config

  config :app, Legacy.Repo,
    username: "legacy",
    password: "legacy",
    hostname: "localhost",
    pool_size: 11
  """

  @migration """
  defmodule Legacy.Repo.Migrations.CreateBooks do
    use Ecto.Migration

    def change do
      create table(:books) do
        add :title, :string
      end
    end
  end
  """

  setup do
    dir = fresh_repo()
    on_exit(fn -> File.rm_rf(dir) end)
    %{dir: dir}
  end

  # -- watermark: three-plane stamping -------------------------------------------

  test "stamp! records identities for lib, config, and migrations planes", %{dir: dir} do
    File.mkdir_p!(Path.join(dir, "config"))
    File.write!(Path.join(dir, "config/app.exs"), @config_impl)
    File.mkdir_p!(Path.join(dir, "priv/repo/migrations"))
    File.write!(Path.join(dir, "priv/repo/migrations/20200101000000_create_books.exs"), @migration)
    commit_all(dir, "add config + migrations")

    assert {:ok, manifest, _path} = EpochWatermark.stamp!(dir, @epoch, now: @boundary)

    globs = manifest["implementation_globs"]
    assert "lib/**/*.ex" in globs
    assert "config/**/*.exs" in globs
    assert "priv/repo/migrations/**/*.exs" in globs

    paths = Enum.map(manifest["files"], & &1["path"])
    assert "lib/legacy.ex" in paths
    assert "config/app.exs" in paths
    assert "priv/repo/migrations/20200101000000_create_books.exs" in paths
  end

  test "a migration edited after the watermark is REFUSED_LEGACY_EDIT", %{dir: dir} do
    File.mkdir_p!(Path.join(dir, "priv/repo/migrations"))
    File.write!(Path.join(dir, "priv/repo/migrations/20200101000000_create_books.exs"), @migration)
    commit_all(dir, "add migration")

    stamp_watermark(dir)

    File.write!(
      Path.join(dir, "priv/repo/migrations/20200101000000_create_books.exs"),
      @migration <> "\n# touched\n"
    )

    commit_all(dir, "touch migration")

    {:ok, report} = EpochFreshness.check(dir, @epoch)
    assert %{"verdict" => :REFUSED_LEGACY_EDIT} = file_report(report, "priv/repo/migrations/20200101000000_create_books.exs")
    assert report["standing"] == :REFUSED
  end

  test "a config file edited after the watermark is REFUSED_LEGACY_EDIT", %{dir: dir} do
    File.mkdir_p!(Path.join(dir, "config"))
    File.write!(Path.join(dir, "config/test.exs"), @config_impl)
    commit_all(dir, "add config")

    stamp_watermark(dir)

    File.write!(Path.join(dir, "config/test.exs"), @config_impl_edited)
    commit_all(dir, "edit config")

    {:ok, report} = EpochFreshness.check(dir, @epoch)

    assert %{"verdict" => :REFUSED_LEGACY_EDIT} =
             file_report(report, "config/test.exs")

    assert report["standing"] == :REFUSED
  end

  test "fresh attributed config file (ledger row) is ALIVE_FRESH_RESIDUE", %{dir: dir} do
    stamp_watermark(dir)

    File.mkdir_p!(Path.join(dir, "config"))
    File.write!(Path.join(dir, "config/runtime.exs"), @config_impl_edited)
    commit_all(dir, "add runtime config")

    add_ledger_row(dir, "config/runtime.exs", ~D[2026-10-15])

    {:ok, report} = EpochFreshness.check(dir, @epoch)
    assert %{"verdict" => :ALIVE_FRESH_RESIDUE} = file_report(report, "config/runtime.exs")
  end

  # -- vacuously-empty migrations plane (loud, never silent) ---------------------

  test "vacuous migrations plane: glob stays bound, plane reported, not silent", %{dir: dir} do
    # This repo's real condition: no priv/repo/migrations at stamp time.
    stamp_watermark(dir)

    {:ok, manifest} = EpochWatermark.load(dir, @epoch)
    assert "priv/repo/migrations/**/*.exs" in manifest["implementation_globs"]

    {:ok, report} = EpochFreshness.check(dir, @epoch)

    planes = report["planes"]
    mig = Enum.find(planes, &(&1["glob"] == "priv/repo/migrations/**/*.exs"))
    assert mig["counts"]["total"] == 0
    # The plane is named and its zero-file state is explicit in the report.
    assert mig["watermarked"] == true
  end

  test "a NEW migration appearing after an old lib-only watermark refuses", %{dir: dir} do
    # Hand-craft a pre-multi-plane watermark (schema as the first court wrote it).
    legacy_manifest = %{
      "schema_version" => "1",
      "epoch" => @epoch,
      "watermark_instant" => DateTime.to_iso8601(@boundary),
      "implementation_glob" => "lib/**/*.ex",
      "head_sha" => head_sha(dir),
      "tree_sha" => tree_sha(dir),
      "files" => [%{"path" => "lib/legacy.ex", "blob_sha" => blob_sha_of(dir, "lib/legacy.ex")}]
    }

    write_manifest(dir, legacy_manifest)

    # A new migration shows up after the boundary.
    File.mkdir_p!(Path.join(dir, "priv/repo/migrations"))
    File.write!(Path.join(dir, "priv/repo/migrations/20261016000000_new.exs"), @migration)
    commit_all(dir, "new migration")

    {:ok, report} = EpochFreshness.check(dir, @epoch)

    # Fail closed: the migration gets a typed refusing verdict.
    assert %{"verdict" => :REFUSED_NO_ATTRIBUTION} =
             file_report(report, "priv/repo/migrations/20261016000000_new.exs")

    # The plane itself is typed UNKNOWN (boundary never covered it).
    mig = Enum.find(report["planes"], &(&1["glob"] == "priv/repo/migrations/**/*.exs"))
    assert mig["standing"] == :UNKNOWN_PROVENANCE
    assert mig["watermarked"] == false

    # The legacy lib plane still judges with the same old boundary.
    lib = Enum.find(report["planes"], &(&1["glob"] == "lib/**/*.ex"))
    assert lib["standing"] == :REFUSED
    assert lib["watermarked"] == true
  end

  # -- admission gate (EpochPlan) across planes -----------------------------------

  test "epoch plan gate refuses an order touching a stamped migration", %{dir: dir} do
    File.mkdir_p!(Path.join(dir, "priv/repo/migrations"))
    File.write!(Path.join(dir, "priv/repo/migrations/20200101000000_create_books.exs"), @migration)
    commit_all(dir, "add migration")

    manifest = stamp_watermark(dir)
    watermark = Map.delete(manifest, "restamp_reason")

    order = %{
      "epoch" => @epoch,
      "plan_touches" => ["priv/repo/migrations/20200101000000_create_books.exs"]
    }

    assert {:error, {:refused_epoch_plan, :legacy_edit}} = EpochPlan.check(order, watermark)
  end

  test "epoch plan gate refuses UNATTRIBUTED new config path without a fresh plan", %{dir: dir} do
    manifest = stamp_watermark(dir)
    watermark = Map.delete(manifest, "restamp_reason")

    order = %{
      "epoch" => @epoch,
      "plan_touches" => ["config/brand_new.exs"]
    }

    assert {:error, {:refused_epoch_plan, :unattributed_implementation}} =
             EpochPlan.check(order, watermark)
  end

  test "epoch plan gate: fresh manufacture plan for new config path is lawful", %{dir: dir} do
    manifest = stamp_watermark(dir)
    watermark = Map.delete(manifest, "restamp_reason")

    order = %{
      "epoch" => @epoch,
      "plan_touches" => ["config/brand_new.exs"],
      "manufacture_plan" => %{"config/brand_new.exs" => "generated"}
    }

    assert :ok = EpochPlan.check(order, watermark)
  end

  test "epoch plan gate accepts multi-glob watermark shape directly", %{dir: dir} do
    manifest = stamp_watermark(dir)
    watermark = Map.delete(manifest, "restamp_reason")
    assert is_list(watermark["implementation_globs"])

    order = %{"epoch" => @epoch, "plan_touches" => ["lib/other.ex"]}
    assert {:error, {:refused_epoch_plan, :unattributed_implementation}} =
             EpochPlan.check(order, watermark)
  end

  # -- fixtures ----------------------------------------------------------------

  defp fresh_repo do
    dir =
      Path.join(System.tmp_dir!(), "epoch-planes-#{:erlang.unique_integer([:positive])}")

    File.mkdir_p!(Path.join(dir, "lib"))
    git!(dir, ["init"])
    git!(dir, ["config", "user.email", "epoch@test"])
    git!(dir, ["config", "user.name", "epoch test"])

    File.write!(Path.join(dir, "lib/legacy.ex"), @lib_impl)
    commit_all(dir, "legacy implementation")

    dir
  end

  defp stamp_watermark(dir, opts \\ []) do
    assert {:ok, manifest, _path} =
             EpochWatermark.stamp!(dir, @epoch, Keyword.merge([now: @boundary], opts))

    manifest
  end

  defp commit_all(dir, message) do
    git!(dir, ["add", "."])
    git!(dir, ["commit", "--no-gpg-sign", "-m", message])
  end

  defp git!(dir, args) do
    {out, code} = System.cmd("git", args, cd: dir, stderr_to_stdout: true)

    if code != 0, do: flunk("git #{Enum.join(args, " ")} failed: #{out}")

    out
  end

  defp head_sha(dir), do: String.trim(git!(dir, ["rev-parse", "HEAD"]))
  defp tree_sha(dir), do: String.trim(git!(dir, ["rev-parse", "HEAD^{tree}"]))

  defp blob_sha_of(dir, rel) do
    {out, 0} = System.cmd("git", ["ls-files", "-s", rel], cd: dir, stderr_to_stdout: true)
    [oid | _] = String.split(String.trim(out), " ")
    oid
  end

  defp write_manifest(dir, manifest) do
    file = EpochWatermark.path(dir, @epoch)
    File.mkdir_p!(Path.dirname(file))
    File.write!(file, Jason.encode!(manifest) <> "\n")
  end

  defp add_ledger_row(dir, path, date) do
    row = "#{path} | some element | some capability | some-owner-pack | #{Date.to_iso8601(date)}"
    File.write!(Path.join(dir, "HANDWRITTEN.md"), row <> "\n")
  end

  defp file_report(report, path) do
    Enum.find(report["files"], &(&1["path"] == path))
  end
end
