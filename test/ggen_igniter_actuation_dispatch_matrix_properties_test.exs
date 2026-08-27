defmodule GgenIgniter.ActuationDispatchMatrixPropertiesTest do
  @moduledoc """
  Real, combinatorial, model-based property test of `mix ggen_igniter.sync`'s
  ACTUATION DISPATCH LOGIC itself -- i.e. which real branch of
  `Mix.Tasks.GgenIgniter.Sync`'s private `actuate!/8` (and, one level below
  it, which branch of `GgenIgniter.Actuate.write_file!/3` /
  `GgenIgniter.Actuate.inject_content!/5`) a given CLI invocation hits, as a
  function of the cross product of:

    * `--engine` (`sparql` | `oxigraph`)
    * `mode` (`file` | `eval`, via template frontmatter)
    * `--for-each` (present | absent)
    * `--dry-run` (present | absent)
    * `inject: true` (present | absent, template frontmatter -- `mode: file` only)
    * a write-guard variant (`none` | `unless_exists` | `skip_if` -- `mode:
      file`, `inject: false` only)

  This is a NEW matrix, not a duplicate of any existing
  `test/ggen_igniter_*_properties_test.exs` file:

    * `ggen_igniter_actuate_properties_test.exs` exercises
      `GgenIgniter.Actuate` DIRECTLY (in-process function calls), never the
      CLI task, never `--engine`/`--for-each`/`--dry-run` dispatch.
    * `ggen_igniter_sync_properties_test.exs` exercises two of
      `Mix.Tasks.GgenIgniter.Sync`'s PURE helpers
      (`build_bindings/2`/`resolve_named_queries!/2`) in-process; it never
      shells out to the real `mix ggen_igniter.sync` CLI and never varies
      `mode`/`inject`/write-guards.
    * `ggen_igniter_full_pipeline_properties_test.exs` composes
      `Frontmatter.split_template/1` -> `Render.render/2` ->
      `Actuate.write_file!/3` directly (in-process), with no `--engine`,
      no `--for-each`, no `mode: eval`, no `inject: true` -- it is a
      2-dimensional matrix (`to`/`unless_exists`) of ONE actuation path
      only.
    * `ggen_igniter_cross_engine_equivalence_properties_test.exs` compares
      `sparql` vs `oxigraph` QUERY RESULTS row-for-row; it does not touch
      `mix ggen_igniter.sync`'s dispatch branches at all.

  None of the five pre-existing property files runs the real CLI subprocess
  across `engine x mode x for_each x dry_run x inject x guard_variant`
  jointly. This file does, using StreamData to generate members of the REAL
  VALID subset of that 6-dimensional space (worked out below), running one
  real `mix ggen_igniter.sync` subprocess per generated case against
  fixtures this file writes itself into a fresh temp directory (Chicago
  style: real subprocess, real files on disk, real state-based assertions on
  the real written/unwritten/injected/evaluated artifact -- no
  `unittest.mock`/`Mox`/interaction-based assertion of any kind, per
  `~/.claude/rules/testing-chicago-style.md`).

  ## Working out the real valid combination set (not brute-forced)

  Read directly from `lib/mix/tasks/ggen_igniter.sync.ex`'s `igniter/1` and
  `actuate!/8` clauses before writing this file:

  1. `inject_spec` is computed ONLY `if mode == :file and frontmatter.inject`
     -- for `mode: :eval`, `inject_spec` is always `nil` and frontmatter
     `inject: true` on an eval-mode template is simply never consulted (dead
     data, not a runtime error). So `inject: true` is only a MEANINGFULLY
     DISTINCT case when `mode: :file`; this test never generates
     `mode: :eval, inject: true` as if it were a fourth real branch, because
     it collapses to the plain `mode: :eval` branch.
  2. `write_opts` (`unless_exists`/`skip_if`/`dry_run`) is passed to
     `actuate!/8`'s `mode: :file, inject_spec: nil` clause and consulted by
     `Actuate.write_file!/3`'s real decision table. The SAME `write_opts` is
     bound as `_write_opts` (ignored, by the underscore prefix in the
     function head itself) in the `mode: :file, inject_spec: {...}` clause,
     and not passed at all to either `mode: :eval` clause. So a write-guard
     variant (`unless_exists`/`skip_if`) is only a MEANINGFULLY DISTINCT case
     when `mode: :file, inject: false` -- generating it crossed with
     `inject: true` or `mode: :eval` would only be testing "this flag has no
     effect here", which is already implied by reading the function heads
     above, not a new dispatch branch to probe.
  3. `--for-each` and `--dry-run` and `--engine` are each honored
     independently by EVERY actuation branch (`for_each` fans out the same
     `actuate!/8` call once per row; `dry_run` is threaded into
     `write_opts`/`inject_opts`/the `:eval` clause guard; `--engine` only
     changes the ROW VALUE SHAPE fed into rendering, per the sync task's own
     moduledoc) -- these three are freely crossable with every branch below,
     no additional constraint.

  This yields exactly 3 branch families, each freely crossed with `engine x
  for_each x dry_run` (2x2x2 = 8 each):

    * **Branch A** (`mode: file, inject: false`) x 3 guard variants
      (`none`/`unless_exists`/`skip_if`) = 8 x 3 = 24 valid cases.
    * **Branch B** (`mode: file, inject: true`) = 8 valid cases.
    * **Branch C** (`mode: eval`) = 8 valid cases.

  Total: 40 valid combinations in the real space. `combo_gen/0` below
  generates exactly this set (via dependent `gen all` binding: `inject`'s
  generator depends on the generated `mode`, `guard_variant`'s generator
  depends on both) -- it can never produce `mode: :eval, inject: true` or a
  non-`:none` `guard_variant` under `inject: true`, because those are not
  members of the valid set reasoned out above.

  ## Engine-shape normalization (a real, disclosed, deliberately-authored
  choice, not an assumption)

  Empirically confirmed before writing this test (`mix run -e` against a
  throwaway probe ontology/query): the native oxigraph engine returns a
  plain untyped string literal wrapped in literal double-quote characters
  (`"\"Agent6.Mod1\""`, no `^^datatype` suffix for an untyped string), while
  `sparql` returns the bare value (`"Agent6.Mod1"`) -- exactly the
  discrepancy `Mix.Tasks.GgenIgniter.Sync`'s own moduledoc discloses. Every
  fixture template this file writes strips those quote characters itself
  (`String.replace(module_name, "\"", "")`) before using a value in a
  `--for-each`-rendered `--out` path or in an assertion -- a normalization
  this TEST authors into its own throwaway fixtures, not a change to
  `GgenIgniter.Query.Oxigraph`/`Render`/`Actuate` -- so this file's
  dispatch-branch assertions are the same across both engines, and only
  `--engine` dispatch itself (not incidental quoting) is what varies.
  """

  use ExUnit.Case, async: false
  use ExUnitProperties

  @moduletag :integration

  alias StreamData

  # ---------------------------------------------------------------------
  # Shared, static fixtures -- ontology + two queries, written once, reused
  # read-only by every generated case. No production `lib/` code and no
  # other test file's fixtures are touched; everything below is new and
  # additive, scoped to this file's own `setup_all` temp directory.
  # ---------------------------------------------------------------------

  @ontology_ttl """
  @prefix ex: <http://example.org/agent6-dispatch-matrix#> .

  ex:Spec1 a ex:Spec ;
      ex:moduleName "Agent6.Single" ;
      ex:fieldName "single_field" .

  ex:Mod1 a ex:Mod ; ex:moduleName "Agent6.Mod1" ; ex:fieldName "field1" .
  ex:Mod2 a ex:Mod ; ex:moduleName "Agent6.Mod2" ; ex:fieldName "field2" .
  ex:Mod3 a ex:Mod ; ex:moduleName "Agent6.Mod3" ; ex:fieldName "field3" .
  """

  @spec_rq """
  PREFIX ex: <http://example.org/agent6-dispatch-matrix#>
  SELECT ?module_name ?field_name WHERE {
    ?s a ex:Spec ; ex:moduleName ?module_name ; ex:fieldName ?field_name .
  }
  """

  @mods_rq """
  PREFIX ex: <http://example.org/agent6-dispatch-matrix#>
  SELECT ?module_name ?field_name WHERE {
    ?s a ex:Mod ; ex:moduleName ?module_name ; ex:fieldName ?field_name .
  }
  ORDER BY ?module_name
  """

  @anchor "# GGEN:AGENT6:ANCHOR"

  # `mode: file, inject: false` template -- no frontmatter needed since
  # `--out`/`--mode` are always passed explicitly on the CLI in this test.
  # Both bound values are quote-stripped in the template itself (see
  # moduledoc's "Engine-shape normalization" section) so the written content
  # is byte-identical across `--engine sparql` and `--engine oxigraph`.
  @file_plain_eex """
  defmodule <%= module_name |> String.replace("\\"", "") %> do
    def field_name, do: "<%= field_name |> String.replace("\\"", "") %>"
  end
  """

  # `mode: file, inject: true` template, anchored on a literal `after:`
  # marker. Requires the target file to ALREADY exist and already contain
  # `@anchor` -- this test pre-creates that file itself before invoking sync.
  @file_inject_eex """
  ---
  to: "unused_since_--out_is_always_passed_explicitly.ex"
  inject: true
  after: "# GGEN:AGENT6:ANCHOR"
  ---
    def injected_field, do: "<%= field_name |> String.replace("\\"", "") %>"
  """

  # `mode: eval` template: never writes to disk; its only observable side
  # effect is writing a sentinel file named after the (quote-stripped)
  # module name, so a for-each fan-out's per-row eval calls are each
  # independently verifiable on disk without depending on eval's return
  # value being captured anywhere.
  @eval_eex """
  ---
  mode: eval
  ---
  sentinel_dir = System.get_env("AGENT6_EVAL_SENTINEL_DIR")
  clean_module = module_name |> String.replace("\\"", "")
  clean_field = field_name |> String.replace("\\"", "")
  if sentinel_dir do
    File.write!(Path.join(sentinel_dir, clean_module <> ".txt"), clean_field)
  end
  "evaluated-\#{clean_module}"
  """

  # Fixtures are written FRESH into each generated case's own `case_dir`
  # (never shared across cases, never shared across concurrently-running
  # test processes) -- deliberately NOT a module-level `setup_all` temp
  # directory. This project's own dev environment runs multiple concurrent
  # agents against this same repo/host, all sharing one OS tmp root
  # (`System.tmp_dir!()`, `~/.cache/tmp` on this machine); a real run of
  # this file's earlier draft (shared `setup_all` fixture dir, cleaned via
  # `on_exit` only at module end) hit a genuine
  # `File.Error: could not open ".../ontology.ttl": no such file or
  # directory` mid-suite when run alongside the FULL `mix test` run (never
  # when this file ran alone, and never across 3 separate `--seed` reruns
  # of this file in isolation) -- consistent with an external, concurrent
  # process touching the shared tmp root, not a bug in this file's own
  # dispatch logic. Writing every fixture into the per-case directory this
  # test itself creates and removes (see the property's `case_dir`/`after`
  # block) removes that shared-state surface entirely: nothing outside this
  # one `check all` iteration's own directory can ever race with it.
  defp write_fixtures!(case_dir) do
    ontology_path = Path.join(case_dir, "ontology.ttl")
    spec_rq_path = Path.join(case_dir, "spec.rq")
    mods_rq_path = Path.join(case_dir, "mods.rq")
    file_plain_path = Path.join(case_dir, "file_plain.ex.eex")
    file_inject_path = Path.join(case_dir, "file_inject.ex.eex")
    eval_path = Path.join(case_dir, "eval_body.exs.eex")

    File.write!(ontology_path, @ontology_ttl)
    File.write!(spec_rq_path, @spec_rq)
    File.write!(mods_rq_path, @mods_rq)
    File.write!(file_plain_path, @file_plain_eex)
    File.write!(file_inject_path, @file_inject_eex)
    File.write!(eval_path, @eval_eex)

    %{
      ontology: ontology_path,
      spec_rq: spec_rq_path,
      mods_rq: mods_rq_path,
      file_plain: file_plain_path,
      file_inject: file_inject_path,
      eval: eval_path
    }
  end

  # ---------------------------------------------------------------------
  # Generators -- see moduledoc's "working out the real valid combination
  # set" for why each dependency exists.
  # ---------------------------------------------------------------------

  defp inject_gen(:file), do: StreamData.boolean()
  defp inject_gen(:eval), do: StreamData.constant(false)

  defp guard_variant_gen(:file, false),
    do: StreamData.member_of([:none, :unless_exists, :skip_if])

  defp guard_variant_gen(_mode, _inject), do: StreamData.constant(:none)

  defp combo_gen do
    gen all(
          mode <- StreamData.member_of([:file, :eval]),
          engine <- StreamData.member_of(["sparql", "oxigraph"]),
          for_each <- StreamData.boolean(),
          dry_run <- StreamData.boolean(),
          inject <- inject_gen(mode),
          guard_variant <- guard_variant_gen(mode, inject)
        ) do
      %{
        mode: mode,
        engine: engine,
        for_each: for_each,
        dry_run: dry_run,
        inject: inject,
        guard_variant: guard_variant
      }
    end
  end

  # ---------------------------------------------------------------------
  # The property: for every valid combo, run the real CLI once and assert
  # the real, branch-appropriate outcome shape.
  # ---------------------------------------------------------------------

  property "mix ggen_igniter.sync dispatches to the correct real actuation branch, and " <>
             "produces the correct real on-disk/evaluated outcome, for every valid " <>
             "engine x mode x for_each x dry_run x inject x guard_variant combination" do
    check all(combo <- combo_gen(), max_runs: 24) do
      case_dir =
        Path.join(
          System.tmp_dir!(),
          "ggen_igniter_dispatch_case_#{System.unique_integer([:positive])}"
        )

      File.mkdir_p!(case_dir)

      try do
        fixtures = write_fixtures!(case_dir)
        run_case!(fixtures, case_dir, combo)
      after
        File.rm_rf!(case_dir)
      end
    end
  end

  # ---------------------------------------------------------------------
  # Per-combo setup + real subprocess invocation + real assertions.
  # ---------------------------------------------------------------------

  defp run_case!(fixtures, case_dir, %{mode: :eval} = combo) do
    sentinel_dir = Path.join(case_dir, "sentinels")
    File.mkdir_p!(sentinel_dir)

    query_args =
      if combo.for_each,
        do: ["--query", "mods=#{fixtures.mods_rq}", "--for-each", "mods"],
        else: ["--query", "spec=#{fixtures.spec_rq}"]

    args =
      [
        "--engine",
        combo.engine,
        "--ontology",
        fixtures.ontology,
        "--template",
        fixtures.eval
      ] ++ query_args ++ if(combo.dry_run, do: ["--dry-run"], else: [])

    {output, exit_code} =
      run_sync!(args, [{"AGEN6_UNUSED", "1"}, {"AGENT6_EVAL_SENTINEL_DIR", sentinel_dir}])

    assert exit_code == 0, "mix ggen_igniter.sync failed (combo=#{inspect(combo)}):\n#{output}"

    expected_modules =
      if combo.for_each,
        do: ["Agent6.Mod1", "Agent6.Mod2", "Agent6.Mod3"],
        else: ["Agent6.Single"]

    expected_fields =
      if combo.for_each, do: ["field1", "field2", "field3"], else: ["single_field"]

    if combo.dry_run do
      # Branch C, dry-run: a "planned: evaluate ..." notice per row, nothing
      # ever actually evaluated -- no sentinel file, no "evaluated" notice.
      for _ <- expected_modules do
        assert output =~ "planned: evaluate #{fixtures.eval} (mode: eval)"
      end

      refute output =~ "evaluated "
      assert File.ls!(sentinel_dir) == []
    else
      # Branch C, real: one real Code.eval_string/2 call per row, its real
      # side effect (writing the sentinel file) actually happened, and the
      # notice reports the real eval return value.
      written = sentinel_dir |> File.ls!() |> Enum.sort()
      assert written == Enum.map(expected_modules, &(&1 <> ".txt")) |> Enum.sort()

      for {module, field} <- Enum.zip(expected_modules, expected_fields) do
        assert output =~ "evaluated #{fixtures.eval} -> \"evaluated-#{module}\""
        assert File.read!(Path.join(sentinel_dir, module <> ".txt")) == field
      end

      refute output =~ "wrote "
      refute output =~ "injected "
    end
  end

  defp run_case!(fixtures, case_dir, %{mode: :file, inject: true} = combo) do
    modules =
      if combo.for_each,
        do: ["Agent6.Mod1", "Agent6.Mod2", "Agent6.Mod3"],
        else: ["Agent6.Single"]

    fields = if combo.for_each, do: ["field1", "field2", "field3"], else: ["single_field"]

    # Injection is fail-closed on a missing target -- pre-create every target
    # file this run's fan-out will touch, each already containing the real
    # anchor line and nothing else.
    pre_bodies =
      for module <- modules, into: %{} do
        path = Path.join(case_dir, module <> ".ex")
        body = "defmodule #{module} do\n" <> @anchor <> "\nend\n"
        File.write!(path, body)
        {module, body}
      end

    query_args =
      if combo.for_each,
        do: ["--query", "mods=#{fixtures.mods_rq}", "--for-each", "mods"],
        else: ["--query", "spec=#{fixtures.spec_rq}"]

    out_arg =
      if combo.for_each,
        do: [
          "--out",
          Path.join(case_dir, "<%= module_name |> String.replace(\"\\\"\", \"\") %>.ex")
        ],
        else: ["--out", Path.join(case_dir, "Agent6.Single.ex")]

    args =
      [
        "--engine",
        combo.engine,
        "--ontology",
        fixtures.ontology,
        "--template",
        fixtures.file_inject
      ] ++ query_args ++ out_arg ++ if(combo.dry_run, do: ["--dry-run"], else: [])

    {output, exit_code} = run_sync!(args)

    assert exit_code == 0, "mix ggen_igniter.sync failed (combo=#{inspect(combo)}):\n#{output}"

    for {module, field} <- Enum.zip(modules, fields) do
      path = Path.join(case_dir, module <> ".ex")
      original_body = pre_bodies[module]

      if combo.dry_run do
        # Branch B, dry-run: real anchor resolution runs, nothing is
        # spliced -- file is byte-identical to its pre-created state.
        assert output =~ "planned: inject #{path}"
        assert File.read!(path) == original_body
      else
        # Branch B, real: the anchor-resolution gate found the unique
        # marker line, spliced the rendered body immediately after it.
        assert output =~ "injected #{path}"
        new_body = File.read!(path)
        assert new_body != original_body
        assert new_body =~ @anchor
        assert new_body =~ "def injected_field, do: \"#{field}\""

        lines = String.split(new_body, "\n")
        anchor_idx = Enum.find_index(lines, &(&1 == @anchor))
        assert Enum.at(lines, anchor_idx + 1) =~ "def injected_field"
      end
    end
  end

  defp run_case!(fixtures, case_dir, %{mode: :file, inject: false} = combo) do
    modules =
      if combo.for_each,
        do: ["Agent6.Mod1", "Agent6.Mod2", "Agent6.Mod3"],
        else: ["Agent6.Single"]

    fields = if combo.for_each, do: ["field1", "field2", "field3"], else: ["single_field"]

    query_args =
      if combo.for_each,
        do: ["--query", "mods=#{fixtures.mods_rq}", "--for-each", "mods"],
        else: ["--query", "spec=#{fixtures.spec_rq}"]

    out_arg =
      if combo.for_each,
        do: [
          "--out",
          Path.join(case_dir, "<%= module_name |> String.replace(\"\\\"\", \"\") %>.ex")
        ],
        else: ["--out", Path.join(case_dir, "Agent6.Single.ex")]

    # Set up the write-guard precondition BEFORE the run under test, per
    # `guard_variant` -- `:none` starts from a target that does not exist
    # yet (the fresh-write case); `:unless_exists`/`:skip_if` start from a
    # deliberately pre-existing, DIFFERENT-content target (so a real
    # `:skipped_exists`/`:skipped_match` outcome, not an incidental
    # `:unchanged` byte-identity match, is what gets exercised).
    pre_contents =
      for module <- modules, into: %{} do
        path = Path.join(case_dir, module <> ".ex")

        content =
          case combo.guard_variant do
            :none ->
              nil

            :unless_exists ->
              body = "# PRE_EXISTING_CONTENT for #{module}\n"
              File.write!(path, body)
              body

            :skip_if ->
              body = "# AGENT6_SKIP_MARKER for #{module}\n"
              File.write!(path, body)
              body
          end

        {module, content}
      end

    guard_args =
      case combo.guard_variant do
        :none -> []
        :unless_exists -> ["--unless-exists"]
        :skip_if -> ["--skip-if", "AGENT6_SKIP_MARKER"]
      end

    args =
      [
        "--engine",
        combo.engine,
        "--ontology",
        fixtures.ontology,
        "--template",
        fixtures.file_plain
      ] ++ query_args ++ out_arg ++ guard_args ++ if(combo.dry_run, do: ["--dry-run"], else: [])

    {output, exit_code} = run_sync!(args)

    assert exit_code == 0, "mix ggen_igniter.sync failed (combo=#{inspect(combo)}):\n#{output}"

    for {module, field} <- Enum.zip(modules, fields) do
      path = Path.join(case_dir, module <> ".ex")
      pre_content = pre_contents[module]

      case {combo.guard_variant, combo.dry_run} do
        {:none, false} ->
          assert output =~ "wrote #{path}"
          assert File.read!(path) =~ "defmodule #{module} do"
          assert File.read!(path) =~ "def field_name, do: \"#{field}\""

        {:none, true} ->
          assert output =~ "planned: write #{path}"
          refute File.exists?(path)

        {:unless_exists, false} ->
          assert output =~ "skipped (unless_exists, already exists): #{path}"
          assert File.read!(path) == pre_content

        {:unless_exists, true} ->
          assert output =~ "planned: skip #{path} (unless_exists/skip_if match)"
          assert File.read!(path) == pre_content

        {:skip_if, false} ->
          assert output =~ "skipped (skip_if matched): #{path}"
          assert File.read!(path) == pre_content

        {:skip_if, true} ->
          assert output =~ "planned: skip #{path} (unless_exists/skip_if match)"
          assert File.read!(path) == pre_content
      end
    end
  end

  defp run_sync!(args, env \\ []) do
    System.cmd("mix", ["ggen_igniter.sync" | args],
      cd: File.cwd!(),
      stderr_to_stdout: true,
      env: env
    )
  end
end
