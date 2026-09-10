defmodule GgenIgniter.SyncConcurrentProcessTest do
  @moduledoc """
  Real two-OS-PROCESS concurrency test for `manifest.json` (see status.md's
  "Concurrent-writer safety on `manifest.json`" row). Unlike
  `test/ggen_igniter_lock_contention_test.exs` (which races two `Task.async/1`
  processes -- same BEAM node -- directly against `GgenIgniter.Lock.acquire/2`),
  this spawns two genuinely SEPARATE OS processes, each a real
  `mix ggen_igniter.sync` subprocess (`System.cmd/3`, no mocks), racing against
  the SAME `--manifest-dir` at nearly the same time. This is the actual
  real-world scenario `GgenIgniter.Lock`'s moduledoc describes ("two separate
  `mix` invocations ... not two processes in the same VM").

  Both subprocesses use the SAME `--template` but a DIFFERENT `--out` path, so
  each gets its own distinct manifest recipe key (`recipe_key/2` is keyed by
  `(template, raw out_template)` -- see `lib/ggen_igniter/manifest.ex`'s
  moduledoc) -- this is what lets the test assert BOTH recipes' entries
  genuinely survived the race, not just that neither run crashed.

  Real assertions on real resulting state: both subprocesses exit 0, both
  output files exist and parse as valid Elixir, `manifest.json` itself is
  valid JSON (never corrupted -- the failure mode a broken lock would produce
  is two processes both winning `File.open/2`'s `:exclusive` mode and
  interleaving writes to the same manifest file), and both recipe keys are
  genuinely present in it.
  """

  use ExUnit.Case, async: false

  @moduletag :integration

  @tag :tmp_dir
  test "two concurrent `mix ggen_igniter.sync` OS processes against one --manifest-dir serialize instead of corrupting manifest.json",
       %{tmp_dir: tmp_dir} do
    manifest_dir = tmp_dir
    out_a = Path.join(tmp_dir, "resource_a.ex")
    out_b = Path.join(tmp_dir, "resource_b.ex")

    common_args = [
      "ggen_igniter.sync",
      "--engine",
      "sparql",
      "--ontology",
      "test/fixtures/audit_trail_ontology.ttl",
      "--query",
      "spec=test/fixtures/spec.rq",
      "--query",
      "sections=test/fixtures/sections.rq",
      "--query",
      "entities=test/fixtures/entities.rq",
      "--query",
      "fields=test/fixtures/fields.rq",
      "--template",
      "test/fixtures/extension.ex.eex",
      "--manifest-dir",
      manifest_dir,
      "--verify-cwd",
      File.cwd!()
    ]

    repo_root = File.cwd!()

    # Two genuinely separate OS processes, launched as close together as
    # `Task.async/1` scheduling allows, both racing `GgenIgniter.Lock.acquire/2`
    # (via `run_sync/2`) against the SAME `manifest_dir` lock key.
    task_a =
      Task.async(fn ->
        System.cmd("mix", common_args ++ ["--out", out_a], cd: repo_root, stderr_to_stdout: true)
      end)

    task_b =
      Task.async(fn ->
        System.cmd("mix", common_args ++ ["--out", out_b], cd: repo_root, stderr_to_stdout: true)
      end)

    {output_a, exit_a} = Task.await(task_a, 60_000)
    {output_b, exit_b} = Task.await(task_b, 60_000)

    assert exit_a == 0, "subprocess A failed:\n#{output_a}"
    assert exit_b == 0, "subprocess B failed:\n#{output_b}"

    # Real resulting state on disk: both outputs genuinely written and valid.
    assert File.exists?(out_a)
    assert File.exists?(out_b)
    assert {:defmodule, _, _} = Code.string_to_quoted!(File.read!(out_a))
    assert {:defmodule, _, _} = Code.string_to_quoted!(File.read!(out_b))

    # The real manifest.json is valid, uncorrupted JSON -- a broken lock would
    # let both processes' File.open/2 :exclusive both win, racing the
    # temp-file-then-rename in GgenIgniter.Manifest.persist!/2 and (in the
    # worst case) truncating/interleaving the file into invalid JSON.
    manifest_path = GgenIgniter.Manifest.path(manifest_dir)
    assert File.exists?(manifest_path)

    manifest_content = File.read!(manifest_path)
    assert {:ok, decoded} = Jason.decode(manifest_content)
    assert %{"entries" => entries} = decoded

    recipe_keys = Map.keys(entries)

    assert Enum.any?(recipe_keys, &String.ends_with?(&1, "=>#{out_a}")),
           "expected a manifest recipe entry for #{out_a}, got keys: #{inspect(recipe_keys)}"

    assert Enum.any?(recipe_keys, &String.ends_with?(&1, "=>#{out_b}")),
           "expected a manifest recipe entry for #{out_b}, got keys: #{inspect(recipe_keys)}"
  end
end
