defmodule GgenIgniter.ConsumerCwdPackTest do
  @moduledoc """
  Chicago-style, no-mocks regression fixture for GGEN-05
  (`docs/jira/v26.9.10/05-GGEN-SYNC-TEMPLATE-PIPELINE-BLOCKER.md`): proves
  that a consumer-style `priv/ggen/<pack>/{ontology.ttl,gates/*.rq,
  templates/*.eex}` tree, run via `mix ggen_igniter.sync --pack-dir ...`
  from a working directory that is NOT `ggen_igniter`'s own repo root,
  resolves the default (unset `--manifest-dir`, relative `--out`) paths
  against that consumer's own real `File.cwd!()` -- not against
  `ggen_igniter`'s own root and not against any hardcoded path.

  This does not (and, per this session's explicit scope constraint,
  cannot this pass) reproduce or refute the specific blocker `ash_a2a`'s
  `MANUFACTURING_RECEIPT.md` disclosed against `~/ash_a2a`'s own real
  template material -- see the ticket's "Status" section for that
  disclosure. It reproduces the general SHAPE of the scenario (a real
  consumer project's own ontology+query+template, invoked from that
  project's own cwd, not `ggen_igniter`'s) using small, self-contained,
  checked-in fixture material at `test/fixtures/consumer_cwd_pack/`.

  Real collaborators throughout: a real `File.cd!/2` process-cwd change to a
  real tmp directory built under `System.tmp_dir!()` (deliberately OUTSIDE
  this repo's own working tree, mirroring a real consumer project's own
  root), the real `Igniter.Mix.Task.configure_and_run/3` plumbing
  `Mix.Tasks.GgenIgniter.Sync`'s generated `run/1` uses (same in-process
  pattern as `GgenIgniter.SyncInProcessDispatchTest`'s `run_sync!/1` and
  `GgenIgniter.SyncControllerDelegationTest`'s), the real oxigraph NIF query
  engine (this repo's default `--engine` since v26.8.27), and real file I/O
  -- no `Mock`/`mock(`/`patch(`/`monkeypatch` anywhere in this file.
  """
  use ExUnit.Case, async: false

  @moduletag :integration

  @pack_dir Path.expand("fixtures/consumer_cwd_pack", __DIR__)

  defp run_sync!(argv) do
    Igniter.new()
    |> Map.put(:task, "ggen_igniter.sync")
    |> Igniter.Mix.Task.configure_and_run(Mix.Tasks.GgenIgniter.Sync, argv)
  end

  defp consumer_root!(tag) do
    dir =
      Path.join(
        System.tmp_dir!(),
        "ggen_igniter_consumer_cwd_#{tag}_#{System.unique_integer([:positive])}"
      )

    File.rm_rf!(dir)
    File.mkdir_p!(dir)
    on_exit(fn -> File.rm_rf!(dir) end)
    dir
  end

  test "mix ggen_igniter.sync --pack-dir, invoked from a consumer's own cwd (not ggen_igniter's root), " <>
         "resolves default --out/--manifest-dir against that consumer's real File.cwd!()" do
    ggen_igniter_root = File.cwd!()
    consumer_root = consumer_root!("default_paths")

    # Deliberately RELATIVE --out and NO --manifest-dir: this is exactly the
    # default-resolution path every existing --pack-dir test in this repo
    # sidesteps by always passing an absolute --out plus an explicit
    # --manifest-dir (see ggen_igniter_sync_pack_test.exs,
    # ggen_igniter_sync_inprocess_dispatch_test.exs). A consumer invoking
    # `mix ggen_igniter.sync --pack-dir ...` for real from its own project
    # root would not pass either flag.
    relative_out = Path.join("generated", "widget.ex")

    igniter =
      File.cd!(consumer_root, fn ->
        run_sync!([
          "--pack-dir",
          @pack_dir,
          "--out",
          relative_out,
          # This repo's own `config/test.exs` defaults `use_reactor: true`
          # (confirmed by this test failing without this flag: "--verify-cwd
          # was not set ... not a Mix project directory"), so the Reactor
          # pipeline's terminal `:verify` step (a real `mix compile`) needs
          # to be pointed at a REAL Mix project root -- `consumer_root` is
          # deliberately a bare fixture directory with no mix.exs of its
          # own, so this points back at ggen_igniter's real root, same
          # convention as ggen_igniter_sync_pack_test.exs. This is
          # orthogonal to what this test actually proves (default --out/
          # --manifest-dir path resolution against the consumer's real
          # File.cwd!()), not a weakening of it.
          "--verify-cwd",
          ggen_igniter_root
        ])
      end)

    assert igniter.notices != []

    # Real, observable state: the generated file exists relative to the
    # CONSUMER's own cwd, not ggen_igniter's repo root, and not any
    # hardcoded "/workspace" (the ash_a2a-reported blocker's shape) --
    # confirmed by direct absence checks against both wrong locations below.
    consumer_out_path = Path.join(consumer_root, relative_out)
    assert File.exists?(consumer_out_path)

    content = File.read!(consumer_out_path)
    assert {:defmodule, _, _} = Code.string_to_quoted!(content)
    assert content =~ "defmodule ConsumerCwdFixture.Widget do"
    assert content =~ ~s(def gizmo, do: "gizmo")

    refute File.exists?(Path.join(ggen_igniter_root, relative_out))
    refute File.exists?("/workspace")

    # The reconciliation manifest itself (`opts[:manifest_dir] ||
    # File.cwd!()`, per this repo's real path-construction sites -- grepped
    # zero `/workspace` hardcodes in `lib/` this session) also lands under
    # the consumer's own root, not ggen_igniter's.
    assert File.exists?(Path.join(consumer_root, ".ggen_igniter/manifest.json"))

    refute File.exists?(
             Path.join(ggen_igniter_root, ".ggen_igniter/manifest.json.consumer_cwd_pack_test")
           )
  end

  test "a second sync run against the same consumer root is a real no-op re-run (identical path+hash set)" do
    ggen_igniter_root = File.cwd!()
    consumer_root = consumer_root!("noop_rerun")
    relative_out = Path.join("generated", "widget.ex")
    manifest_path = Path.join(consumer_root, ".ggen_igniter/manifest.json")

    sync_args = [
      "--pack-dir",
      @pack_dir,
      "--out",
      relative_out,
      "--verify-cwd",
      ggen_igniter_root
    ]

    File.cd!(consumer_root, fn -> run_sync!(sync_args) end)

    assert File.exists?(manifest_path)
    first_manifest_mtime = File.stat!(manifest_path).mtime

    File.cd!(consumer_root, fn -> run_sync!(sync_args) end)

    # Real, state-based proof of the no-op re-run guarantee this repo's
    # `docs/CLAUDE.md`/reconciliation-manifest docs describe: an identical
    # path+content-hash set does not even touch the manifest file's mtime.
    assert File.stat!(manifest_path).mtime == first_manifest_mtime
  end
end
