defmodule GgenIgniter.SemanticJira.TargetPackManufactureTest do
  @moduledoc """
  Chicago-style manufacture witness for lane D4's `sj:targetPack` paydown:
  `templates/target_pack.ex.eex` renders `GgenIgniter.SemanticJira.TargetPack`
  from the pack's kernel-contract facts (gate `065_target_pack_contract.rq`
  over `sj:KernelContract`), and the rendered bytes ARE the checked-in
  `lib/ggen_igniter/semantic_jira/target_pack.ex` -- the retirement falsifier
  of HANDWRITTEN.md row 48 ("rows leave when the rendered file passes the
  existing tests unchanged").

  Real collaborators, no test doubles: the real canonical ontology file, the
  real SPARQL engine, the real `ReconcileReactor` render/admit/actuate
  pipeline (the same actuation path `mix ggen_igniter.sync` dispatches), real
  tmp mix projects as `--verify-cwd`, and real byte comparisons of the actuated
  output against the checked-in module on disk.
  """

  # async: false -- real ReconcileReactor runs (the compensation-telemetry ETS
  # table is global; same reason as
  # ggen_igniter_semantic_jira_target_pack_test.exs).
  use ExUnit.Case, async: false

  @moduletag :integration
  @moduletag timeout: 900_000

  @lib_path "lib/ggen_igniter/semantic_jira/target_pack.ex"
  @ontology_path "priv/ggen/semantic-jira-pack/ontology.ttl"
  @gate_path "priv/ggen/semantic-jira-pack/gates/065_target_pack_contract.rq"

  describe "gate 065_target_pack_contract.rq (canonical graph)" do
    test "returns exactly the TargetPack kernel-contract row" do
      graph = GgenIgniter.Ontology.load!(@ontology_path)
      rows = GgenIgniter.Query.run(graph, File.read!(@gate_path))

      assert rows == [
               %{
                 "module" => "GgenIgniter.SemanticJira.TargetPack",
                 "refusal_prefix" => "REFUSED:TARGET_PACK_UNKNOWN"
               }
             ]
    end
  end

  describe "target_pack.ex.eex manufacture byte-identity" do
    test "two ReconcileReactor renders are byte-stable and byte-identical to the checked-in module" do
      render1 = render_once!("d4_mfg_run1")
      render2 = render_once!("d4_mfg_run2")

      assert render1 == render2, "the render is not byte-stable across two runs"

      assert render1 == File.read!(@lib_path),
             "the rendered module is not byte-identical to #{inspect(@lib_path)} -- " <>
               "HANDWRITTEN.md row 48 must NOT retire until it is"
    end
  end

  # -- helpers -------------------------------------------------------------------

  # One real ReconcileReactor render of `templates/target_pack.ex.eex` from the
  # canonical pack (the exact actuation path `mix ggen_igniter.sync --pack
  # semantic-jira-pack:target_pack` dispatches), into a real tmp project.
  defp render_once!(tag) do
    project_dir = new_mix_project!(tag)

    opts = [
      pack: "semantic-jira-pack",
      pack_template_stem: "target_pack",
      out: Path.join(project_dir, "target_pack.ex"),
      manifest_dir: project_dir,
      engine: "sparql",
      verify_cwd: project_dir
    ]

    assert {:ok, receipt} = GgenIgniter.Reactors.ReconcileReactor.run(opts)
    assert receipt.standing == :alive
    assert receipt.pack_name == "semantic-jira-pack"

    Path.join(project_dir, "target_pack.ex") |> File.read!()
  end

  # Mirrors ggen_igniter_semantic_jira_target_pack_test.exs' own
  # `new_mix_project!/0` fixture: a real throwaway Mix project on disk,
  # resolved to its symlink-free real path (RealDir: the macOS TMPDIR
  # symlink trips the actuation layer's canonicalized root check).
  defp new_mix_project!(tag) do
    dir =
      Path.join(
        System.tmp_dir!(),
        "ggen_igniter_tp_mfg_#{tag}_#{System.unique_integer([:positive])}"
      )

    File.rm_rf!(dir)
    File.mkdir_p!(dir)
    dir = RealDir.real_dir!(dir)

    File.write!(Path.join(dir, "mix.exs"), """
    defmodule #{Macro.camelize("tp_mfg_#{tag}")}.MixProject do
      use Mix.Project

      def project do
        [app: :tp_mfg_#{tag}, version: "0.1.0", elixir: "~> 1.14", deps: []]
      end
    end
    """)

    on_exit(fn -> File.rm_rf!(dir) end)
    dir
  end
end
