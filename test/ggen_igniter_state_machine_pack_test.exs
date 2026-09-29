defmodule GgenIgniter.StateMachinePackTest do
  @moduledoc """
  Chicago-style: a real `mix ggen_igniter.sync` subprocess renders
  `priv/ggen/state-machine-pack` from RDF lifecycle facts (`test/fixtures/state-machine/`),
  the real compiler builds the output against the real ash + ash_state_machine deps, and
  the assertions are on final STATE: `AshStateMachine.Info` introspection of the compiled
  module, real Ash create/update calls against the ETS data layer (stored state re-read
  from the data layer), and rendered file bytes. No doubles anywhere.

  Falsifier: the ontology fact `ex:abc-t-finish` (B -> C) is deleted; the compiled machine
  must lose the transition and the record in B must no longer be able to reach C.
  """

  use ExUnit.Case, async: false
  # async: false -- compiles same-named modules into the global code server.
  @moduletag :integration
  @moduletag timeout: 600_000

  alias GgenIgniter.Test.PackCompile

  @pack_dir Path.expand("../priv/ggen/state-machine-pack", __DIR__)
  @fixtures Path.expand("fixtures/state-machine", __DIR__)
  @spec_ "state-machine-pack:state_machine"
  # `--out` is an EEx path template rendered per for_each row (one file per machine).
  @out "lib/<%= file_stem %>.ex"

  def ontology!(names, transform \\ & &1) do
    body =
      [File.read!(Path.join(@pack_dir, "ontology.ttl"))] ++
        Enum.map(names, &(@fixtures |> Path.join(&1) |> File.read!() |> transform.()))

    dir = PackCompile.tmp_project!(%{"ontology.ttl" => Enum.join(body, "\n")})
    {dir, Path.join(dir, "ontology.ttl")}
  end

  def with_machine(names, transform \\ & &1, fun) do
    {dir, path} = ontology!(names, transform)

    try do
      PackCompile.with_compiled(@spec_, [ontology: path, out: @out], fun)
    after
      PackCompile.cleanup(dir)
    end
  end

  defp transitions(mod) do
    mod
    |> AshStateMachine.Info.state_machine_transitions()
    |> MapSet.new(&{Atom.to_string(&1.action), Enum.sort(&1.from), Enum.sort(&1.to)})
  end

  defp errors_of({:error, %{errors: errors}}), do: errors

  defp stored_state(mod, id), do: mod |> Ash.get!(id) |> Map.fetch!(:state)

  describe "A -> B -> C lifecycle" do
    test "create in A; B->C refused from A with state unchanged; A->B then B->C reach C" do
      with_machine(["pos_abc.ttl"], fn [_ | _], _rendered ->
        mod = SmFixture.Abc
        rec = mod |> Ash.Changeset.for_create(:create, %{}) |> Ash.create!()
        assert rec.state == :a

        refused = rec |> Ash.Changeset.for_update(:finish, %{}) |> Ash.update()

        assert Enum.any?(
                 errors_of(refused),
                 &match?(
                   %AshStateMachine.Errors.NoMatchingTransition{old_state: :a, target: :c},
                   &1
                 )
               )

        assert stored_state(mod, rec.id) == :a

        b = rec |> Ash.Changeset.for_update(:advance, %{}) |> Ash.update!()
        assert b.state == :b
        assert stored_state(mod, rec.id) == :b

        c = b |> Ash.Changeset.for_update(:finish, %{}) |> Ash.update!()
        assert c.state == :c
        assert stored_state(mod, rec.id) == :c

        assert AshStateMachine.Info.state_machine_initial_states!(mod) == [:a]
        assert AshStateMachine.Info.state_machine_default_initial_state!(mod) == :a
      end)
    end

    test "falsifier: deleting the B->C fact removes the transition and B can no longer reach C" do
      base =
        with_machine(["pos_abc.ttl"], fn _mods, _r ->
          rec = SmFixture.Abc |> Ash.Changeset.for_create(:create, %{}) |> Ash.create!()
          b = rec |> Ash.Changeset.for_update(:advance, %{}) |> Ash.update!()
          {transitions(SmFixture.Abc), Enum.sort(AshStateMachine.possible_next_states(b))}
        end)

      {base_transitions, base_next} = base
      assert {"finish", [:b], [:c]} in base_transitions
      assert base_next == [:a, :c]

      mutate = fn text ->
        mutated = String.replace(text, ", ex:abc-t-finish", "")
        refute mutated == text
        mutated
      end

      with_machine(["pos_abc.ttl"], mutate, fn _mods, _r ->
        mod = SmFixture.Abc
        refute Enum.any?(transitions(mod), &match?({"finish", _, _}, &1))
        rec = mod |> Ash.Changeset.for_create(:create, %{}) |> Ash.create!()
        b = rec |> Ash.Changeset.for_update(:advance, %{}) |> Ash.update!()
        assert Enum.sort(AshStateMachine.possible_next_states(b)) == [:a]

        # the action itself is gone: no update action can carry B to C
        assert_raise ArgumentError, ~r/No such update action.*:finish/s, fn ->
          Ash.Changeset.for_update(b, :finish, %{})
        end

        assert stored_state(mod, rec.id) == :b
      end)
    end
  end

  describe "rendering" do
    test "the rendered file carries the AshStateMachine block from ontology facts" do
      {dir, path} = ontology!(["pos_abc.ttl"])

      try do
        rendered = PackCompile.render!(@spec_, ontology: path, out: @out)
        [file] = Enum.filter(rendered.files, &String.ends_with?(&1, ".ex"))
        source = File.read!(file)
        assert source =~ "extensions: [AshStateMachine]"
        assert source =~ "initial_states([:a])"
        assert source =~ "default_initial_state(:a)"
        assert source =~ "transition(:advance, from: [:a], to: :b)"
        assert source =~ "transition(:finish, from: [:b], to: :c)"
        PackCompile.cleanup(rendered.out_dir)
      after
        PackCompile.cleanup(dir)
      end
    end

    test "idempotence: two syncs of the same ontology are byte-identical" do
      {dir, path} = ontology!(["pos_doc.ttl", "pos_tap.ttl"])

      try do
        snapshot = fn ->
          r = PackCompile.render!(@spec_, ontology: path, out: @out)

          result =
            Map.new(r.files, fn f -> {Path.relative_to(f, r.out_dir), File.read!(f)} end)

          PackCompile.cleanup(r.out_dir)
          result
        end

        first = snapshot.()
        second = snapshot.()
        assert map_size(first) == 2
        assert first == second
      after
        PackCompile.cleanup(dir)
      end
    end
  end

  describe "multi-target" do
    test "two state machines in one ontology render and behave independently" do
      with_machine(["pos_doc.ttl", "pos_tap.ttl"], fn mods, rendered ->
        assert Enum.count(rendered.files, &String.ends_with?(&1, ".ex")) == 2
        assert SmFixture.Doc in mods and SmFixture.Tap in mods

        assert AshStateMachine.Info.state_machine_state_attribute!(SmFixture.Doc) == :state
        assert AshStateMachine.Info.state_machine_state_attribute!(SmFixture.Tap) == :phase
        refute {"open", [:off], [:on]} in transitions(SmFixture.Doc)
        assert {"open", [:off], [:on]} in transitions(SmFixture.Tap)
        assert {"submit", [:draft], [:review]} in transitions(SmFixture.Doc)

        tap = SmFixture.Tap |> Ash.Changeset.for_create(:create, %{}) |> Ash.create!()
        assert tap.phase == :off
        doc = SmFixture.Doc |> Ash.Changeset.for_create(:create, %{}) |> Ash.create!()
        assert doc.state == :draft

        on = tap |> Ash.Changeset.for_update(:open, %{}) |> Ash.update!()
        assert on.phase == :on
        assert Ash.get!(SmFixture.Doc, doc.id).state == :draft
        assert Ash.get!(SmFixture.Tap, tap.id).phase == :on
      end)
    end
  end

  describe "consumer-named shared domain" do
    test "domain template lists both resources; both machines run under it" do
      {dir, path} = ontology!(["pos_shared_domain.ttl"])

      try do
        res = PackCompile.render!(@spec_, ontology: path, out: @out)

        dom =
          PackCompile.render!("state-machine-pack:domain",
            ontology: path,
            out: "lib/<%= file_stem %>.ex"
          )

        files = for f <- res.files ++ dom.files, String.ends_with?(f, ".ex"), do: f
        assert length(files) == 3
        mods = PackCompile.compile!(files)

        try do
          assert SmFixture.Shared in mods

          assert Enum.sort(Ash.Domain.Info.resources(SmFixture.Shared)) ==
                   [SmFixture.SharedA, SmFixture.SharedB]

          a = SmFixture.SharedA |> Ash.Changeset.for_create(:create, %{}) |> Ash.create!()
          assert (a |> Ash.Changeset.for_update(:go, %{}) |> Ash.update!()).state == :y
          b = SmFixture.SharedB |> Ash.Changeset.for_create(:create, %{}) |> Ash.create!()
          assert (b |> Ash.Changeset.for_update(:advance, %{}) |> Ash.update!()).state == :q
        after
          PackCompile.purge(mods)
        end
      after
        PackCompile.cleanup(dir)
      end
    end
  end
end
