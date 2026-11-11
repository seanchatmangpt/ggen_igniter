defmodule GgenIgniter.Review.Perspectives.EpochLaw do
  @moduledoc """
  Epoch-law perspective — the closed verdict set of the epoch boundary
  (`CLAUDE.md` epoch section, `GgenIgniter.EpochFreshness`): every
  implementation-plane hunk (`lib/**/*.ex`) in the diff needs attribution —
  a post-watermark alive receipt, a `HANDWRITTEN.md` residue row, or an
  explicit epoch-plan admission. An unattributed `lib/**/*.ex` hunk is the
  `REFUSED_NO_ATTRIBUTION` / `REFUSED_LEGACY_EDIT` class surfacing at review
  time.

  Mechanism: this perspective parses the diff's `+++ b/<path>` headers, and
  for every file matching `lib/**/*.ex` that carries at least one added line,
  requires an attribution entry in `opts[:attributions]` — a map of
  `%{file => attribution}` where attribution is any non-nil term (caller
  passes real provenance: receipt paths, watermark rows). A `lib/**/*.ex`
  file with added lines and no attribution entry yields a class `:epoch_law`
  finding. No other file plane is judged (knowledge/evidence planes are
  exempt per the epoch law).
  """

  @behaviour GgenIgniter.Review.Perspective

  alias GgenIgniter.Review.Finding

  @impl true
  def review_diff(diff_text, opts) do
    attributions = opts |> Keyword.get(:attributions, %{}) |> Enum.into(%{})

    diff_text
    |> changed_implementation_files()
    |> Enum.reject(&Map.has_key?(attributions, &1))
    |> Enum.map(fn file ->
      Finding.new(
        file: file,
        line: 1,
        class: :epoch_law,
        severity: :important,
        summary:
          "implementation-plane file (lib/**/*.ex) has diff hunks but no epoch attribution",
        perspective: :epoch_law
      )
    end)
  end

  @doc "Distinct lib/**/*.ex file paths that carry at least one added line in the diff."
  @spec changed_implementation_files(String.t()) :: [String.t()]
  def changed_implementation_files(diff_text) do
    diff_text
    |> GgenIgniter.Review.Perspectives.Invariants.added_lines()
    |> Enum.map(fn {file, _line, _text} -> file end)
    |> Enum.uniq()
    |> Enum.filter(&implementation_plane?/1)
  end

  defp implementation_plane?(path) do
    String.starts_with?(path, "lib/") and String.ends_with?(path, ".ex")
  end
end
