defmodule GgenIgniter.SyncInProcessReconcileTest do
  @moduledoc """
  Chicago-style, no-mocks proof that `Mix.Tasks.GgenIgniter.Sync.igniter/1`'s
  RECONCILIATION MANIFEST logic (`--on-stale refuse|prune|preserve`,
  `GgenIgniter.Manifest`) runs and behaves correctly when invoked fully
  IN-PROCESS via `Igniter.Mix.Task.configure_and_run/3` -- the same real
  plumbing `use Igniter.Mix.Task`'s generated `run/1` calls after argv
  parsing (see `GgenIgniter.SyncControllerDelegationTest`'s own `run_sync!/1`
  for the pattern this mirrors), rather than a `System.cmd("mix", ...)`
  subprocess.

  `test/ggen_igniter_reconciliation_manifest_test.exs` already proves this
  exact rename/`--on-stale` behavior end-to-end via real subprocesses -- but
  a subprocess is a separate BEAM/OS process, invisible to `mix coveralls`'s
  real instrumented coverage of THIS module (measured this session:
  `lib/mix/tasks/ggen_igniter.sync.ex` at 47.0% real coverage, with the
  entire reconciliation-manifest branch -- `resolve_on_stale!/1`,
  `refuse_stale_message/2`, `apply_stale_policy!/2` (all 3 clauses),
  `preview_stale!/2`, the `Manifest.load/get_entry/stale_paths/put/persist!`
  call sequence in `igniter/1` itself -- among the uncovered lines). Unlike
  `Mix.Tasks.GgenIgniter.Doctor.igniter/1` (which calls `System.halt(1)`
  directly on any `:error` check, making in-process testing of its failure
  paths unsafe -- see `GgenIgniter.DoctorInProcessTest`'s moduledoc), every
  `ggen_igniter.sync` failure path is a plain `raise` (`ArgumentError`),
  which propagates as a normal Elixir exception in-process -- safe to
  exercise directly with `assert_raise/2`, including the real `--on-stale
  refuse` refusal path.

  Real collaborators throughout: the real `test/fixtures/ash-lifecycle-pack`
  ontology/gate-query/template fixtures (the same ones
  `ggen_igniter_reconciliation_manifest_test.exs` uses), real `--for-each`
  fan-out, real files written to a real temp directory, real
  `GgenIgniter.Manifest.path/1`/`File.read!/1`/`Jason.decode!/1` reads of the
  real manifest this run actually wrote. No mocking anywhere.
  """
  use ExUnit.Case, async: false

  alias GgenIgniter.Manifest

  @pack_dir "test/fixtures/ash-lifecycle-pack"
  @resource_template Path.join(@pack_dir, "templates/resource.ex.eex")
  @ontology_base Path.join(@pack_dir, "ontology.ttl")
  @ontology_rename Path.join(@pack_dir, "ontology_v9_rename_resource.ttl")

  setup do
    out_dir =
      Path.join(
        System.tmp_dir!(),
        "ggen_igniter_sync_inprocess_reconcile_#{System.unique_integer([:positive])}"
      )

    File.rm_rf!(out_dir)
    File.mkdir_p!(out_dir)
    on_exit(fn -> File.rm_rf!(out_dir) end)

    %{out_dir: out_dir}
  end

  defp out_template(out_dir), do: Path.join(out_dir, "<%= String.downcase(resource_name) %>.ex")

  defp recipe_key(out_dir), do: Manifest.recipe_key(@resource_template, out_template(out_dir))

  defp read_manifest!(out_dir), do: out_dir |> Manifest.path() |> File.read!() |> Jason.decode!()

  defp real_hash!(path), do: path |> File.read!() |> Manifest.hash_content()

  defp sync_args(ontology_path, out_dir, extra_opts \\ []) do
    [
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
      out_dir
    ] ++ extra_opts
  end

  # Same real in-process plumbing as
  # `GgenIgniter.SyncControllerDelegationTest.run_sync!/1`.
  defp run_sync!(argv) do
    Igniter.new()
    |> Map.put(:task, "ggen_igniter.sync")
    |> Igniter.Mix.Task.configure_and_run(Mix.Tasks.GgenIgniter.Sync, argv)
  end

  test "first in-process sync creates a real manifest with the real written paths and content hashes",
       %{out_dir: out_dir} do
    ticket_path = Path.join(out_dir, "ticket.ex")
    customer_path = Path.join(out_dir, "customer.ex")

    igniter = run_sync!(sync_args(@ontology_base, out_dir))
    assert [notice] = igniter.notices
    assert notice =~ "wrote #{ticket_path}"

    assert File.exists?(ticket_path)
    assert File.exists?(customer_path)
    assert File.exists?(Manifest.path(out_dir))

    manifest = read_manifest!(out_dir)
    entry = manifest["entries"][recipe_key(out_dir)]
    assert entry, "expected an entry for key #{inspect(recipe_key(out_dir))}"

    outputs = entry["outputs"]
    assert Enum.sort(Map.keys(outputs)) == Enum.sort([ticket_path, customer_path])
    assert outputs[ticket_path] == real_hash!(ticket_path)
    assert String.starts_with?(outputs[ticket_path], "sha256:")
  end

  test "renaming the resource with the DEFAULT --on-stale (refuse, omitted) raises in-process " <>
         "before any write, and never touches the existing manifest",
       %{out_dir: out_dir} do
    ticket_path = Path.join(out_dir, "ticket.ex")
    case_path = Path.join(out_dir, "case.ex")

    _igniter = run_sync!(sync_args(@ontology_base, out_dir))
    assert File.exists?(ticket_path)
    ticket_before = File.read!(ticket_path)
    manifest_bytes_before = File.read!(Manifest.path(out_dir))

    # No --on-stale flag at all -- the real default, resolve_on_stale!(nil),
    # must resolve to :refuse and really raise, not silently no-op.
    error =
      assert_raise ArgumentError, fn ->
        run_sync!(sync_args(@ontology_rename, out_dir))
      end

    assert Exception.message(error) =~ "refusing to sync"
    assert Exception.message(error) =~ ticket_path
    assert Exception.message(error) =~ "--on-stale prune"
    assert Exception.message(error) =~ "--on-stale preserve"

    # Complete reconciliation or refusal before ANY partial actuation: the new
    # identity was never written, the old file and the manifest are both
    # completely untouched by the refused run.
    refute File.exists?(case_path)
    assert File.read!(ticket_path) == ticket_before
    assert File.read!(Manifest.path(out_dir)) == manifest_bytes_before
  end

  test "renaming the resource with --on-stale prune really deletes the stale output and updates " <>
         "the manifest to the new real path set",
       %{out_dir: out_dir} do
    ticket_path = Path.join(out_dir, "ticket.ex")
    case_path = Path.join(out_dir, "case.ex")
    customer_path = Path.join(out_dir, "customer.ex")

    _igniter = run_sync!(sync_args(@ontology_base, out_dir))
    assert File.exists?(ticket_path)

    igniter = run_sync!(sync_args(@ontology_rename, out_dir, ["--on-stale", "prune"]))
    assert [notice] = igniter.notices
    assert notice =~ "wrote #{case_path}"

    assert File.exists?(case_path)
    assert File.read!(case_path) =~ "defmodule SupportDesk.Support.Case do"

    refute File.exists?(ticket_path),
           "expected --on-stale prune to have really deleted the stale #{ticket_path}"

    manifest = read_manifest!(out_dir)
    outputs = manifest["entries"][recipe_key(out_dir)]["outputs"]

    assert Enum.sort(Map.keys(outputs)) == Enum.sort([case_path, customer_path])
    assert outputs[case_path] == real_hash!(case_path)
  end

  test "a genuine no-op in-process re-sync leaves the manifest byte-for-byte unchanged",
       %{out_dir: out_dir} do
    _igniter1 = run_sync!(sync_args(@ontology_base, out_dir))
    manifest_bytes_before = File.read!(Manifest.path(out_dir))

    igniter2 = run_sync!(sync_args(@ontology_base, out_dir))
    assert [notice] = igniter2.notices
    assert notice =~ "unchanged (skipped, identical content)"

    assert File.read!(Manifest.path(out_dir)) == manifest_bytes_before
  end
end
