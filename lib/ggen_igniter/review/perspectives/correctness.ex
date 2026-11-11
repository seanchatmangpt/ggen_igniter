defmodule GgenIgniter.Review.Perspectives.Correctness do
  @moduledoc """
  Correctness perspective — the 6 ggen-reviewer surfaces
  (`.claude/agents/ggen-reviewer.md`): (1) reconciliation-manifest staleness,
  (2) Reactor admission/compensation invariants, (3) cross-engine divergence,
  (4) frontmatter/injection, (5) Chicago-testing discipline, (6)
  `docs/status.md` alignment.

  Agent execution is out of scope: this module consumes structured findings
  produced upstream — the reviewer agent's structured output, passed via
  `opts[:findings]` as a list of maps with `:file`, `:line`, `:summary`, an
  optional `:severity` (`:blocker`/`:major` map to `:important`, `:minor` to
  `:nit`), and a `:surface` in 1..6 — and projects each into a Finding pinned
  to class `:correctness`.

  Fail-closed on malformed input: a surface outside 1..6, or a missing
  required key, raises `ArgumentError` naming the entry. A bad structured
  finding never silently disappears.
  """

  @behaviour GgenIgniter.Review.Perspective

  alias GgenIgniter.Review.Finding

  @surfaces 1..6

  @impl true
  def review_diff(_diff_text, opts) do
    opts
    |> Keyword.get(:findings, [])
    |> Enum.map(&project/1)
  end

  defp project(%{surface: surface} = f) when surface in @surfaces do
    class = class(Map.get(f, :class, :correctness))

    Finding.new(
      file: fetch(f, :file),
      line: fetch(f, :line),
      class: class,
      severity: severity(Map.get(f, :severity, :important)),
      summary: fetch(f, :summary),
      perspective: :correctness
    )
  end

  defp project(%{surface: bad} = f) do
    raise ArgumentError,
          "correctness perspective: structured finding has unknown surface " <>
            "#{inspect(bad)} (expected 1..6): #{inspect(Map.get(f, :summary))}"
  end

  defp project(other) do
    raise ArgumentError,
          "correctness perspective: structured finding missing :surface — #{inspect(other)}"
  end

  defp class(:correctness), do: :correctness
  defp class(:style), do: :style
  defp class(:diagnostic), do: :diagnostic

  defp class(other),
    do: raise(ArgumentError, "correctness perspective: class #{inspect(other)} not projectable")

  defp fetch(f, key), do: Map.fetch!(f, key)

  defp severity(:blocker), do: :important
  defp severity(:major), do: :important
  defp severity(:minor), do: :nit
  defp severity(s) when s in [:important, :nit, :pre_existing], do: s
end
