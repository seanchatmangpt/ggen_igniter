defmodule GgenIgniter.FullPipelinePropertiesTest do
  @moduledoc """
  Real, combinatorial, Chicago-style property tests for the COMPOSED
  `GgenIgniter.Frontmatter.split_template/1` -> `GgenIgniter.Render.render/2`
  -> `GgenIgniter.Actuate.write_file!/3` pipeline -- as opposed to
  `test/ggen_igniter_frontmatter_properties_test.exs` and
  `test/ggen_igniter_actuate_properties_test.exs`, which already exercise
  each of those two modules in isolation. This file's properties fail (and
  would only fail) if something about the COMPOSITION corrupts data or
  breaks an invariant that holds for each module alone -- e.g. a body that
  survives `split_template/1` unchanged but gets mangled by `render/2`, or a
  `to`/`unless_exists` field that round-trips through `from_map/1` but gets
  lost on the way to `write_file!/3`'s `opts`.

  No mocking anywhere: every run uses a real temp directory, real
  `File.write!/2`/`File.read!/1` calls (via the real `Actuate.write_file!/3`),
  and the real `EEx.eval_string/2` (via the real `Render.render/2`) --
  per `~/.claude/rules/testing-chicago-style.md`.

  ## Real constraints verified against the actual source before writing this
  file (not assumed)

  - `Frontmatter.split_template/1`'s closing-fence match is
    `String.split(rest, "\\n---\\n", parts: 2)` -- it splits on only the
    FIRST occurrence of the literal `"\\n---\\n"` sequence in `rest` (the
    text after the opening `"---\\n"` line), and everything after that first
    occurrence becomes the body unchanged, even if the body itself contains
    further `"\\n---\\n"` sequences. Empirically verified:

        iex> String.split("to: 1\\n---\\nabc\\n---\\ndef", "\\n---\\n", parts: 2)
        ["to: 1", "abc\\n---\\ndef"]

    So, strictly, a body containing `"\\n---\\n"` would NOT break this
    pipeline given the single-line, dash-free YAML block this test
    generates (the first occurrence is always the boundary we inserted).
    This test still filters `"\\n---\\n"` out of the generated body anyway,
    per the task's own instruction, to keep the composed pipeline's
    "expected output" trivially checkable (`rendered == body`, full stop)
    without leaning on the first-occurrence subtlety -- a narrower domain
    than what was shown safe, chosen deliberately, not out of an unverified
    assumption. (`test/ggen_igniter_frontmatter_properties_test.exs`
    documents this same empirical finding independently.)

  - `Render.render/2` is `EEx.eval_string(template_string, bindings)`. `EEx`
    only opens a tag on the literal `"<%"` sequence; text containing neither
    `"<%"` nor `"%>"` is passed through as a literal, unevaluated string.
    This test filters both sequences out of the generated body, so
    `Render.render(body, [])` is a true identity function on that body for
    every case this test generates -- verified empirically while writing
    this test (`EEx.eval_string("plain % text > no tags", [])` returns the
    input unchanged).

  - `Actuate.write_file!/3`'s decision table (first match wins):
    `unless_exists: true && exists -> :skipped_exists`, then
    `skip_if && match -> :skipped_match` (not exercised here -- this
    pipeline never sets `skip_if`), then
    `exists && existing == content -> :unchanged`, else `:written`. Because
    `unless_exists: true` is checked BEFORE the byte-identity check, a
    composed-pipeline rerun with `unless_exists: true` against an
    already-written file yields `:skipped_exists`, NOT `:unchanged` --
    the property below (`re-running the exact same pipeline`) branches on
    the generated `unless_exists` boolean precisely to assert the REAL
    outcome for both cases, rather than asserting `:unchanged`
    unconditionally (which would be false whenever `unless_exists: true`
    was generated) or silently narrowing the generator to `unless_exists:
    false` (which would under-test the composed decision table).
  """

  use ExUnit.Case, async: true
  use ExUnitProperties

  alias GgenIgniter.{Actuate, Frontmatter, Render}

  setup do
    tmp_dir =
      Path.join(
        System.tmp_dir!(),
        "ggen_igniter_full_pipeline_properties_test_#{System.unique_integer([:positive])}"
      )

    File.rm_rf!(tmp_dir)
    File.mkdir_p!(tmp_dir)
    on_exit(fn -> File.rm_rf!(tmp_dir) end)
    {:ok, tmp_dir: tmp_dir}
  end

  # ---------------------------------------------------------------------
  # Generators
  # ---------------------------------------------------------------------

  # `to:` values: alphanumeric + underscore only, no "/" and no ".." -- safe
  # as both a bare (unquoted) YAML scalar and a single filesystem path
  # segment, per the task spec.
  defp filename_gen do
    StreamData.string([?a..?z, ?A..?Z, ?0..?9, ?_], min_length: 1, max_length: 20)
  end

  # Plain-text body: printable, no EEx tag delimiters (so render/2 is a pure
  # identity pass-through), no literal frontmatter-closing fence (see
  # moduledoc for why this is a deliberately narrower-than-necessary filter,
  # not an unverified assumption).
  defp body_gen do
    StreamData.string(:printable, max_length: 200)
    |> StreamData.filter(fn body ->
      not String.contains?(body, "<%") and
        not String.contains?(body, "%>") and
        not String.contains?(body, "\n---\n")
    end)
  end

  # A fresh, never-yet-touched directory under `tmp_dir`, unique per
  # generator iteration, so that random (or even colliding) `to:` filenames
  # generated across DIFFERENT `check all` iterations never collide with
  # each other's leftover files -- only a DELIBERATE reuse of the same
  # directory within a single iteration (the collision property below)
  # creates a real collision.
  defp fresh_dir(tmp_dir) do
    dir = Path.join(tmp_dir, "case_#{System.unique_integer([:positive])}")
    File.mkdir_p!(dir)
    dir
  end

  # `to` is emitted as a DOUBLE-QUOTED YAML scalar, not bare. Verified
  # empirically while writing this test: a bare (unquoted) numeric-looking
  # `to:` value such as "0" or "123" -- both valid outputs of filename_gen/0,
  # since digits are alphanumeric -- is resolved by YamlElixir's YAML 1.1
  # implicit typing to an INTEGER, not a string (`to: 0` parses to the
  # integer `0`, so `Frontmatter.from_map/1`'s `fm.to` would be `0`, failing
  # `fm.to == "0"`). This is a real YAML-scalar-typing artifact of how this
  # test serializes the generated `to` string into a frontmatter block, not
  # a defect in `Frontmatter`/`Render`/`Actuate` themselves -- quoting is the
  # correct fix (it forces the YAML string type for every value in
  # filename_gen/0's alphanumeric+underscore domain, including bareword
  # collisions like "true"/"null"/"yes" as well as digit-only names),
  # applied here rather than narrowing the generator away from the digits
  # the task explicitly asked to include ("alphanumeric+underscore").
  defp yaml_for(to, unless_exists), do: ~s(to: "#{to}") <> "\nunless_exists: #{unless_exists}"

  defp template_for(to, unless_exists, body),
    do: "---\n" <> yaml_for(to, unless_exists) <> "\n---\n" <> body

  # The real composed pipeline under test: split_template/1 -> render/2
  # (empty bindings) -> write_file!/3, using the parsed frontmatter's own
  # `to`/`unless_exists` fields (never the generator's raw values directly)
  # to resolve the write target and guard options -- proving those fields
  # actually flow end to end through the real structs, not just that the
  # generator's values happen to match.
  defp run_pipeline!(dir, to, unless_exists, body) do
    template = template_for(to, unless_exists, body)

    {fm, mode, rendered_source} = Frontmatter.split_template(template)

    assert %Frontmatter{} = fm
    assert fm.to == to
    assert fm.unless_exists == unless_exists
    assert mode == :file

    rendered = Render.render(rendered_source, [])
    assert rendered == body

    path = Path.join(dir, fm.to)
    outcome = Actuate.write_file!(path, rendered, unless_exists: fm.unless_exists)

    %{path: path, outcome: outcome}
  end

  # ---------------------------------------------------------------------
  # Property 1 + 2: fresh write is byte-identical, and a same-pipeline
  # rerun is idempotent per the REAL decision table (branches on the
  # generated unless_exists boolean instead of asserting one outcome).
  # ---------------------------------------------------------------------

  property "composed pipeline: fresh write is byte-identical, and a same-pipeline rerun " <>
             "reproduces write_file!/3's real decision table without corrupting disk content",
           %{tmp_dir: tmp_dir} do
    check all(
            to <- filename_gen(),
            unless_exists <- StreamData.boolean(),
            body <- body_gen(),
            max_runs: 50
          ) do
      dir = fresh_dir(tmp_dir)

      # First run: target is fresh, so unless_exists is moot (exists? is
      # false) regardless of its value -- must always be :written, and the
      # real on-disk content must be byte-identical to the generated body.
      %{path: path, outcome: first_outcome} = run_pipeline!(dir, to, unless_exists, body)

      assert first_outcome == {:ok, :written}
      assert File.read!(path) == body

      # Second run: the exact same template through the exact same
      # pipeline, against the now-existing file. write_file!/3 checks
      # unless_exists BEFORE the byte-identity branch, so the real outcome
      # depends on the generated unless_exists boolean -- assert the real
      # branch, not a single hardcoded expectation.
      %{path: ^path, outcome: second_outcome} = run_pipeline!(dir, to, unless_exists, body)

      if unless_exists do
        assert second_outcome == {:ok, :skipped_exists}
      else
        assert second_outcome == {:ok, :unchanged}
      end

      # Either way, the file's real content must be untouched/unchanged --
      # still byte-identical to the original generated body.
      assert File.read!(path) == body
    end
  end

  # ---------------------------------------------------------------------
  # Property 3: unless_exists: true against a DELIBERATELY colliding
  # filename from a prior, DIFFERENT generated case -- not relying on
  # random collision. Proves :skipped_exists and that the ORIGINAL content
  # (from the first, different case) survives untouched.
  # ---------------------------------------------------------------------

  property "composed pipeline: unless_exists: true skips a write onto a deliberately " <>
             "colliding filename from a prior, different generated case, leaving its " <>
             "content untouched",
           %{tmp_dir: tmp_dir} do
    check all(
            to <- filename_gen(),
            first_body <- body_gen(),
            second_body <- body_gen(),
            first_body != second_body,
            max_runs: 50
          ) do
      dir = fresh_dir(tmp_dir)

      # Prior generated case: a normal, unless_exists: false write that
      # creates the file for the first time.
      %{path: path, outcome: prior_outcome} =
        run_pipeline!(dir, to, false, first_body)

      assert prior_outcome == {:ok, :written}
      assert File.read!(path) == first_body

      # Second generated case: SAME `to` (deliberate filename collision,
      # constructed here rather than left to chance), unless_exists: true,
      # and DIFFERENT body content.
      %{path: ^path, outcome: second_outcome} =
        run_pipeline!(dir, to, true, second_body)

      assert second_outcome == {:ok, :skipped_exists}

      # The real file on disk must still hold the PRIOR case's content,
      # completely untouched by the second (colliding, unless_exists: true)
      # pipeline run.
      assert File.read!(path) == first_body
    end
  end
end
