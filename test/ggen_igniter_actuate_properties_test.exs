defmodule GgenIgniter.ActuatePropertiesTest do
  @moduledoc """
  Property-based tests for `GgenIgniter.Actuate.write_file!/3`'s write-safety
  decision table, using real StreamData-generated file content against a REAL
  temp directory and REAL `File` reads/writes -- Chicago-style, no mocking of
  the filesystem, per this project's testing convention
  (`~/.claude/rules/testing-chicago-style.md`).

  Decision order under test (first match wins), copied from
  `GgenIgniter.Actuate.write_file!/3`'s own moduledoc:

    1. `unless_exists: true` && target exists       -> `:skipped_exists`
    2. `skip_if: pattern` && target exists && match  -> `:skipped_match`
    3. target exists && content byte-identical       -> `:unchanged`
    4. otherwise                                     -> `:written`
  """
  use ExUnit.Case, async: true
  use ExUnitProperties

  alias GgenIgniter.Actuate

  setup do
    tmp_dir =
      Path.join(
        System.tmp_dir!(),
        "ggen_igniter_actuate_properties_test_#{System.unique_integer([:positive])}"
      )

    File.mkdir_p!(tmp_dir)
    on_exit(fn -> File.rm_rf!(tmp_dir) end)
    {:ok, tmp_dir: tmp_dir}
  end

  # A fresh, never-yet-touched nested path under `tmp_dir`, unique per
  # generator run so consecutive `check all` iterations never collide with
  # each other's leftover files/dirs. The nesting (two extra path segments
  # neither of which exist yet) lets the dry_run property assert that
  # `File.mkdir_p!/1` itself was never invoked, not just `File.write!/2`.
  defp fresh_path(tmp_dir) do
    n = System.unique_integer([:positive])
    Path.join([tmp_dir, "case_#{n}", "nested", "file_#{n}.ex"])
  end

  defp content_gen, do: StreamData.string(:printable, min_length: 0, max_length: 80)

  # Non-empty, alphanumeric-only marker used to build `skip_if` patterns --
  # kept simple so the same literal string is meaningful both as a plain
  # substring and (once `Regex.escape/1`d) as a regex source.
  defp marker_gen, do: StreamData.string(:alphanumeric, min_length: 1, max_length: 12)

  describe "property: idempotency (no guards)" do
    property "writing identical content twice in a row always yields :written then :unchanged",
             %{tmp_dir: tmp_dir} do
      check all(content <- content_gen(), max_runs: 100) do
        path = fresh_path(tmp_dir)
        refute File.exists?(path)

        assert {:ok, :written} = Actuate.write_file!(path, content)
        assert File.read!(path) == content

        assert {:ok, :unchanged} = Actuate.write_file!(path, content)
        assert File.read!(path) == content
      end
    end
  end

  describe "property: unless_exists" do
    property "always :skipped_exists when target exists, regardless of new content, " <>
               "and never modifies the existing file",
             %{tmp_dir: tmp_dir} do
      check all(
              existing_content <- content_gen(),
              new_content <- content_gen(),
              max_runs: 100
            ) do
        path = fresh_path(tmp_dir)
        File.mkdir_p!(Path.dirname(path))
        File.write!(path, existing_content)

        assert {:ok, :skipped_exists} =
                 Actuate.write_file!(path, new_content, unless_exists: true)

        assert File.read!(path) == existing_content
      end
    end
  end

  describe "property: skip_if precedence over the byte-comparison (:unchanged) branch" do
    property "always :skipped_match when existing content matches, whether new content " <>
               "is identical to or differs from it -- skip_if gates before equality",
             %{tmp_dir: tmp_dir} do
      check all(
              marker <- marker_gen(),
              filler <- content_gen(),
              use_regex? <- StreamData.boolean(),
              max_runs: 100
            ) do
        existing_content = filler <> marker
        path = fresh_path(tmp_dir)
        File.mkdir_p!(Path.dirname(path))
        File.write!(path, existing_content)

        pattern =
          if use_regex? do
            Regex.compile!(Regex.escape(marker))
          else
            marker
          end

        # Case A: new content byte-identical to existing -- would be
        # :unchanged (decision branch 3) if skip_if (branch 2) did not
        # short-circuit first.
        assert {:ok, :skipped_match} =
                 Actuate.write_file!(path, existing_content, skip_if: pattern)

        assert File.read!(path) == existing_content

        # Case B: new content differs from existing -- would be :written
        # (decision branch 4) if skip_if did not short-circuit first. The
        # match is evaluated against the file's real on-disk content, not
        # the incoming content, so this must still be :skipped_match.
        differing_content = existing_content <> "_definitely_different"
        refute differing_content == existing_content

        assert {:ok, :skipped_match} =
                 Actuate.write_file!(path, differing_content, skip_if: pattern)

        assert File.read!(path) == existing_content
      end
    end
  end

  describe "property: dry_run never touches the filesystem" do
    property "never calls File.write!/2 or File.mkdir_p!/1 regardless of computed " <>
               "outcome, including :written",
             %{tmp_dir: tmp_dir} do
      check all(
              content <- content_gen(),
              unless_exists? <- StreamData.boolean(),
              pre_create? <- StreamData.boolean(),
              max_runs: 100
            ) do
        path = fresh_path(tmp_dir)
        parent = Path.dirname(path)

        if pre_create? do
          File.mkdir_p!(parent)
          File.write!(path, "pre-existing sentinel content")
        end

        file_existed_before = File.exists?(path)
        dir_existed_before = File.dir?(parent)
        content_before = if file_existed_before, do: File.read!(path), else: nil

        assert {:ok, outcome} =
                 Actuate.write_file!(path, content, unless_exists: unless_exists?, dry_run: true)

        assert outcome in [:written, :unchanged, :skipped_exists, :skipped_match]

        # The core claim: no matter what outcome was computed (in
        # particular :written, the branch that would otherwise call
        # File.mkdir_p!/1 + File.write!/2), a target that did not exist
        # before must still not exist after, and its parent directory must
        # still not have been created.
        assert File.exists?(path) == file_existed_before
        assert File.dir?(parent) == dir_existed_before

        if file_existed_before do
          assert File.read!(path) == content_before
        end
      end
    end
  end
end
