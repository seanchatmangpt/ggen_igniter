defmodule GgenIgniter.PendingActuationPropertiesTest do
  @moduledoc """
  Chicago-style: pure-function property testing against real generated
  inputs, no mocking. `logical_id/3` and `plan_unchanged?/1` are exercised
  as pure functions over generated strings/structs; `for_file/7` is
  exercised against a REAL temp directory on disk (real `File.exists?/1`,
  `File.read!/1`, `File.write!/2` -- never faked), following this repo's
  `test/CLAUDE.md` tmp-dir setup pattern (copied from `actuate_test.exs`).
  """

  use ExUnit.Case, async: true
  use ExUnitProperties

  alias GgenIgniter.{Manifest, PendingActuation}

  defp scratch_dir!(tag) do
    dir =
      Path.join(
        System.tmp_dir!(),
        "ggen_igniter_pending_actuation_props_#{tag}_#{System.unique_integer([:positive])}"
      )

    File.rm_rf!(dir)
    File.mkdir_p!(dir)
    on_exit(fn -> File.rm_rf!(dir) end)
    dir
  end

  defp safe_filename_generator do
    StreamData.string(:alphanumeric, min_length: 1, max_length: 20)
  end

  defp safe_string_generator do
    StreamData.string(:alphanumeric, min_length: 0, max_length: 40)
  end

  describe "logical_id/3 (pure)" do
    property "is deterministic for the same inputs" do
      check all(
              template_path <- safe_string_generator(),
              out_template <- safe_string_generator(),
              target <- safe_string_generator()
            ) do
        id1 = PendingActuation.logical_id(template_path, out_template, target)
        id2 = PendingActuation.logical_id(template_path, out_template, target)
        assert id1 == id2
      end
    end

    property "changes when target changes but (template_path, out_template) stay fixed" do
      check all(
              template_path <- safe_string_generator(),
              out_template <- safe_string_generator(),
              target_a <- safe_string_generator(),
              target_b <- safe_string_generator(),
              target_a != target_b
            ) do
        id_a = PendingActuation.logical_id(template_path, out_template, target_a)
        id_b = PendingActuation.logical_id(template_path, out_template, target_b)
        assert id_a != id_b
      end
    end
  end

  describe "plan_unchanged?/1 (pure)" do
    defp build_pending_actuation(previous_hash, desired_hash) do
      %PendingActuation{
        logical_id: "props::logical_id",
        operation: :replace,
        ownership: true,
        semantic_source: %{},
        compensation_data: :did_not_exist,
        previous_hash: previous_hash,
        desired_hash: desired_hash
      }
    end

    property "is true iff previous_hash == desired_hash and both non-nil" do
      hash_generator = StreamData.string(:alphanumeric, min_length: 1, max_length: 16)

      check all(
              previous_hash <- StreamData.one_of([StreamData.constant(nil), hash_generator]),
              desired_hash <- StreamData.one_of([StreamData.constant(nil), hash_generator])
            ) do
        pa = build_pending_actuation(previous_hash, desired_hash)

        expected =
          not is_nil(previous_hash) and not is_nil(desired_hash) and previous_hash == desired_hash

        assert PendingActuation.plan_unchanged?(pa) == expected
      end
    end

    property "is always true for a real equal-hash pair (both non-nil)" do
      check all(hash <- StreamData.string(:alphanumeric, min_length: 1, max_length: 16)) do
        pa = build_pending_actuation(hash, hash)
        assert PendingActuation.plan_unchanged?(pa)
      end
    end

    property "is always false when hashes differ" do
      check all(
              hash_a <- StreamData.string(:alphanumeric, min_length: 1, max_length: 16),
              hash_b <- StreamData.string(:alphanumeric, min_length: 1, max_length: 16),
              hash_a != hash_b
            ) do
        pa = build_pending_actuation(hash_a, hash_b)
        refute PendingActuation.plan_unchanged?(pa)
      end
    end
  end

  describe "for_file/7 (real temp file on disk)" do
    property "target does not exist yet -> operation is always :create, previous_hash is always nil" do
      check all(
              filename <- safe_filename_generator(),
              desired_content <- safe_string_generator()
            ) do
        tmp_dir = scratch_dir!("create_#{System.unique_integer([:positive])}")
        target = Path.join(tmp_dir, filename)

        refute File.exists?(target)

        pa =
          PendingActuation.for_file(
            tmp_dir,
            target,
            desired_content,
            "template.eex",
            target,
            nil,
            %{}
          )

        assert pa.operation == :create
        assert pa.previous_hash == nil
        assert pa.desired_hash == Manifest.hash_content(desired_content)
        assert pa.compensation_data == :did_not_exist

        File.rm_rf!(tmp_dir)
      end
    end

    property "target already exists with real content -> operation is always :replace, previous_hash is always the real prior content's hash" do
      check all(
              filename <- safe_filename_generator(),
              prior_content <- safe_string_generator(),
              desired_content <- safe_string_generator()
            ) do
        tmp_dir = scratch_dir!("replace_#{System.unique_integer([:positive])}")
        target = Path.join(tmp_dir, filename)

        File.write!(target, prior_content)
        assert File.exists?(target)

        pa =
          PendingActuation.for_file(
            tmp_dir,
            target,
            desired_content,
            "template.eex",
            target,
            nil,
            %{}
          )

        assert pa.operation == :replace
        assert pa.previous_hash == Manifest.hash_content(prior_content)
        assert pa.desired_hash == Manifest.hash_content(desired_content)
        assert pa.compensation_data == {:previous_content, prior_content}

        File.rm_rf!(tmp_dir)
      end
    end
  end
end
