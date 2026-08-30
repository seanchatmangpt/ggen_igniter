defmodule GgenIgniter.ReconciliationManifestTest do
  @moduledoc """
  Real, subprocess-driven proof of the RECONCILIATION MANIFEST
  (`GgenIgniter.Manifest`, wired into `Mix.Tasks.GgenIgniter.Sync`'s
  `igniter/1`): `mix ggen_igniter.sync` now knows what it previously wrote,
  so a rename/removal in the ontology produces a mechanically DETECTABLE
  stale output (`.ggen_igniter/manifest.json`) instead of a silently
  orphaned file -- closing the exact gap
  `test/ggen_igniter_destructive_change_agent3_test.exs` cases 7/8 reproduce
  and disclose ("REAL GAP: `mode: file` for_each has no manifest of
  previously-written output paths...").

  Every assertion here is against REAL files this process itself writes and
  re-reads (`--pack-dir test/fixtures/ash-lifecycle-pack`, a real `mix
  ggen_igniter.sync` subprocess via `System.cmd/3`, real `File.read!/1`, a
  real independently-recomputed SHA-256 via `GgenIgniter.Manifest.hash_content/1`
  against the real bytes on disk) -- no mocking anywhere. `--manifest-dir` is
  always pointed at each test's own fresh tmp `out_dir` (never this repo's
  own root) precisely so the manifest is "written into the CONSUMER
  project's own directory" the same way a real consumer's `mix
  ggen_igniter.sync` invocation would, without leaving
  `.ggen_igniter/manifest.json` state behind in `ggen_igniter`'s own
  checkout.

  `--engine sparql` is pinned throughout, matching
  `ggen_igniter_destructive_change_agent3_test.exs`'s and
  `test/e2e/lifecycle_test.ex`'s own documented reasoning: oxigraph's raw,
  quoted N-Triples-style term strings are not what this pack's
  templates/assertions were authored against.
  """
  use ExUnit.Case, async: false

  @moduletag :integration

  alias GgenIgniter.Manifest

  @pack_dir "test/fixtures/ash-lifecycle-pack"
  @resource_template Path.join(@pack_dir, "templates/resource.ex.eex")
  @ontology_base Path.join(@pack_dir, "ontology.ttl")
  @ontology_rename Path.join(@pack_dir, "ontology_v9_rename_resource.ttl")

  defp tmp_dir!(tag) do
    dir =
      Path.join(
        System.tmp_dir!(),
        "ggen_igniter_manifest_#{tag}_#{System.unique_integer([:positive])}"
      )

    File.rm_rf!(dir)
    File.mkdir_p!(dir)
    on_exit(fn -> File.rm_rf!(dir) end)
    dir
  end

  defp out_template(out_dir), do: Path.join(out_dir, "<%= String.downcase(resource_name) %>.ex")

  # Runs `mix ggen_igniter.sync` as a real subprocess against THIS repo
  # (cd: File.cwd!() -- the only way to invoke this repo's own Mix task
  # without a full scaffolded consumer app, same convention every other
  # sync*_test.exs file already uses), with BOTH --out and --manifest-dir
  # pointed at `out_dir` -- so the reconciliation manifest this run produces
  # lands under `out_dir/.ggen_igniter/manifest.json`, never in ggen_igniter's
  # own checkout.
  defp sync_resources!(ontology_path, out_dir, extra_args \\ []) do
    args =
      [
        "ggen_igniter.sync",
        "--engine",
        "sparql",
        "--pack-dir",
        @pack_dir,
        "--ontology",
        ontology_path,
        "--template",
        @resource_template,
        "--for-each",
        "resource",
        "--out",
        out_template(out_dir),
        "--manifest-dir",
        out_dir,
        # v26.9.2: `--for-each` now routes through
        # `GgenIgniter.Reactors.ReconcileReactor.run/1`, whose `:verify` step
        # runs a real `mix compile --warnings-as-errors` subprocess -- it
        # needs a real Mix project directory to `cd:` into, which `out_dir`
        # (a bare tmp dir) is not. Before v26.9.2, `--for-each` always ran
        # via the inline `run_pipeline!/3` pipeline, which has no `:verify`
        # step at all, so this flag was never needed here.
        "--verify-cwd",
        File.cwd!()
      ] ++ extra_args

    System.cmd("mix", args, cd: File.cwd!(), stderr_to_stdout: true)
  end

  defp manifest_path(out_dir), do: Manifest.path(out_dir)

  defp read_manifest!(out_dir) do
    out_dir |> manifest_path() |> File.read!() |> Jason.decode!()
  end

  defp recipe_key(out_dir), do: Manifest.recipe_key(@resource_template, out_template(out_dir))

  defp real_hash!(path), do: path |> File.read!() |> Manifest.hash_content()

  # -- 1. First run creates a manifest with the real written paths. ---------
  test "first sync creates a manifest recording the real written output paths and content hashes" do
    out_dir = tmp_dir!("first_run")
    ticket_path = Path.join(out_dir, "ticket.ex")
    customer_path = Path.join(out_dir, "customer.ex")

    {output, exit_code} = sync_resources!(@ontology_base, out_dir)
    assert exit_code == 0, "expected a clean sync, got:\n#{output}"

    assert File.exists?(ticket_path)
    assert File.exists?(customer_path)
    assert File.exists?(manifest_path(out_dir))

    manifest = read_manifest!(out_dir)
    assert manifest["version"] == 1

    key = recipe_key(out_dir)
    entry = manifest["entries"][key]
    assert entry, "expected an entry for key #{inspect(key)}, got: #{inspect(manifest)}"

    assert entry["template"] == @resource_template
    assert entry["out_template"] == out_template(out_dir)
    assert entry["pack_dir"] == @pack_dir
    assert is_binary(entry["updated_at"])
    # Real, parseable UTC timestamp -- not merely "some string".
    assert {:ok, _dt, _offset} = DateTime.from_iso8601(entry["updated_at"])

    outputs = entry["outputs"]
    assert Map.keys(outputs) |> Enum.sort() == Enum.sort([ticket_path, customer_path])

    # Real content hashes: independently recomputed here (via the same
    # GgenIgniter.Manifest.hash_content/1 the task uses) against the REAL
    # bytes currently on disk -- not a hardcoded/expected string.
    assert outputs[ticket_path] == real_hash!(ticket_path)
    assert outputs[customer_path] == real_hash!(customer_path)
    assert String.starts_with?(outputs[ticket_path], "sha256:")
  end

  # -- 2. A no-op re-run leaves the manifest unchanged. ----------------------
  test "a no-op re-sync (same ontology) leaves the manifest byte-for-byte unchanged" do
    out_dir = tmp_dir!("noop_rerun")

    {_output, 0} = sync_resources!(@ontology_base, out_dir)
    manifest_bytes_before = File.read!(manifest_path(out_dir))

    {output, exit_code} = sync_resources!(@ontology_base, out_dir)
    assert exit_code == 0, "expected a clean re-sync, got:\n#{output}"

    # The underlying writes really no-op'd (Actuate.write_file!/3's own
    # idempotent-content check) -- this proves the re-run genuinely produced
    # byte-identical output, not merely that the manifest write happened to
    # be skipped for an unrelated reason.
    assert output =~ "unchanged (skipped, identical content)"

    manifest_bytes_after = File.read!(manifest_path(out_dir))

    assert manifest_bytes_after == manifest_bytes_before,
           "expected the manifest file to be completely untouched (not even its " <>
             "timestamp) by a genuine no-op re-run"
  end

  # -- 3. Rename resource (Ticket -> Case): default policy (--on-stale
  #    omitted) is refuse -- refuses BEFORE writing anything new. ------------
  test "rename resource with the default --on-stale (refuse): refuses before any new write, nothing is written or deleted" do
    out_dir = tmp_dir!("rename_refuse")
    ticket_path = Path.join(out_dir, "ticket.ex")
    case_path = Path.join(out_dir, "case.ex")

    {_output, 0} = sync_resources!(@ontology_base, out_dir)
    assert File.exists?(ticket_path)
    ticket_before = File.read!(ticket_path)
    assert ticket_before =~ "defmodule SupportDesk.Support.Ticket do"
    manifest_bytes_before = File.read!(manifest_path(out_dir))

    # No --on-stale flag at all: proves the DEFAULT is refuse, not merely
    # that --on-stale refuse (spelled out) works.
    {output, exit_code} = sync_resources!(@ontology_rename, out_dir)

    refute exit_code == 0,
           "expected the default --on-stale refuse to fail this run closed, got:\n#{output}"

    assert output =~ "refusing to sync"
    assert output =~ ticket_path
    assert output =~ "--on-stale prune"
    assert output =~ "--on-stale preserve"

    # Complete reconciliation or refusal before ANY partial actuation: the
    # new identity's file must NOT have been written...
    refute File.exists?(case_path),
           "expected refuse to write NOTHING this run, but #{case_path} was created"

    # ...and the old file must be completely untouched (same content as
    # before this refused run, not merely "still present").
    assert File.exists?(ticket_path)
    assert File.read!(ticket_path) == ticket_before

    # ...and the manifest itself must never have been touched by a refused
    # run (still reflects the last KNOWN-GOOD state, per this task's
    # partial-run-safety design).
    assert File.read!(manifest_path(out_dir)) == manifest_bytes_before
  end

  # -- 4. Rename resource: --on-stale prune really deletes the stale path and
  #    reports it, and reconciles the manifest to the new path set. --------
  test "rename resource with --on-stale prune: writes the new identity and really deletes the stale old one" do
    out_dir = tmp_dir!("rename_prune")
    ticket_path = Path.join(out_dir, "ticket.ex")
    case_path = Path.join(out_dir, "case.ex")
    customer_path = Path.join(out_dir, "customer.ex")

    {_output, 0} = sync_resources!(@ontology_base, out_dir)
    assert File.exists?(ticket_path)

    {output, exit_code} = sync_resources!(@ontology_rename, out_dir, ["--on-stale", "prune"])
    assert exit_code == 0, "expected --on-stale prune to succeed, got:\n#{output}"

    assert output =~ "pruned: #{ticket_path}"

    assert File.exists?(case_path)
    case_content = File.read!(case_path)
    assert Code.string_to_quoted!(case_content)
    assert case_content =~ "defmodule SupportDesk.Support.Case do"

    refute File.exists?(ticket_path),
           "expected --on-stale prune to have really deleted the stale #{ticket_path}"

    manifest = read_manifest!(out_dir)
    entry = manifest["entries"][recipe_key(out_dir)]
    outputs = entry["outputs"]

    # The pack's `resource` driver query still yields TWO rows every run
    # (Case, the renamed identity, and Customer, untouched) -- only the OLD
    # `ticket.ex` path (no longer produced by any row) is stale and pruned.
    assert Enum.sort(Map.keys(outputs)) == Enum.sort([case_path, customer_path])
    assert outputs[case_path] == real_hash!(case_path)
    assert outputs[customer_path] == real_hash!(customer_path)
  end

  # -- 5. Rename resource: --on-stale preserve leaves the stale path
  #    untouched on disk, warns about it, and drops it from manifest
  #    tracking (this pack no longer claims ownership of a path it isn't
  #    producing this run). -----------------------------------------------
  test "rename resource with --on-stale preserve: writes the new identity, warns about and leaves the stale old one" do
    out_dir = tmp_dir!("rename_preserve")
    ticket_path = Path.join(out_dir, "ticket.ex")
    case_path = Path.join(out_dir, "case.ex")
    customer_path = Path.join(out_dir, "customer.ex")

    {_output, 0} = sync_resources!(@ontology_base, out_dir)
    assert File.exists?(ticket_path)
    ticket_before = File.read!(ticket_path)

    {output, exit_code} = sync_resources!(@ontology_rename, out_dir, ["--on-stale", "preserve"])
    assert exit_code == 0, "expected --on-stale preserve to succeed, got:\n#{output}"

    assert output =~ "WARNING"
    assert output =~ ticket_path

    assert File.exists?(case_path)
    assert File.read!(case_path) =~ "defmodule SupportDesk.Support.Case do"

    # Left on disk, completely untouched.
    assert File.exists?(ticket_path)
    assert File.read!(ticket_path) == ticket_before

    # No longer tracked as this recipe's output going forward -- released,
    # not deleted.
    manifest = read_manifest!(out_dir)
    entry = manifest["entries"][recipe_key(out_dir)]
    outputs = entry["outputs"]

    assert Enum.sort(Map.keys(outputs)) == Enum.sort([case_path, customer_path])
    refute Map.has_key?(outputs, ticket_path)
  end

  # -- 6. Bonus: --dry-run previews the same refusal honestly, touching
  #    nothing at all (no write, no delete, no manifest write). -------------
  test "rename resource with --dry-run (default --on-stale refuse): raises the same refusal, touches nothing" do
    out_dir = tmp_dir!("rename_dry_run_refuse")
    ticket_path = Path.join(out_dir, "ticket.ex")
    case_path = Path.join(out_dir, "case.ex")

    {_output, 0} = sync_resources!(@ontology_base, out_dir)
    manifest_bytes_before = File.read!(manifest_path(out_dir))
    ticket_before = File.read!(ticket_path)

    {output, exit_code} = sync_resources!(@ontology_rename, out_dir, ["--dry-run"])

    refute exit_code == 0,
           "expected --dry-run to still surface the real refusal decision, got:\n#{output}"

    assert output =~ "refusing to sync"
    refute File.exists?(case_path)
    assert File.read!(ticket_path) == ticket_before
    assert File.read!(manifest_path(out_dir)) == manifest_bytes_before
  end
end
