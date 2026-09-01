defmodule GgenIgniter.SyncVerify do
  @moduledoc """
  Orchestrates GGEN-1805 (`GgenIgniter.SyncShellout`) and GGEN-1806
  (`GgenIgniter.GateVerify`) into the single pipeline
  `docs/jira/v26.9.1/04-SYNC-SHELLOUT-AND-VERIFY.md` describes: shell out to
  a real `ggen sync run`, and only on a real exit-0 success, run the pack's
  own gate queries against the regenerated ontology.

  `run/3`'s return value lets a caller pattern-match "generated and
  gate-verified" (`{:ok, %{sync: _, gates: _}}`) apart from every other
  outcome -- a sync failure (`GgenIgniter.SyncShellout`'s own error shapes,
  propagated unchanged), an upstream-gating refusal
  (`{:error, :upstream_failed}`), or a gate failure
  (`{:error, {:gate_failed, gate_name}}`).
  """

  @doc """
  `project_dir` is the consumer project `ggen sync run` is shelled out
  against (see `GgenIgniter.SyncShellout.run/2`). `pack_dir` is the pack
  whose `gates/*.rq` are verified post-sync (see `GgenIgniter.GateVerify.run/2`).

  `opts`:

    * `upstream_ok?` -- forwarded to `GgenIgniter.SyncShellout.run/2`.
    * `ontology_path` -- overrides the default `<project_dir>/ontology.ttl`
      (the file `ggen sync run` regenerates against) passed to
      `GgenIgniter.GateVerify.run/2`.
  """
  @spec run(String.t(), String.t(), keyword()) ::
          {:ok, %{sync: String.t(), gates: [{String.t(), :pass}]}}
          | {:error, {integer() | :enoent, String.t()}}
          | {:error, :upstream_failed}
          | {:error, {:gate_failed, String.t()}}
  def run(project_dir, pack_dir, opts \\ [])
      when is_binary(project_dir) and is_binary(pack_dir) and is_list(opts) do
    ontology_path = Keyword.get(opts, :ontology_path, Path.join(project_dir, "ontology.ttl"))
    shellout_opts = Keyword.take(opts, [:upstream_ok?])

    with {:ok, sync_output} <- GgenIgniter.SyncShellout.run(project_dir, shellout_opts),
         {:ok, gate_results} <- GgenIgniter.GateVerify.run(pack_dir, ontology_path) do
      {:ok, %{sync: sync_output, gates: gate_results}}
    end
  end
end
