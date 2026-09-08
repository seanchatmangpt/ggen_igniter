defmodule GgenIgniter.AshTaskCoverageTest do
  @moduledoc """
  Coverage gate over the generator capability envelope in
  `test/fixtures/ash_manufacture_pack/ontology.ttl`.

  The property under test is CLOSURE, in both directions, between two real
  surfaces:

    * the set of `Igniter.Mix.Task` modules that actually ship in the resolved
      `deps/ash` and `deps/ash_postgres` source trees, and
    * the set of `amp:GeneratorCapability` rows in the pack ontology.

  Closure is the right property because the envelope's whole purpose is to be
  exhaustive: a capability row carries a truthful `amp:standing` and an
  `amp:admitted` flag so the projection can lawfully refuse an inadmissible
  morphism instead of faking it. A task sitting OUTSIDE the envelope is not
  refused -- it is simply invisible, which is the one failure mode a refusal
  vocabulary cannot express. So an Ash release that adds a sixteenth Igniter
  task must break this suite loudly rather than silently widen the untyped
  gap.

  Discovery is done by scanning the real dependency source at runtime
  (`Mix.Project.deps_paths/0` + a grep for `use Igniter.Mix.Task`), never from
  a list written down here. A hardcoded list cannot notice a new task, which
  would make this file assert its own contents rather than the dependency
  surface.

  ## Nothing standing is restated here

  The closed `amp:standing` vocabulary used to be a `MapSet` literal in this
  file -- a fourth copy of a list that also lives in the ontology, in the pack
  README and in `AGENTS.md`, and that two of those four already disagreed
  about. A gate that carries its own copy of the thing it guards cannot detect
  drift in it; it can only drift too. So both vocabularies are now DERIVED at
  runtime:

    * the enforced one, from `amp:standing`'s own `rdfs:comment` through the
      same real Turtle/SPARQL stack the `gates/*.rq` queries run through, and
    * the doctrine one, from the protocol list in `AGENTS.md` that tells an
      agent what to write into a row.

  Their disagreement is then a first-class assertion instead of a latent
  documentation defect. It is currently REAL: `AGENTS.md` instructs agents to
  use a value the ontology does not declare, so a row written exactly as the
  doctrine says fails the membership test below. The message says so, and says
  which of the two files to change.

  ## Version scope

  Every standing is a claim about ONE resolved dependency set: `ash.gen.resource.ex:76`
  names a line in one exact tarball. Two different trees are in play and this
  suite is the only place that sees both -- it discovers tasks from the REPO's
  `deps/` while every `deps/...` citation in the ontology is resolved by the
  pack's checkers against the FIXTURE's. A version skew between them means the
  two halves of this gate read different source. That skew is real today and is
  asserted as an exact set below, so a new one fails loudly.

  The ontology pins its own version scope as `amp:DependencyPin` triples, and
  those are checked here too -- against the lock they describe, and for closure
  over every dependency the ontology cites. That closes the scope on the
  citation side. It does NOT close the skew above: a pin records the FIXTURE's
  version, so a pin can be perfectly correct while the repo this suite scans
  resolves something else. Both checks are needed and neither implies the other.

  Chicago style throughout: the real Turtle file is parsed by the real
  `RDF.Turtle` reader and queried by the real `SPARQL` engine, the real
  dependency source is read off disk, real versions come from the real
  `Application.spec/2` and the real `mix.lock`, and task existence is resolved
  through the real `Mix.Task.get/1`. There are no doubles of any kind.

  Falsifier tests establish that the gate is not vacuous: deleting a row for a
  randomly chosen real task, adding a Faker-named task that no row covers, and
  adding a Faker-named pseudo-capability each must be reported. Without those,
  a gate whose discovery silently returned `[]` would pass.
  """
  use ExUnit.Case, async: true

  @ontology "test/fixtures/ash_manufacture_pack/ontology.ttl"
  @amp "http://seanchatmangpt.github.io/packs/ash-manufacture-pack#"
  @rdfs "http://www.w3.org/2000/01/rdf-schema#"

  # The doctrine file whose protocol tells an agent what to write into a row.
  # It is READ here, never written: this suite reports a disagreement between
  # it and the ontology, it does not resolve one.
  @agents_doc "AGENTS.md"

  # The lock the ontology's `deps/...` citations are resolved against. The
  # ontology names this subject itself; the pack's own checkers read the same
  # file, which is what makes it the citation-resolution surface.
  @fixture_lock "test/fixtures/book_library/mix.lock"

  # The dependencies whose Igniter surface the envelope claims to close over.
  # These are CONTRACT values -- they name the real deps in mix.exs -- so they
  # stay literal; a Faker-generated dep name would test nothing.
  @deps [:ash, :ash_postgres]

  # The ONLY capability rows allowed to name something that is not a resolvable
  # mix task. Both are deliberate modelling devices, not generators:
  #
  #   ash.attach.support_module -- names the DSL entry (`validations do
  #     validate X end`) that NO upstream task can manufacture, so the gap is a
  #     typed refusal instead of a silent orphan.
  #   ash.extend:policies       -- names one unexercised ARGUMENT SHAPE of the
  #     real `ash.extend` task, not a task of its own.
  #
  # Asserted as exact set equality so a third pseudo-row cannot be introduced
  # without editing this list, and so either of these becoming a real upstream
  # task also fails.
  @pseudo_capabilities MapSet.new(["ash.attach.support_module", "ash.extend:policies"])

  # The ontology writes its closed vocabularies as `Closed: A | B | C.` inside
  # the property's own rdfs:comment. This is the ontology's NOTATION, not a
  # value from any vocabulary, which is why it is literal.
  @closed_marker "Closed:"

  # A closed vocabulary in AGENTS.md is a pipe-separated run of backticked
  # all-caps tokens. Matching the RUN rather than bare tokens is what keeps
  # unrelated constants (`CLAUDE_TOOL_INPUT`, `CLAUDE_FILE_PATH`) out of the
  # derived set -- neither appears in an alternation.
  @doc_vocabulary_run ~r/`[A-Z][A-Z_]*`(?:\s*\|\s*`[A-Z][A-Z_]*`)+/

  # Standings the AGENTS.md protocol tells agents to write that the ontology's
  # own closed vocabulary does not declare. This is LIVE drift, not a style
  # difference: a row written exactly as the doctrine instructs is rejected by
  # the membership test below, so the doctrine and its enforcing gate disagree
  # about what a legal standing is.
  #
  # Recorded as exact set equality rather than tolerated, so that resolving it
  # on EITHER side -- declaring the value in amp:standing's rdfs:comment, or
  # dropping it from the AGENTS.md list -- empties this set and forces this
  # constant to be deleted. It names a value that is in neither vocabulary this
  # suite enforces; it is a delta, not a restatement of the vocabulary.
  @documented_vocabulary_drift MapSet.new()

  # The vocabulary encodes liveness in the token itself, so the values meaning
  # "observed to work, at least partially" are derived from the declared set
  # rather than listed again. "ALIVE" is the stem the ontology's own tokens are
  # built from, not a vocabulary value, which is why it is literal.
  #
  # Limitation, stated because the derivation cannot detect it: a future value
  # built on the stem but meaning the opposite would be admitted silently. The
  # guards below bound the derived set, and the failure message prints it, so
  # the coupling is visible rather than assumed.
  @liveness_stem "ALIVE"

  # mix.lock's hex-entry shape. An upstream FORMAT contract -- Mix writes this
  # file -- so the pattern is literal.
  @lock_entry ~r/^\s*"(?<dep>[a-z_0-9]+)":\s*\{:hex,\s*:[a-z_0-9]+,\s*"(?<vsn>[^"]+)"/m

  # Deps whose resolved version differs between this repo (the trees this
  # suite's discovery scans, via `Mix.Project.deps_paths/0`) and the fixture
  # (the trees every `deps/...` citation is resolved against). A skew means the
  # two halves of this gate read DIFFERENT source: closure is computed over one
  # version while the standings were evidenced against another.
  #
  # Exact set equality, so a NEW skew fails loudly and a repaired one forces
  # this list to shrink. The real versions are read at runtime and printed by
  # the failure message; no version is written down in this file.
  @known_version_skew MapSet.new([:igniter])

  setup_all do
    %{
      discovered: discover_igniter_tasks(),
      rows: capability_rows(),
      standings: declared_standings()
    }
  end

  describe "discovery over the real dependency source" do
    test "every discovered module really is an Igniter.Mix.Task", ctx do
      # Precision of the source scan. The regex collects every `Mix.Tasks.*`
      # module in a file that mentions `use Igniter.Mix.Task`; this asserts
      # that collection has no false positives, so a gap reported below is a
      # real task and not a sibling module that happened to share a file.
      #
      # The predicate is upstream's OWN (`Igniter.Mix.Task.igniter_task?/1`)
      # rather than a reimplementation, because it accepts `igniter/1` OR the
      # deprecated `igniter/2`. Checking only arity 1 wrongly rejects
      # `Mix.Tasks.Ash.Set.Domains`, which really does define
      # `def igniter(igniter, _argv)` and really is dispatched as an Igniter
      # task.
      not_igniter =
        Enum.reject(ctx.discovered, fn t ->
          Code.ensure_loaded?(t.module) and Igniter.Mix.Task.igniter_task?(t.module)
        end)

      assert not_igniter == [],
             "source scan collected modules that are not Igniter tasks:\n" <>
               Enum.map_join(not_igniter, "\n", &"  #{inspect(&1.module)} (#{&1.file})")
    end

    test "each dependency contributes at least one discovered task", ctx do
      # Non-vacuity guard. A wildcard or deps-path regression that returned no
      # files would make the closure assertions below pass while checking
      # nothing, so absence of tasks is itself a failure.
      by_dep = Enum.group_by(ctx.discovered, & &1.dep)

      for dep <- @deps do
        assert Map.has_key?(by_dep, dep),
               "no `use Igniter.Mix.Task` module found anywhere under " <>
                 "#{dep_root(dep)}/lib -- discovery is broken, not the envelope"
      end
    end
  end

  describe "the standing vocabulary, derived from its declaration sites" do
    test "the ontology declares a usable closed vocabulary for amp:standing", ctx do
      # Everything below consumes this derivation, so it is checked before it
      # is trusted. A reworded rdfs:comment that parsed to `[]` would make
      # membership meaningless rather than loud; a parse that swallowed the
      # surrounding prose would make it permissive. Both are caught here.
      assert MapSet.size(ctx.standings) > 1,
             """
             Derived no usable closed vocabulary from amp:standing's rdfs:comment
             in #{@ontology}.

               derived: #{inspect(Enum.sort(ctx.standings))}

             The reader expects one rdfs:comment on amp:standing containing
             "#{@closed_marker} A | B | C." -- that comment is the single
             declaration site this suite reads. If its wording changed, either
             restore the marker or teach parse_closed_vocabulary/1 the new one.
             This file deliberately holds no copy of the list to fall back on.
             """

      malformed = Enum.reject(ctx.standings, &Regex.match?(~r/^[A-Z][A-Z_]*$/, &1))

      assert malformed == [],
             "parsed non-token values out of amp:standing's rdfs:comment: " <>
               inspect(malformed)
    end

    test "the doctrine agents follow and the vocabulary this gate enforces agree", ctx do
      doc = doc_vocabulary()

      assert doc != nil,
             """
             Could not locate a closed vocabulary in #{@agents_doc}.

             The reader looks for a pipe-separated run of backticked all-caps
             tokens (the shape of the protocol list that tells an agent what to
             write into amp:standing). If that list was reworded or removed,
             agents no longer have a stated vocabulary to follow and this gate
             can no longer report drift against one -- restore it, or point
             this reader at wherever it now lives.
             """

      graph_only = MapSet.difference(ctx.standings, doc.values)
      doc_only = MapSet.difference(doc.values, ctx.standings)

      assert graph_only == MapSet.new(),
             """
             #{@ontology} declares amp:standing values that #{@agents_doc} does
             not list, so an agent following the documented protocol would never
             produce them:

             #{bullets(graph_only)}
             Add them to the protocol list at #{@agents_doc}:#{doc.line}, or drop
             them from amp:standing's rdfs:comment.
             """

      assert doc_only == @documented_vocabulary_drift,
             """
             The recorded disagreement between the doctrine and the gate changed.

               #{@agents_doc}:#{doc.line} lists: #{inspect(Enum.sort(doc.values))}
               amp:standing declares:  #{inspect(Enum.sort(ctx.standings))}

               recorded doc-only drift: #{inspect(Enum.sort(@documented_vocabulary_drift))}
               actual doc-only drift:   #{inspect(Enum.sort(doc_only))}

             Newly undeclared (AGENTS.md tells agents to write these, and this
             suite rejects them -- declare them in amp:standing's rdfs:comment or
             remove them from the protocol):
             #{bullets(MapSet.difference(doc_only, @documented_vocabulary_drift))}
             No longer drifting (the two sides now agree about these -- delete
             them from @documented_vocabulary_drift):
             #{bullets(MapSet.difference(@documented_vocabulary_drift, doc_only))}
             """
    end
  end

  describe "capability rows in the pack ontology" do
    test "every capability subject declares both a standing and an admitted flag", ctx do
      # The row query joins on amp:standing AND amp:admitted, so a row missing
      # either would not appear as a solution at all -- and would then be
      # misreported below as a MISSING task rather than an INCOMPLETE row.
      # Comparing against the bare `a amp:GeneratorCapability` set turns that
      # silent join failure into a precise message.
      declared = MapSet.new(capability_subjects())
      complete = MapSet.new(ctx.rows, & &1.subject)
      incomplete = MapSet.difference(declared, complete)

      assert MapSet.size(incomplete) == 0,
             "capability rows missing amp:standing and/or amp:admitted:\n" <>
               Enum.map_join(incomplete, "\n", &"  #{&1}")
    end

    test "every standing is in the vocabulary the ontology declares", ctx do
      outside = Enum.reject(ctx.rows, &MapSet.member?(ctx.standings, &1.standing))
      non_boolean = Enum.reject(ctx.rows, &is_boolean(&1.admitted))

      assert outside == [], out_of_vocabulary_message(outside, ctx.standings)

      assert non_boolean == [],
             "amp:admitted must be an xsd:boolean:\n" <>
               Enum.map_join(non_boolean, "\n", &"  #{&1.task}: #{inspect(&1.admitted)}")
    end

    test "admission tracks standing: only the live standings are admitted", ctx do
      # A not-exercised standing means exactly that: nothing has been observed.
      # Admitting one would let the projection compose a morphism no run has
      # ever seen -- the exact upgrade the ontology forbids without evidence.
      admissible = admissible_standings(ctx.standings)

      # Bound the derivation before relying on it: empty would admit nothing
      # and reject every real row for the wrong reason, and a set equal to the
      # whole vocabulary would admit everything and assert nothing.
      assert MapSet.size(admissible) > 0 and
               MapSet.size(admissible) < MapSet.size(ctx.standings),
             "liveness derivation over #{inspect(Enum.sort(ctx.standings))} " <>
               "yielded #{inspect(Enum.sort(admissible))}, which is empty or total"

      incoherent =
        Enum.reject(ctx.rows, fn r ->
          r.admitted == MapSet.member?(admissible, r.standing)
        end)

      assert incoherent == [],
             "admitted must be true for exactly #{inspect(Enum.sort(admissible))}:\n" <>
               Enum.map_join(incoherent, "\n", fn r ->
                 "  #{r.task}: standing=#{r.standing} admitted=#{r.admitted}"
               end)
    end
  end

  describe "version scope of the envelope" do
    test "every dependency the ontology cites is a real loaded application here", _ctx do
      cited = cited_deps()

      # Non-vacuity: a literal scan that matched nothing would make all three
      # version assertions pass while checking nothing, and the deps this suite
      # discovers tasks from must be among the ones it cites.
      assert MapSet.size(cited) > 0,
             "no `deps/<name>/` citation found in any literal in #{@ontology}"

      assert MapSet.subset?(MapSet.new(@deps), cited),
             "the envelope closes over #{inspect(@deps)} but cites only " <>
               "#{inspect(Enum.sort(cited))}"

      unresolvable = Enum.reject(cited, &(dep_version(&1) != nil))

      assert unresolvable == [],
             """
             The ontology cites source under `deps/<name>/` for dependencies that
             are not loadable applications here, so `Application.spec/2` can give
             no version for the claims resting on them:

             #{bullets(unresolvable)}
             """
    end

    test "every cited dependency is resolved by the lock its citations are relative to", _ctx do
      lock = fixture_lock()
      cited = cited_deps()

      assert map_size(lock) > 0, "parsed no hex entries out of #{@fixture_lock}"

      absent = Enum.reject(cited, &Map.has_key?(lock, &1))

      assert absent == [],
             """
             The ontology cites `deps/<name>/...` paths that #{@fixture_lock} does
             not resolve, so those citations point into a tree the manufacturing
             subject does not actually have:

             #{bullets(absent)}
             """
    end

    test "the repo this suite scans and the fixture its citations resolve against agree", _ctx do
      lock = fixture_lock()

      versions =
        Map.new(cited_deps(), fn dep -> {dep, {dep_version(dep), Map.get(lock, dep)}} end)

      skew =
        versions
        |> Enum.filter(fn {_dep, {repo, fixture}} -> repo != fixture end)
        |> MapSet.new(fn {dep, _} -> dep end)

      assert skew == @known_version_skew,
             """
             The set of dependencies that resolve to DIFFERENT versions in this
             repo and in the fixture changed.

             This suite discovers Igniter tasks from the repo's trees, while every
             `deps/...` citation backing a standing is resolved against the
             fixture's. Where the two disagree, closure is computed over one
             version and the standings were evidenced against another, and a line
             number verified on one side says nothing about the other.

             #{version_table(versions)}
               recorded skew: #{inspect(Enum.sort(@known_version_skew))}
               actual skew:   #{inspect(Enum.sort(skew))}

             Newly skewed (bring the two locks back into agreement, or record it
             here with the reason it is acceptable):
             #{bullets(MapSet.difference(skew, @known_version_skew))}
             No longer skewed (delete it from @known_version_skew):
             #{bullets(MapSet.difference(@known_version_skew, skew))}
             """
    end

    test "every version the ontology pins agrees with the lock it describes", _ctx do
      lock = fixture_lock()
      pins = declared_pins()
      pinned_deps = MapSet.new(pins, fn {dep, _} -> dep end)

      # Closure on the citation side: a cited dependency with no pin has an
      # UNDECLARED version scope, which is the state this whole section exists
      # to rule out. Asserted as a subset rather than against a list written
      # here, so a newly cited dependency fails until it is pinned.
      unpinned = MapSet.difference(cited_deps(), pinned_deps)

      assert unpinned == MapSet.new(),
             """
             The ontology cites source under `deps/<name>/` for dependencies it
             pins no amp:DependencyPin version for, so the line numbers in those
             citations are scoped to nothing:

             #{bullets(unpinned)}
             """

      mismatched =
        Enum.reject(pins, fn {dep, pinned} -> Map.get(lock, dep) == pinned end)

      assert mismatched == [],
             """
             amp:DependencyPin claims versions that #{@fixture_lock} does not
             resolve. Every citation scoped to one of these pins names line
             numbers in a tarball that is not the one on disk:

             #{Enum.map_join(mismatched, "\n", fn {dep, pinned} -> "  #{dep}: pinned #{pinned}, locked #{inspect(Map.get(lock, dep))}" end)}
             """
    end
  end

  describe "closure between the dependency surface and the envelope" do
    test "every Igniter task in the resolved deps has a capability row", ctx do
      gaps = uncovered_tasks(ctx.discovered, ctx.rows)

      assert gaps == [], coverage_summary(ctx.discovered, ctx.rows, gaps)
    end

    test "every capability row resolves to a real task, bar the documented pseudo-rows", ctx do
      # Reverse direction: catches a row whose task was renamed or removed
      # upstream, which the forward direction cannot see (the vanished task is
      # no longer discovered, so nothing reports its now-dangling row).
      unresolved = unresolvable_task_names(ctx.rows)

      assert unresolved == @pseudo_capabilities,
             """
             Capability rows that do not resolve to a real mix task must be
             EXACTLY the documented pseudo-capabilities.

               expected: #{inspect(Enum.sort(@pseudo_capabilities))}
               actual:   #{inspect(Enum.sort(unresolved))}

             Unexpected (row names a task Mix cannot find -- renamed or removed
             upstream, or a new pseudo-row that needs documenting in
             @pseudo_capabilities):
             #{bullets(MapSet.difference(unresolved, @pseudo_capabilities))}
             Now resolvable (a documented pseudo-capability became a real task;
             give it a real standing and drop it from @pseudo_capabilities):
             #{bullets(MapSet.difference(@pseudo_capabilities, unresolved))}
             """
    end
  end

  describe "falsifiers -- the gate reports gaps it is supposed to report" do
    # Both coverage falsifiers assert the DELTA a mutation introduces, not an
    # absolute gap list. Asserting the absolute list would couple them to the
    # ontology being complete, so a single real gap would fail them too and
    # bury the one message that actually says what to add.

    test "deleting the row for a real discovered task reports that task", ctx do
      # Chosen at random rather than named, so this cannot pass by coinciding
      # with a literal task name written in this file.
      victim = Enum.random(ctx.discovered)
      thinned = Enum.reject(ctx.rows, &(&1.task == victim.task))

      before = uncovered_tasks(ctx.discovered, ctx.rows)
      gaps = uncovered_tasks(ctx.discovered, thinned)

      assert Enum.map(gaps, & &1.task) -- Enum.map(before, & &1.task) == [victim.task]
      assert coverage_summary(ctx.discovered, thinned, gaps) =~ victim.task
    end

    test "an undeclared task is reported as a gap", ctx do
      phantom = phantom_task()
      refute Enum.any?(ctx.rows, &(&1.task == phantom))

      widened = ctx.discovered ++ [%{task: phantom, module: nil, file: nil, dep: :ash}]

      before = uncovered_tasks(ctx.discovered, ctx.rows)
      gaps = uncovered_tasks(widened, ctx.rows)

      assert Enum.map(gaps, & &1.task) -- Enum.map(before, & &1.task) == [phantom]
      assert coverage_summary(widened, ctx.rows, gaps) =~ phantom
    end

    test "a third pseudo-capability row breaks the exact exception list", ctx do
      phantom = phantom_task()

      # The falsifier is only honest if the phantom genuinely resolves to
      # nothing -- otherwise it would be filtered out as a real task.
      assert Mix.Task.get(phantom) == nil,
             "#{phantom} unexpectedly resolves to a real mix task"

      # The synthetic row needs A standing. Drawn from the declared vocabulary
      # rather than written down, so this file still names no vocabulary value;
      # a non-live one is chosen to keep the row coherent with admitted: false.
      standing =
        ctx.standings
        |> MapSet.difference(admissible_standings(ctx.standings))
        |> Enum.random()

      rows =
        ctx.rows ++ [%{subject: phantom, task: phantom, standing: standing, admitted: false}]

      unresolved = unresolvable_task_names(rows)

      assert MapSet.member?(unresolved, phantom)
      refute unresolved == @pseudo_capabilities
    end

    test "an out-of-vocabulary standing is reported by value, with the doctrine conflict", ctx do
      # The falsifier for the derivation itself. A row carrying a value the
      # ontology does not declare must produce a message that names the VALUE
      # and points at the doctrine that told an agent to write it -- an opaque
      # set-membership failure would leave the reader unable to tell which of
      # the two declaration sites is wrong.
      #
      # While drift exists the offender is taken FROM it rather than invented,
      # because that is the value an agent following AGENTS.md actually
      # produces; a generated string would falsify a different, easier claim.
      # Once the drift is resolved there is no such value, so the falsifier
      # falls back to a generated token and keeps testing the reporting path.
      offender =
        case Enum.to_list(@documented_vocabulary_drift) do
          [] -> String.upcase(Faker.Lorem.word()) <> "_#{System.unique_integer([:positive])}"
          drift -> Enum.random(drift)
        end

      refute MapSet.member?(ctx.standings, offender)

      row = %{
        subject: "urn:falsifier",
        task: Enum.random(ctx.rows).task,
        standing: offender,
        admitted: false
      }

      message = out_of_vocabulary_message([row], ctx.standings)

      assert message =~ offender
      assert message =~ @agents_doc
      assert message =~ row.task
    end
  end

  # --- discovery over the real dep source -------------------------------------

  defp dep_root(dep) do
    Mix.Project.deps_paths()
    |> Map.fetch!(dep)
  end

  defp discover_igniter_tasks do
    @deps
    |> Enum.flat_map(fn dep ->
      root = dep_root(dep)

      [root, "lib", "**", "*.ex"]
      |> Path.join()
      |> Path.wildcard()
      |> Enum.flat_map(&igniter_tasks_in_file(&1, dep))
    end)
    |> Enum.uniq_by(& &1.task)
    |> Enum.sort_by(& &1.task)
  end

  defp igniter_tasks_in_file(file, dep) do
    source = File.read!(file)

    if String.contains?(source, "use Igniter.Mix.Task") do
      ~r/defmodule\s+(Mix\.Tasks\.[A-Za-z0-9_.]+)\s+do/
      |> Regex.scan(source, capture: :all_but_first)
      |> List.flatten()
      # `<Task>.Docs` modules carry Igniter's @moduledoc/@shortdoc text. They
      # sit outside the `if Code.ensure_loaded?(Igniter)` guard and are not
      # tasks. Real example: ash_postgres.setup_vector.ex defines both
      # Mix.Tasks.AshPostgres.SetupVector.Docs and the task itself.
      |> Enum.reject(&String.ends_with?(&1, ".Docs"))
      |> Enum.uniq()
      |> Enum.map(fn name ->
        module = Module.concat([name])
        %{task: Mix.Task.task_name(module), module: module, file: file, dep: dep}
      end)
    else
      []
    end
  end

  # --- the ontology, through the real RDF/SPARQL stack ------------------------

  defp ontology_graph, do: RDF.Turtle.read_file!(@ontology)

  defp solve(query) do
    prologue = "PREFIX amp: <#{@amp}>\nPREFIX rdfs: <#{@rdfs}>\n"

    ontology_graph()
    |> SPARQL.execute_query(SPARQL.query(prologue <> query))
    |> Map.fetch!(:results)
  end

  defp capability_rows do
    """
    SELECT ?c ?mix_task ?standing ?admitted
    WHERE {
      ?c a amp:GeneratorCapability ;
         amp:mixTask ?mix_task ;
         amp:standing ?standing ;
         amp:admitted ?admitted .
    }
    ORDER BY ?mix_task
    """
    |> solve()
    |> Enum.map(fn s ->
      %{
        subject: to_string(s["c"]),
        task: RDF.Literal.value(s["mix_task"]),
        standing: RDF.Literal.value(s["standing"]),
        admitted: RDF.Literal.value(s["admitted"])
      }
    end)
  end

  defp capability_subjects do
    "SELECT ?c WHERE { ?c a amp:GeneratorCapability . }"
    |> solve()
    |> Enum.map(&to_string(&1["c"]))
  end

  # --- the two vocabulary declaration sites, both derived ---------------------

  # The vocabulary this gate ENFORCES, read from the ontology it guards. Not a
  # copy: if the ontology's comment changes, this changes with it, which is the
  # only way a gate can fail on drift rather than participate in it.
  defp declared_standings do
    "SELECT ?comment WHERE { amp:standing rdfs:comment ?comment . }"
    |> solve()
    |> Enum.flat_map(&parse_closed_vocabulary(RDF.Literal.value(&1["comment"])))
    |> MapSet.new()
  end

  defp parse_closed_vocabulary(comment) do
    case String.split(comment, @closed_marker, parts: 2) do
      [_, list] ->
        list
        |> String.split("|")
        |> Enum.map(&(&1 |> String.trim() |> String.trim_trailing(".") |> String.trim()))
        |> Enum.reject(&(&1 == ""))

      _ ->
        []
    end
  end

  # The vocabulary the DOCTRINE states, read from the protocol agents follow.
  # Returns nil when the list cannot be located, so the caller reports a
  # missing protocol rather than silently comparing against an empty set.
  defp doc_vocabulary do
    src = File.read!(@agents_doc)

    case Regex.run(@doc_vocabulary_run, src, return: :index) do
      [{offset, len}] ->
        values =
          ~r/`([A-Z][A-Z_]*)`/
          |> Regex.scan(binary_part(src, offset, len), capture: :all_but_first)
          |> List.flatten()
          |> MapSet.new()

        newlines = :binary.matches(binary_part(src, 0, offset), "\n")

        %{values: values, line: 1 + length(newlines)}

      _ ->
        nil
    end
  end

  defp admissible_standings(standings) do
    MapSet.new(Enum.filter(standings, &String.contains?(&1, @liveness_stem)))
  end

  # --- version scope ----------------------------------------------------------

  # Every dependency whose source the ontology cites, taken from the literals
  # themselves rather than from a named property, so a citation moved onto a
  # new property (amp:citesFile, say) is still seen.
  defp cited_deps do
    "SELECT ?o WHERE { ?s ?p ?o . FILTER(isLiteral(?o)) }"
    |> solve()
    |> Enum.flat_map(fn s ->
      ~r{\bdeps/([a-z_0-9]+)/}
      |> Regex.scan(RDF.Literal.lexical(s["o"]), capture: :all_but_first)
      |> List.flatten()
    end)
    |> MapSet.new(&String.to_atom/1)
  end

  defp declared_pins do
    """
    SELECT ?dep ?vsn
    WHERE { ?p a amp:DependencyPin ; amp:pinnedDep ?dep ; amp:pinnedVersion ?vsn . }
    """
    |> solve()
    |> Enum.map(fn s ->
      {String.to_atom(RDF.Literal.value(s["dep"])), RDF.Literal.value(s["vsn"])}
    end)
  end

  # The version of the tree THIS suite scans. Read from the application's real
  # .app metadata, which is the same file Mix resolves, not from a lock this
  # test parses itself.
  defp dep_version(dep) do
    Application.load(dep)

    case Application.spec(dep, :vsn) do
      nil -> nil
      vsn -> List.to_string(vsn)
    end
  end

  # The version of the tree the ontology's citations are resolved against.
  defp fixture_lock do
    @lock_entry
    |> Regex.scan(File.read!(@fixture_lock), capture: :all_but_first)
    |> Map.new(fn [dep, vsn] -> {String.to_atom(dep), vsn} end)
  end

  # --- the analysis both the gate and its falsifiers run ----------------------

  defp uncovered_tasks(discovered, rows) do
    covered = MapSet.new(rows, & &1.task)
    Enum.reject(discovered, &MapSet.member?(covered, &1.task))
  end

  defp unresolvable_task_names(rows) do
    rows
    |> Enum.filter(&(Mix.Task.get(&1.task) == nil))
    |> MapSet.new(& &1.task)
  end

  # Names the offending VALUE, then names the other declaration site that may
  # have told an agent to write it. Without the second half the reader knows a
  # row is illegal but not which of the two files is the one to change.
  defp out_of_vocabulary_message(rows, standings) do
    doc = doc_vocabulary()
    drift = if doc, do: MapSet.difference(doc.values, standings), else: MapSet.new()

    """
    amp:standing values outside the vocabulary #{@ontology} itself declares:

    #{Enum.map_join(rows, "\n", &"  #{&1.task}: #{inspect(&1.standing)}")}

      declared by amp:standing's rdfs:comment: #{inspect(Enum.sort(standings))}

    #{doctrine_note(doc, drift, standings)}
    """
  end

  defp doctrine_note(nil, _drift, _standings) do
    "No vocabulary list could be located in #{@agents_doc}, so this suite " <>
      "cannot say whether the doctrine sanctions the value above."
  end

  defp doctrine_note(doc, drift, standings) do
    if MapSet.size(drift) == 0 do
      "#{@agents_doc}:#{doc.line} lists the same values, so the value above is " <>
        "sanctioned by neither site and is simply wrong."
    else
      """
      #{@agents_doc}:#{doc.line} states the protocol agents follow. It lists #{MapSet.size(doc.values)} values; the ontology declares #{MapSet.size(standings)}. These are listed there and declared NOWHERE in the graph:

      #{bullets(drift)}
      So a row written exactly as #{@agents_doc} instructs fails HERE. Two
      declaration sites disagree about what a legal amp:standing is; exactly one
      of them has to change. Either declare the value(s) above in amp:standing's
      rdfs:comment in #{@ontology}, or remove them from the #{@agents_doc}
      protocol list. This suite derives both sides and restates neither, so
      fixing either file is enough.
      """
    end
  end

  defp coverage_summary(discovered, rows, gaps) do
    """
    Ash / AshPostgres Igniter task coverage -- #{@ontology}

      Igniter tasks discovered in #{inspect(@deps)}: #{length(discovered)}
      amp:GeneratorCapability rows in the ontology: #{length(rows)}
      discovered tasks covered by a row:            #{length(discovered) - length(gaps)}
      UNCOVERED:                                    #{length(gaps)}

    Uncovered tasks (each needs an amp:GeneratorCapability row carrying
    amp:mixTask, amp:standing, amp:admitted, amp:phase, amp:evidence and, when
    not admitted, amp:refusalReason):
    #{Enum.map_join(gaps, "\n", &"  #{&1.task}  <- #{&1.file}")}

    A newly added upstream task must be given a truthful standing from an
    OBSERVED run. The not-exercised standing plus admitted false is the correct
    entry for a task nobody has run yet; it is not a claim that it is broken.
    """
  end

  defp version_table(versions) do
    versions
    |> Enum.sort()
    |> Enum.map_join("\n", fn {dep, {repo, fixture}} ->
      marker = if repo == fixture, do: " ", else: "!"
      "  #{marker} #{dep}: repo #{inspect(repo)} / fixture #{inspect(fixture)}"
    end)
  end

  defp bullets(names) do
    case Enum.sort(names) do
      [] -> "  (none)"
      list -> Enum.map_join(list, "\n", &"  #{&1}")
    end
  end

  # A task name that provably does not exist upstream. Generated rather than
  # written down so a falsifier cannot pass by coinciding with a literal, and
  # suffixed with a unique integer so it cannot collide with a real Ash task
  # (`ash.gen.gettext` is real, and Faker's word list is not disjoint from it).
  defp phantom_task do
    "ash.gen." <> Faker.Lorem.word() <> "_#{System.unique_integer([:positive])}"
  end
end
