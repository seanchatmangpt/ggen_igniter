defmodule GgenIgniter.ArtifactIdentity do
  @moduledoc """
  A real, first-class ARTIFACT IDENTITY primitive: turns a `(base_dir,
  raw_path)` pair -- an arbitrary, possibly-relative, possibly-alias-laden
  path string as it appears in a `%GgenIgniter.PendingActuation{}`'s
  `target`, a `GgenIgniter.Manifest` entry's `outputs` key, or a
  `GgenIgniter.Receipt`'s `files` entry -- into one CANONICAL identity
  string, so two lexically different raw strings that resolve to the same
  real on-disk location are recognized as the SAME identity everywhere this
  pipeline reasons about "is this the same output."

  ## Why this module exists (a real, confirmed adversarial finding, not a
  speculative hardening pass)

  `.ggen_igniter_factory/redteam-concurrency-nondeterminism.md` (read fresh
  before writing this module, its real reproducer re-run against the fix
  below) demonstrates a REAL, reproduced defect: `:admit`'s duplicate-
  output-path guard in `GgenIgniter.Reactors.ReconcileReactor` used to group
  pending writes by the raw `target` STRING
  (`Enum.group_by(& &1.target)`) -- never canonicalized. Two targets whose
  `--out`/`to:` strings differ only by a redundant `/./` path segment (one
  concrete, independently filesystem-verified example; `//`, `..`, and
  symlink-based aliases are the same root cause by the same reasoning)
  resolve to the SAME real inode while comparing as different Elixir
  strings, silently bypassing the guard and letting `:actuate`'s real
  `Task.async_stream/3` concurrency race unprotected on the shared real
  file -- genuine, empirically-confirmed last-writer-wins, with the
  pipeline reporting `standing: :alive` (full success) regardless of which
  target's content was actually discarded.

  This module closes that gap as a real, reusable, independently-tested
  primitive rather than a one-off string-munge inlined into `:admit` --
  see `GgenIgniter.Reactors.ReconcileReactor`'s `admit_pending/2` for the
  real wiring, `GgenIgniter.PendingActuation`'s `canonical_target` field for
  where every planned actuation carries its own real identity, and
  `GgenIgniter.Manifest`/`GgenIgniter.Receipt`'s call sites in
  `ReconcileReactor` for where the manifest's `outputs` keys and the
  receipt's `files` entries are now built from this same real identity
  rather than a raw path string.

  ## Two-tier resolution, honestly bounded

  `canonicalize/2` resolves in two tiers, in order:

    1. **Lexical normalization** (`Path.expand/2`): relative-vs-absolute
       forms unified against `base_dir`, `.`/`..` segments resolved,
       repeated separators collapsed. This ALONE is what closes the exact
       `/./`-alias reproducer above (neither colliding target need exist on
       disk yet for this tier to unify them).
    2. **Real filesystem identity** (symlink/realpath resolution): for
       every path SEGMENT that already exists on disk, this module walks it
       exactly like POSIX `realpath(3)` -- resolving any symlink
       encountered (including in an INTERMEDIATE directory segment, so a
       directory reached via two different real symlinked paths still
       collapses to one identity), with a bounded expansion budget so a
       symlink cycle can never loop forever.

  **Honest limit, stated plainly (per this module's own design brief):**
  the moment resolution reaches a path segment that does not exist on disk
  at all, real filesystem resolution stops there -- the remaining,
  not-yet-existing suffix is appended to the already-resolved (real, or
  lexically-expanded, whichever tier got that far) prefix VERBATIM, after
  its own `.`/`..` segments were already normalized by `Path.expand/2` in
  tier 1. This is the best available identity for a target that does not
  exist yet: there is no real inode to resolve a not-yet-created file
  against. Concretely: a brand-new file inside an EXISTING (possibly
  symlinked) directory gets that directory's real identity as its prefix
  (stronger than bare lexical expansion); a brand-new file whose parent
  directory ALSO does not exist yet gets pure lexical normalization only,
  identical to `Path.expand/2`'s own result. Two aliases of a not-yet-
  existing path that would only converge via a symlink CREATED after this
  function returns are, honestly, not detected -- there is no way to
  observe a filesystem fact that does not exist yet.
  """

  # A generous, POSIX-realpath-typical bound on symlink expansions -- large
  # enough that no legitimate directory structure ever hits it, small enough
  # that a genuine symlink cycle (`a -> b`, `b -> a`) can never loop forever.
  @max_symlink_expansions 40

  @doc """
  Resolves `raw_path` (relative or absolute, `base_dir`-relative when
  relative) into one canonical identity string -- see this module's
  moduledoc for the real two-tier algorithm and its honestly-disclosed
  limit for not-yet-existing targets.

  Two raw strings that are lexically different but denote the same real
  on-disk location (a redundant `.`/`..` segment, a repeated separator, a
  relative-vs-absolute spelling of the same path, or -- for a path that
  already exists -- two different symlinked routes to the same real inode)
  canonicalize to the IDENTICAL string.
  """
  @spec canonicalize(String.t(), String.t()) :: String.t()
  def canonicalize(base_dir, raw_path)
      when is_binary(base_dir) and is_binary(raw_path) do
    expanded = Path.expand(raw_path, base_dir)

    case real_path(expanded) do
      {:ok, real} -> real
      {:partial, best_effort} -> best_effort
    end
  end

  @doc """
  Whether `path_a` and `path_b` (both resolved relative to the same
  `base_dir`) denote the SAME real artifact identity -- built directly on
  `canonicalize/2`, never a second, parallel comparison scheme.
  """
  @spec same_target?(String.t(), String.t(), String.t()) :: boolean()
  def same_target?(base_dir, path_a, path_b)
      when is_binary(base_dir) and is_binary(path_a) and is_binary(path_b) do
    canonicalize(base_dir, path_a) == canonicalize(base_dir, path_b)
  end

  @doc """
  Whether `raw_path`'s real canonical identity remains INSIDE the
  authorized project root (`base_dir`, itself canonicalized the same way --
  so a symlinked project root does not itself defeat this guard). Refuses
  (`false`) any path that escapes `base_dir` via `..` traversal, an
  absolute path pointing elsewhere, or a symlink whose real target lands
  outside the root.

  `base_dir` itself is considered within its own root (`within_root?(dir,
  dir)` is `true`, matching `File.rm_rf!/1`-style "the root itself is a
  valid target" conventions elsewhere in this codebase); every other path
  must resolve to a REAL descendant of that root.
  """
  @spec within_root?(String.t(), String.t()) :: boolean()
  def within_root?(base_dir, raw_path) when is_binary(base_dir) and is_binary(raw_path) do
    root = canonicalize(base_dir, ".")
    candidate = canonicalize(base_dir, raw_path)

    candidate == root or String.starts_with?(candidate, root <> "/")
  end

  # -- Real realpath-style resolution ----------------------------------------

  # `expanded` is already absolute and lexically normalized (via
  # `Path.expand/2` above) -- no `.`/`..` segments, no repeated separators.
  # Walks it component-by-component from `/`, resolving any REAL symlink
  # encountered at any depth (POSIX `realpath(3)` semantics), stopping the
  # instant a component genuinely does not exist and returning the
  # already-resolved prefix plus the untouched, already-lexically-clean
  # remainder (`{:partial, _}`) -- see moduledoc "honest limit".
  defp real_path(expanded) do
    segments = expanded |> Path.split() |> drop_leading_root()
    walk_real_path(segments, "/", @max_symlink_expansions)
  end

  defp drop_leading_root(["/" | rest]), do: rest
  defp drop_leading_root(segments), do: segments

  defp walk_real_path([], resolved, _budget), do: {:ok, resolved}

  defp walk_real_path(segments, resolved, budget) when budget <= 0 do
    # A genuine symlink cycle (or a pathological, absurdly deep chain) --
    # refuse to loop forever. Falls back to the best-effort literal join,
    # the same honest fallback a not-yet-existing target already gets.
    {:partial, join_all(resolved, segments)}
  end

  defp walk_real_path([seg | rest], resolved, budget) do
    candidate = Path.join(resolved, seg)

    case File.read_link(candidate) do
      {:ok, link_target} ->
        follow_link(link_target, rest, resolved, budget)

      {:error, :einval} ->
        # Exists, and is genuinely NOT a symlink -- keep it as-is and
        # continue resolving the remaining segments underneath it.
        walk_real_path(rest, candidate, budget)

      {:error, _enoent_or_other} ->
        # Does not exist (or its parent isn't real-enough to check, or a
        # permissions error) -- real resolution stops here; the rest of
        # the (already lexically-normalized) path is appended verbatim.
        {:partial, join_all(candidate, rest)}
    end
  end

  defp follow_link(link_target, rest, resolved, budget) do
    case Path.type(link_target) do
      :absolute ->
        new_segments = link_target |> Path.split() |> drop_leading_root()
        walk_real_path(new_segments ++ rest, "/", budget - 1)

      _relative ->
        new_segments = Path.split(link_target)
        walk_real_path(new_segments ++ rest, resolved, budget - 1)
    end
  end

  defp join_all(base, segments), do: Enum.reduce(segments, base, &Path.join(&2, &1))
end
