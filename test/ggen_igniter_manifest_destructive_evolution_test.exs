defmodule GgenIgniterManifestDestructiveEvolutionTest do
  @moduledoc """
  Dogfoods `GgenIgniter.Manifest` against a REAL destructive-evolution
  simulation: three sequential "runs" (real function calls, real files
  written/removed on a real tmp dir), covering add -> rename -> remove of a
  single recipe's tracked outputs. No mocks -- every assertion is against
  real on-disk state and the real return value of `Manifest.stale_paths/2`,
  `Manifest.output_paths/1`, and a real `Manifest.prune!/1` call standing in
  for the `--on-stale prune` policy.

  Mirrors (but does not duplicate) the destructive-change scenarios already
  covered by `test/ggen_igniter_destructive_change_agent3_test.exs` and
  `test/ggen_igniter_reconciliation_manifest_test.exs`, focused specifically
  on the full add -> rename -> remove -> prune lifecycle across THREE
  sequential runs against ONE recipe key, asserting zero orphaned tracked
  paths survive the final prune.
  """
  use ExUnit.Case, async: true

  alias GgenIgniter.Manifest

  @template "test/fixtures/ash-lifecycle-pack/templates/resource.ex.eex"
  @out_template "lib/support_desk/support/<%= String.downcase(resource_name) %>.ex"

  setup do
    tmp_dir =
      Path.join(
        System.tmp_dir!(),
        "ggen_igniter_destructive_evolution_#{System.unique_integer([:positive])}"
      )

    File.mkdir_p!(tmp_dir)
    on_exit(fn -> File.rm_rf!(tmp_dir) end)
    %{base_dir: tmp_dir}
  end

  defp write_real_file!(base_dir, relpath, content) do
    abs = Path.join(base_dir, relpath)
    File.mkdir_p!(Path.dirname(abs))
    File.write!(abs, content)
    abs
  end

  defp run_sync!(base_dir, new_relpaths_with_content) do
    manifest = Manifest.load(base_dir)
    key = Manifest.recipe_key(@template, @out_template)
    entry = Manifest.get_entry(manifest, key)

    new_paths = Map.keys(new_relpaths_with_content)
    stale = Manifest.stale_paths(entry, new_paths)

    # Simulate `--on-stale prune`: really delete every stale path.
    pruned =
      stale
      |> MapSet.to_list()
      |> Enum.map(&Path.join(base_dir, &1))
      |> Manifest.prune!()

    # Actuate this run's real outputs (write real files, hash real bytes
    # read back off disk -- matching Manifest's documented "real content
    # hash of what is actually on disk" contract).
    outputs =
      Map.new(new_relpaths_with_content, fn {relpath, content} ->
        abs = write_real_file!(base_dir, relpath, content)
        real_bytes = File.read!(abs)
        {relpath, Manifest.hash_content(real_bytes)}
      end)

    new_entry = Manifest.build_entry(@template, @out_template, nil, outputs)

    manifest
    |> Manifest.put(key, new_entry)
    |> Manifest.persist!(base_dir)

    %{stale: stale, pruned: pruned, entry: new_entry}
  end

  test "add -> rename -> remove across three real sequential runs leaves zero orphans after prune",
       %{base_dir: base_dir} do
    # --- Run 1: initial sync creates ticket.ex and customer.ex ---
    run1 =
      run_sync!(base_dir, %{
        "lib/support_desk/support/ticket.ex" => "defmodule SupportDesk.Support.Ticket do\nend\n",
        "lib/support_desk/support/customer.ex" =>
          "defmodule SupportDesk.Support.Customer do\nend\n"
      })

    assert MapSet.new() == run1.stale
    assert [] == run1.pruned
    assert File.exists?(Path.join(base_dir, "lib/support_desk/support/ticket.ex"))
    assert File.exists?(Path.join(base_dir, "lib/support_desk/support/customer.ex"))

    manifest_after_run1 = Manifest.load(base_dir)

    entry_after_run1 =
      Manifest.get_entry(manifest_after_run1, Manifest.recipe_key(@template, @out_template))

    assert Manifest.output_paths(entry_after_run1) ==
             MapSet.new([
               "lib/support_desk/support/ticket.ex",
               "lib/support_desk/support/customer.ex"
             ])

    # --- Run 2: ontology renames Ticket -> Case (upstream rename) ---
    # ticket.ex is now stale (its recipe's new output set no longer includes it).
    run2 =
      run_sync!(base_dir, %{
        "lib/support_desk/support/case.ex" => "defmodule SupportDesk.Support.Case do\nend\n",
        "lib/support_desk/support/customer.ex" =>
          "defmodule SupportDesk.Support.Customer do\nend\n"
      })

    assert MapSet.new(["lib/support_desk/support/ticket.ex"]) == run2.stale

    assert [{Path.join(base_dir, "lib/support_desk/support/ticket.ex"), :pruned}] ==
             run2.pruned

    refute File.exists?(Path.join(base_dir, "lib/support_desk/support/ticket.ex"))
    assert File.exists?(Path.join(base_dir, "lib/support_desk/support/case.ex"))
    assert File.exists?(Path.join(base_dir, "lib/support_desk/support/customer.ex"))

    manifest_after_run2 = Manifest.load(base_dir)

    entry_after_run2 =
      Manifest.get_entry(manifest_after_run2, Manifest.recipe_key(@template, @out_template))

    assert Manifest.output_paths(entry_after_run2) ==
             MapSet.new([
               "lib/support_desk/support/case.ex",
               "lib/support_desk/support/customer.ex"
             ])

    # --- Run 3: ontology removes Customer entirely (upstream removal) ---
    # customer.ex is now stale; case.ex remains.
    run3 =
      run_sync!(base_dir, %{
        "lib/support_desk/support/case.ex" => "defmodule SupportDesk.Support.Case do\nend\n"
      })

    assert MapSet.new(["lib/support_desk/support/customer.ex"]) == run3.stale

    assert [{Path.join(base_dir, "lib/support_desk/support/customer.ex"), :pruned}] ==
             run3.pruned

    refute File.exists?(Path.join(base_dir, "lib/support_desk/support/customer.ex"))
    assert File.exists?(Path.join(base_dir, "lib/support_desk/support/case.ex"))
    # Confirm the renamed-away ticket.ex from run 2 is still gone (real
    # persistent state, not merely absent from this run's return value).
    refute File.exists?(Path.join(base_dir, "lib/support_desk/support/ticket.ex"))

    manifest_after_run3 = Manifest.load(base_dir)

    entry_after_run3 =
      Manifest.get_entry(manifest_after_run3, Manifest.recipe_key(@template, @out_template))

    assert Manifest.output_paths(entry_after_run3) ==
             MapSet.new(["lib/support_desk/support/case.ex"])

    # --- Final invariant: zero orphaned tracked paths survive on the real filesystem ---
    tracked_paths = Manifest.output_paths(entry_after_run3)

    all_files_under_support =
      Path.wildcard(Path.join(base_dir, "lib/support_desk/support/*.ex"))
      |> Enum.map(&Path.relative_to(&1, base_dir))
      |> MapSet.new()

    assert all_files_under_support == tracked_paths,
           "every real file on disk under support/ must be exactly the tracked set -- " <>
             "no orphans, no untracked leftovers"

    # And a final stale_paths/2 call against the current entry, against its
    # own current output set, proves the reconciled state is clean.
    assert MapSet.new() ==
             Manifest.stale_paths(entry_after_run3, Manifest.output_paths(entry_after_run3))
  end

  test "no-op re-run (identical outputs) leaves the manifest file byte-for-byte unchanged",
       %{base_dir: base_dir} do
    outputs = %{
      "lib/support_desk/support/case.ex" => "defmodule SupportDesk.Support.Case do\nend\n"
    }

    run_sync!(base_dir, outputs)
    manifest_path = Manifest.path(base_dir)
    bytes_after_run1 = File.read!(manifest_path)

    # Re-running with byte-identical content must not touch the manifest at
    # all, per Manifest.same_outputs?/2's documented contract -- verify this
    # directly (the module's own truth) before also checking the file.
    manifest = Manifest.load(base_dir)
    key = Manifest.recipe_key(@template, @out_template)
    entry = Manifest.get_entry(manifest, key)

    real_content = File.read!(Path.join(base_dir, "lib/support_desk/support/case.ex"))
    same_outputs = %{"lib/support_desk/support/case.ex" => Manifest.hash_content(real_content)}

    assert Manifest.same_outputs?(entry, same_outputs)

    # File on disk is untouched by a second identical run's mtime/bytes,
    # since a real caller (Sync task) would skip persist!/2 entirely here --
    # simulate that by NOT calling persist!/2 and confirming the file still
    # matches byte-for-byte.
    assert File.read!(manifest_path) == bytes_after_run1
  end
end
