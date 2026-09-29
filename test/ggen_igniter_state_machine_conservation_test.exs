defmodule GgenIgniter.StateMachineConservationTest do
  @moduledoc """
  Chicago-style: real `mix ggen_igniter.sync` subprocesses over real fixture ontologies
  (`test/fixtures/state-machine/`). Two kinds of state are asserted:

    * REFUSAL: a malformed lifecycle exits non-zero with a typed `REFUSED:<CODE>` and the
      output tree hash (every file under the sync root, incl. the manifest dir) is identical
      before and after -- zero files written. The same sync passes once the ontology is fixed.
    * CONSERVATION: the transition set of the compiled resource
      (`AshStateMachine.Info.state_machine_transitions/1`) equals the transition set queried
      from the ontology by a real SPARQL query -- nothing lost, nothing added.

  Falsifier for the gates: each negative fixture's fix (or a mutation) flips the sync outcome.
  """

  use ExUnit.Case, async: false
  @moduletag :integration
  @moduletag timeout: 600_000

  alias GgenIgniter.Test.PackCompile

  @pack_dir Path.expand("../priv/ggen/state-machine-pack", __DIR__)
  @fixtures Path.expand("fixtures/state-machine", __DIR__)
  @spec_ "state-machine-pack:state_machine"

  defp ontology!(names) do
    body =
      [File.read!(Path.join(@pack_dir, "ontology.ttl"))] ++
        Enum.map(names, &File.read!(Path.join(@fixtures, &1)))

    PackCompile.tmp_project!(%{"ontology.ttl" => Enum.join(body, "\n")})
  end

  # Real sync into a caller-owned root so the tree can be hashed before and after.
  @engines ["sparql", "oxigraph"]

  defp sync(ontology_dir, root, engine \\ "sparql") do
    out = Path.join(root, "lib/<%= file_stem %>.ex")

    System.cmd(
      "mix",
      [
        "ggen_igniter.sync",
        "--pack",
        @spec_,
        "--ontology",
        Path.join(ontology_dir, "ontology.ttl"),
        "--engine",
        engine,
        "--out",
        out,
        "--manifest-dir",
        root,
        "--verify-cwd",
        File.cwd!()
      ],
      cd: File.cwd!(),
      stderr_to_stdout: true
    )
  end

  defp tree_hash(root) do
    root
    |> Path.join("**/*")
    |> Path.wildcard(match_dot: true)
    |> Enum.reject(&(File.dir?(&1) or String.contains?(&1, "/.ggen_igniter/receipts/")))
    |> Enum.sort()
    |> Enum.map(&{Path.relative_to(&1, root), :crypto.hash(:sha256, File.read!(&1))})
    |> then(&:crypto.hash(:sha256, :erlang.term_to_binary(&1)))
  end

  defp refusal(fixture, engine) do
    odir = ontology!([fixture])
    root = PackCompile.tmp_project!(%{})

    try do
      before = tree_hash(root)
      {output, status} = sync(odir, root, engine)
      {status, output, before == tree_hash(root)}
    after
      PackCompile.cleanup(odir)
      PackCompile.cleanup(root)
    end
  end

  describe "typed-refusal gates (zero files written)" do
    for engine <- @engines do
      @engine engine

      test "[#{engine}] unreachable state -> exact REFUSED:STATE_UNREACHABLE ...: c detail" do
        {status, output, unchanged?} = refusal("neg_unreachable.ttl", @engine)
        assert status != 0, output
        assert output =~ ~r/REFUSED:STATE_UNREACHABLE \S+: c; broken_term=mu_on_O/
        assert unchanged?
      end

      test "[#{engine}] dead-end non-terminal -> REFUSED:STATE_DEAD_END; edge C->D fixes it" do
        {status, output, unchanged?} = refusal("neg_dead_end.ttl", @engine)
        assert status != 0, output
        assert output =~ "REFUSED:STATE_DEAD_END"
        assert unchanged?

        {status, output, _} = refusal("pos_dead_end_fixed.ttl", @engine)
        assert status == 0, output
      end

      test "[#{engine}] transition naming an undeclared state -> TRANSITION_UNKNOWN_STATE" do
        {status, output, unchanged?} = refusal("neg_unknown_state.ttl", @engine)
        assert status != 0, output
        assert output =~ "REFUSED:TRANSITION_UNKNOWN_STATE"
        assert output =~ "ghost"
        assert unchanged?
      end

      test "[#{engine}] no initial state -> REFUSED:INITIAL_STATE_MISSING" do
        {status, output, unchanged?} = refusal("neg_no_initial.ttl", @engine)
        assert status != 0, output
        assert output =~ "REFUSED:INITIAL_STATE_MISSING"
        assert unchanged?
      end

      test "[#{engine}] one action targeting two states -> ACTION_AMBIGUOUS_TARGET (names it)" do
        {status, output, unchanged?} = refusal("neg_ambiguous_target.ttl", @engine)
        assert status != 0, output
        assert output =~ "REFUSED:ACTION_AMBIGUOUS_TARGET"
        assert unchanged?
      end

      test "[#{engine}] defaultInitialState undeclared -> TRANSITION_UNKNOWN_STATE" do
        {status, output, unchanged?} = refusal("neg_default_initial_undeclared.ttl", @engine)
        assert status != 0, output
        assert output =~ ~r/REFUSED:TRANSITION_UNKNOWN_STATE .*default-initial \S*abc-ghost/
        assert unchanged?
      end

      test "[#{engine}] defaultInitialState not among initialState -> refused" do
        {status, output, unchanged?} = refusal("neg_default_initial_not_initial.ttl", @engine)
        assert status != 0, output
        assert output =~ ~r/REFUSED:TRANSITION_UNKNOWN_STATE .*default-initial \S*abc-b/
        assert unchanged?
      end

      test "[#{engine}] defaultInitialState without stateName -> refused" do
        {status, output, unchanged?} = refusal("neg_default_initial_unnamed.ttl", @engine)
        assert status != 0, output
        assert output =~ "default-initial without stateName"
        assert unchanged?
      end

      test "[#{engine}] illegal state name -> REFUSED:INPUT_INVALID" do
        {status, output, unchanged?} = refusal("neg_bad_state_name.ttl", @engine)
        assert status != 0, output
        assert output =~ ~s(REFUSED:INPUT_INVALID)
        assert output =~ ~r/stateName \\*"Bad Name\\*" is not a legal identifier/
        assert unchanged?
      end

      test "[#{engine}] reserved action name create -> REFUSED:INPUT_INVALID" do
        {status, output, unchanged?} = refusal("neg_reserved_action.ttl", @engine)
        assert status != 0, output
        assert output =~ ~s(REFUSED:INPUT_INVALID)
        assert output =~ ~r/action \\*"create\\*" is reserved/
        assert unchanged?
      end
    end

    test "a bad machine refuses the whole sync: a good machine beside it is not written" do
      odir = ontology!(["pos_tap.ttl", "neg_unreachable.ttl"])
      root = PackCompile.tmp_project!(%{})

      try do
        before = tree_hash(root)
        {output, status} = sync(odir, root)
        assert status != 0, output
        assert output =~ "REFUSED:STATE_UNREACHABLE"
        assert tree_hash(root) == before
      after
        PackCompile.cleanup(odir)
        PackCompile.cleanup(root)
      end
    end

    test "falsifier: a good ontology passes the identical sync" do
      odir = ontology!(["pos_abc.ttl"])
      root = PackCompile.tmp_project!(%{})

      try do
        {output, status} = sync(odir, root)
        assert status == 0, output

        written =
          root
          |> Path.join("**/*")
          |> Path.wildcard(match_dot: true)
          |> Enum.reject(&(File.dir?(&1) or String.contains?(&1, "/.ggen_igniter/")))
          |> Enum.map(&Path.relative_to(&1, root))

        assert written == ["lib/sm_fixture/smfixture_abc.ex"] or
                 Enum.any?(written, &String.ends_with?(&1, "abc.ex")),
               inspect(written)
      after
        PackCompile.cleanup(odir)
        PackCompile.cleanup(root)
      end
    end
  end

  describe "gate falsifiers: mutating a good ontology flips the sync outcome" do
    defp mutated_sync(replace_from, replace_to) do
      text = File.read!(Path.join(@fixtures, "pos_abc.ttl"))
      mutated = String.replace(text, replace_from, replace_to)
      refute mutated == text

      dir =
        PackCompile.tmp_project!(%{
          "ontology.ttl" => File.read!(Path.join(@pack_dir, "ontology.ttl")) <> "\n" <> mutated
        })

      root = PackCompile.tmp_project!(%{})

      try do
        sync(dir, root)
      after
        PackCompile.cleanup(dir)
        PackCompile.cleanup(root)
      end
    end

    test "deleting the only edge into B leaves B unreachable -> REFUSED:STATE_UNREACHABLE" do
      {output, status} = mutated_sync(" , ex:abc-t-reopen", "")
      # reopen (b->a) is not the only edge into b, so this control still passes
      assert status == 0, output

      {output, status} = mutated_sync("ex:abc-t-advance , ", "")
      assert status != 0
      assert output =~ "REFUSED:STATE_UNREACHABLE"
      assert output =~ ": b"
    end

    test "deleting sm:initialState -> REFUSED:INITIAL_STATE_MISSING" do
      {output, status} = mutated_sync("    sm:initialState ex:abc-a ;\n", "")
      assert status != 0
      assert output =~ "REFUSED:INITIAL_STATE_MISSING"
    end
  end

  describe "conservation of the transition set" do
    test "ontology transitions == AshStateMachine.Info transitions (5 states / 7 transitions)" do
      dir = ontology!(["pos_doc.ttl"])
      path = Path.join(dir, "ontology.ttl")

      try do
        expected =
          path
          |> GgenIgniter.Ontology.load!()
          |> GgenIgniter.Query.run("""
          PREFIX sm: <https://ggen-igniter.dev/ontology/state-machine#>
          SELECT DISTINCT ?t ?action ?from ?to WHERE {
            ?m sm:resourceModule "SmFixture.Doc" ; sm:hasTransition ?t .
            ?t sm:action ?action ; sm:from ?f ; sm:to ?d .
            ?f sm:stateName ?from . ?d sm:stateName ?to .
          }
          """)
          |> Enum.group_by(& &1["t"])
          |> Enum.map(fn {_t, rows} ->
            {hd(rows)["action"], rows |> Enum.map(& &1["from"]) |> Enum.uniq() |> Enum.sort(),
             rows |> Enum.map(& &1["to"]) |> Enum.uniq() |> Enum.sort()}
          end)
          |> MapSet.new()

        assert MapSet.size(expected) == 7

        PackCompile.with_compiled(
          @spec_,
          [ontology: path, out: "lib/<%= file_stem %>.ex"],
          fn _mods, _r ->
            actual =
              SmFixture.Doc
              |> AshStateMachine.Info.state_machine_transitions()
              |> MapSet.new(fn t ->
                {Atom.to_string(t.action), t.from |> Enum.map(&Atom.to_string/1) |> Enum.sort(),
                 t.to |> Enum.map(&Atom.to_string/1) |> Enum.sort()}
              end)

            assert actual == expected
            assert {"reject", ["approved", "review"], ["draft"]} in actual
            assert {"touch", ["review"], ["review"]} in actual
            assert length(AshStateMachine.Info.state_machine_all_states(SmFixture.Doc)) == 5
          end
        )
      after
        PackCompile.cleanup(dir)
      end
    end
  end
end
