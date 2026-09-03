defmodule GgenIgniter.ArtifactIdentityPropertiesTest do
  @moduledoc """
  Chicago-style: real property-based testing via StreamData/ExUnitProperties
  against `GgenIgniter.ArtifactIdentity` -- a security-critical primitive
  (path-traversal / symlink-escape refusal, see its own moduledoc for the
  real, confirmed adversarial finding it closes). Every generator produces
  real strings fed into real `Path.expand/2`/`File` calls against a REAL
  per-test tmp directory on disk (`System.tmp_dir!()` +
  `System.unique_integer/1`, `File.rm_rf!/1` before and in `on_exit`, per
  `test/CLAUDE.md`'s required pattern) -- no mocking anywhere, and no oracle
  in this file re-implements `canonicalize/2`/`within_root?/2` themselves:
  the ground truth for property 1 is computed independently via a real
  `Path.expand/2` + `String.starts_with?/2` comparison. One real filesystem
  symlink (`File.ln_s!/2`) is created per property-1 run so the exact
  historical defect class this module's moduledoc documents (a symlinked
  escape route bypassing a purely-lexical root check) is exercised inside
  the generated-input sweep, not just the fixed-example test file.
  """

  use ExUnit.Case, async: true
  use ExUnitProperties

  alias GgenIgniter.ArtifactIdentity, as: AI

  defp scratch_dir!(tag) do
    dir =
      Path.join(
        System.tmp_dir!(),
        "ggen_igniter_artifact_identity_props_#{tag}_#{System.unique_integer([:positive])}"
      )

    File.rm_rf!(dir)
    File.mkdir_p!(dir)
    on_exit(fn -> File.rm_rf!(dir) end)
    dir
  end

  # A real safe leaf-file segment: alphanumeric, no path separators, no ".."
  # tokens of its own -- the thing an adversarial path is trying to reach.
  defp safe_segment_generator do
    StreamData.string(:alphanumeric, min_length: 1, max_length: 8)
  end

  # A real, benign intermediate directory segment (never "." or "..").
  defp safe_dir_segment_generator do
    StreamData.string(:alphanumeric, min_length: 1, max_length: 6)
  end

  # Builds an adversarial relative path string via real StreamData
  # combinators: a random number (0..6) of "../" traversal prefixes, real
  # "./"-noise interspersed, and a mix of real subdirectory segments before
  # the final safe leaf segment. Constructed with StreamData.bind/map --
  # never a hardcoded example list.
  defp adversarial_relative_path_generator do
    StreamData.bind(
      StreamData.tuple({
        StreamData.integer(0..6),
        StreamData.list_of(safe_dir_segment_generator(), max_length: 4),
        StreamData.boolean(),
        safe_segment_generator()
      }),
      fn {up_count, dir_segments, interleave_dot_noise?, leaf} ->
        up_segments = List.duplicate("..", up_count)

        middle =
          if interleave_dot_noise? do
            Enum.flat_map(dir_segments, fn seg -> [".", seg, "."] end)
          else
            dir_segments
          end

        parts = up_segments ++ middle ++ [leaf]

        StreamData.constant(Path.join(parts))
      end
    )
  end

  describe "within_root?/2 and canonicalize/2 (property): adversarial relative paths" do
    property "within_root?/2 agrees with an independently-computed Path.expand/2 + starts_with?/2 oracle" do
      check all(raw_path <- adversarial_relative_path_generator()) do
        base_dir = scratch_dir!("oracle_#{System.unique_integer([:positive])}")

        # Independent ground truth: NEVER calls canonicalize/2 or
        # within_root?/2 -- pure Path.expand/2 (lexical only) plus a real
        # string prefix check, exactly as the module under test describes
        # its own tier-1 semantics in its moduledoc.
        expanded_root = Path.expand(base_dir)
        expanded_candidate = Path.expand(raw_path, base_dir)

        expected_within? =
          expanded_candidate == expanded_root or
            String.starts_with?(expanded_candidate, expanded_root <> "/")

        actual_within? = AI.within_root?(base_dir, raw_path)

        assert actual_within? == expected_within?,
               "within_root?(#{inspect(base_dir)}, #{inspect(raw_path)}) returned " <>
                 "#{inspect(actual_within?)}, expected #{inspect(expected_within?)} " <>
                 "(lexically expanded candidate=#{inspect(expanded_candidate)}, " <>
                 "root=#{inspect(expanded_root)})"

        File.rm_rf!(base_dir)
      end
    end

    property "canonicalize/2 is idempotent: re-canonicalizing its own output returns the same string" do
      check all(raw_path <- adversarial_relative_path_generator()) do
        base_dir = scratch_dir!("idempotent_#{System.unique_integer([:positive])}")

        # canonicalize/2's real, documented contract (@spec String.t() ->
        # String.t()): it always returns an absolute path string, which is
        # itself a valid "raw_path" (already absolute, Path.expand/2 treats
        # an absolute path as self-relative regardless of base_dir) --
        # re-feedable as-is, no shape adjustment needed.
        once = AI.canonicalize(base_dir, raw_path)
        twice = AI.canonicalize(base_dir, once)

        assert is_binary(once)

        assert once == twice,
               "canonicalize/2 not idempotent for #{inspect(raw_path)}: " <>
                 "first=#{inspect(once)}, second=#{inspect(twice)}"

        File.rm_rf!(base_dir)
      end
    end

    property "a real symlink escaping the root is refused for every generated adversarial leaf" do
      check all(leaf <- safe_segment_generator()) do
        base_dir = scratch_dir!("symlink_escape_#{System.unique_integer([:positive])}")
        outside_dir = scratch_dir!("symlink_outside_#{System.unique_integer([:positive])}")

        # A REAL symlink inside base_dir pointing OUTSIDE base_dir -- the
        # exact historical defect class named in ArtifactIdentity's own
        # moduledoc ("a symlink whose real target lands outside the root").
        escape_link = Path.join(base_dir, "escape_link")
        File.ln_s!(outside_dir, escape_link)

        candidate = Path.join(escape_link, leaf)

        refute AI.within_root?(base_dir, candidate),
               "expected the real symlinked escape via #{inspect(candidate)} to be refused"

        File.rm_rf!(base_dir)
        File.rm_rf!(outside_dir)
      end
    end
  end

  # ===========================================================================
  # Real case-variant adversarial property (case-insensitive/case-preserving
  # filesystem defect: `walk_real_path/3` used to preserve each existing,
  # non-symlink segment's RAW caller-supplied spelling via
  # `Path.join(resolved, seg)` rather than querying the real on-disk entry
  # casing -- so two differently-cased spellings of the SAME real file (e.g.
  # "Foo.ex" vs "foo.ex" when only one of the two spellings really exists on
  # disk) canonicalized to two DIFFERENT strings on macOS default APFS/HFS+,
  # defeating :admit's duplicate-canonical-target dedup guard in
  # `GgenIgniter.Reactors.ReconcileReactor`.
  #
  # This property is REAL, not simulated: it writes one real mixed-case file
  # to a real per-test tmp directory, generates several real case-permuted
  # spellings of that file's own real path components via a StreamData
  # case-flip-per-character generator, and asserts `canonicalize/2` returns
  # the IDENTICAL canonical_target for every permutation. It first detects,
  # for REAL (never assumed from `:os.type/0`), whether the CURRENT test
  # runner's filesystem is actually case-insensitive by writing a real
  # mixed-case file and checking whether `File.exists?/1` on a different-case
  # spelling of that same path actually finds it -- skipping/guarding itself
  # honestly on a genuinely case-sensitive runner filesystem (Linux ext4,
  # etc.) rather than producing a false failure there.
  # ===========================================================================

  # Flips the case of each character independently with ~50% probability,
  # constrained to letters only (StreamData over a boolean-per-character
  # decision) -- a real generator, not a fixed permutation list, per the fix
  # request's "StreamData generator over case-flip-per-character is fine".
  defp case_flip_generator(original) when is_binary(original) do
    chars = String.graphemes(original)

    chars
    |> Enum.map(fn ch -> StreamData.tuple({StreamData.constant(ch), StreamData.boolean()}) end)
    |> StreamData.fixed_list()
    |> StreamData.map(fn pairs ->
      Enum.map_join(pairs, fn {ch, flip?} ->
        cond do
          not flip? -> ch
          ch =~ ~r/[a-z]/ -> String.upcase(ch)
          ch =~ ~r/[A-Z]/ -> String.downcase(ch)
          true -> ch
        end
      end)
    end)
  end

  # Detects, for REAL (writes a real mixed-case file and checks whether a
  # different-case spelling of the same real path is found via
  # `File.exists?/1`), whether the current test-runner filesystem is
  # case-insensitive -- never assumed from platform/OS name.
  defp filesystem_case_insensitive? do
    probe_dir =
      Path.join(
        System.tmp_dir!(),
        "ggen_igniter_artifact_identity_case_probe_#{System.unique_integer([:positive])}"
      )

    File.rm_rf!(probe_dir)
    File.mkdir_p!(probe_dir)

    mixed_case_path = Path.join(probe_dir, "CaseProbeFile.txt")
    other_case_path = Path.join(probe_dir, "caseprobefile.txt")
    File.write!(mixed_case_path, "probe")

    result = File.exists?(other_case_path)
    File.rm_rf!(probe_dir)
    result
  end

  describe "canonicalize/2 (property): real case-variant adversarial spellings" do
    property "every real case-permuted spelling of an existing file's path canonicalizes identically" do
      if filesystem_case_insensitive?() do
        check all(
                dir_seg <- StreamData.string(?a..?z, min_length: 3, max_length: 6),
                leaf_seg <- StreamData.string(?a..?z, min_length: 3, max_length: 6),
                max_runs: 20
              ) do
          base_dir = scratch_dir!("case_variant_#{System.unique_integer([:positive])}")
          real_dir = Path.join(base_dir, dir_seg)
          File.mkdir_p!(real_dir)

          real_file = Path.join(real_dir, "#{leaf_seg}.ex")
          File.write!(real_file, "defmodule CaseVariant, do: :ok")

          canonical = AI.canonicalize(base_dir, real_file)

          # A small fixed set of real, independently-constructed case
          # permutations of the SAME real path -- confirmed via
          # `File.exists?/1` to genuinely resolve to the same real file on
          # this (already-confirmed-case-insensitive) filesystem before
          # asserting anything about `canonicalize/2`.
          permutations = [
            Path.join(String.upcase(dir_seg), "#{leaf_seg}.ex"),
            Path.join(dir_seg, "#{String.upcase(leaf_seg)}.ex"),
            Path.join(String.upcase(dir_seg), "#{String.upcase(leaf_seg)}.ex"),
            Path.join(
              dir_seg |> String.graphemes() |> Enum.map_join(&String.upcase/1),
              "#{leaf_seg}.ex"
            )
          ]

          for rel_permutation <- permutations do
            permuted_absolute = Path.join(base_dir, rel_permutation)

            assert File.exists?(permuted_absolute),
                   "sanity: expected the OS itself to resolve #{inspect(permuted_absolute)} " <>
                     "to the same real file as #{inspect(real_file)} on this case-insensitive " <>
                     "filesystem"

            assert AI.canonicalize(base_dir, permuted_absolute) == canonical,
                   "expected case-variant spelling #{inspect(permuted_absolute)} to " <>
                     "canonicalize identically to #{inspect(canonical)} (real file " <>
                     "#{inspect(real_file)}), got #{inspect(AI.canonicalize(base_dir, permuted_absolute))}"
          end

          # A genuine, real StreamData case-flip-per-character permutation
          # of the full relative path, independently confirmed via
          # `File.exists?/1` before being asserted against `canonicalize/2`.
          check all(
                  flipped_dir <- case_flip_generator(dir_seg),
                  flipped_leaf <- case_flip_generator(leaf_seg),
                  max_runs: 10
                ) do
            flipped_absolute = Path.join([base_dir, flipped_dir, "#{flipped_leaf}.ex"])

            assert File.exists?(flipped_absolute),
                   "sanity: expected the OS to resolve the case-flipped spelling " <>
                     "#{inspect(flipped_absolute)} to the same real file"

            assert AI.canonicalize(base_dir, flipped_absolute) == canonical,
                   "expected case-flipped spelling #{inspect(flipped_absolute)} to " <>
                     "canonicalize identically to #{inspect(canonical)}"
          end

          File.rm_rf!(base_dir)
        end
      else
        IO.puts(
          "\n[skip] case-variant property: this test runner's filesystem is genuinely " <>
            "case-sensitive (confirmed via a real File.exists?/1 probe, not assumed from " <>
            "platform) -- two differently-cased spellings really ARE different files here, " <>
            "so this macOS/APFS-specific property does not apply."
        )

        assert true
      end
    end
  end
end
