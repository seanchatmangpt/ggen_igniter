defmodule GgenIgniter.EngineComparisonReport do
  @moduledoc """
  The runtime, per-invocation, N-way surfacing mechanism ADR-0008 introduces --
  NOT a new correctness oracle. `pairwise_agreement/1` restates, over real rows
  returned from a real run, exactly the row-set/row-order/error-shape
  distinction classes `test/ggen_igniter_cross_engine_equivalence_properties_test.exs`
  and `test/ggen_igniter_engine_parity_test.exs` already establish statically:

  - Row-SET equality via `MapSet.new/1` over each candidate's raw `rows`
    (mirroring `ggen_igniter_cross_engine_equivalence_properties_test.exs`'s own
    `rows_as_set/1` method, for the identical reason that test names -- order is
    a separately-tracked, already-known-divergent axis).
  - Row-ORDER equality as a SEPARATE raw-list `==` check, deliberately kept
    apart from set equality per the confirmed `sparql`-hex `ORDER BY`
    row-reversal bug documented in `lib/ggen_igniter/query.ex:4-16`'s
    moduledoc. A future divergence of that exact shape shows up here as
    `order_equal?: false` with `row_set_equal?: true`, never collapsed into
    one ambiguous boolean.

  Two structs:

  - `t()` -- one comparison run: `query` (the SPARQL text run, verbatim),
    `candidates` (`[CandidateResult.t()]`, one per engine `GgenIgniter.
    EngineRegistry.run_all/4` fanned out to), `pairwise_agreement` (a map
    keyed by `{engine_a, engine_b}` engine-atom pairs, `engine_a` ordered
    before `engine_b` per `GgenIgniter.Engine.valid_names/0`'s own sort so a
    pair never appears twice under swapped keys), `generated_at`
    (`DateTime.t()`).
  - `CandidateResult.t()` -- one engine's real outcome: `engine` (atom),
    `status` (`:ok | :error | :timeout`), `rows` (`[map()] | nil`,
    `nil` only when `status != :ok`), `row_count`, `elapsed_us`
    (`System.monotonic_time(:microsecond)` delta; always a real non-negative
    integer, even on `:error`/`:timeout`, so the report can show how long a
    failing engine took before it failed), `error` (`String.t() | nil`, the
    real `Exception.message/1` or exit-reason text on a non-`:ok` status).

  `to_markdown/1` and `to_json/1` render either one report or a list of
  reports (`GgenIgniter.EngineRegistry.run_all/4`'s caller runs one report per
  named `--query`; `mix ggen_igniter.sync --engine oxigraph,sparql` with more
  than one `--query name=path.rq` produces more than one report over one
  invocation). No new templating path: `to_markdown/1` follows this repo's
  existing `GgenIgniter.Render.render/2` convention (`lib/ggen_igniter/
  render.ex:8-11`, stdlib `EEx.eval_string/2` against bindings) rather than
  inventing a second one. `to_json/1` uses `Jason` (already a dependency, see
  `mix.exs`'s `{:jason, "~> 1.4"}`) -- no new dependency either.
  """

  defstruct [:query, :candidates, :pairwise_agreement, :generated_at]

  @type t :: %__MODULE__{
          query: String.t(),
          candidates: [__MODULE__.CandidateResult.t()],
          pairwise_agreement: %{
            {atom(), atom()} => %{
              row_set_equal?: boolean(),
              row_count_diff: integer(),
              order_equal?: boolean()
            }
          },
          generated_at: DateTime.t()
        }

  defmodule CandidateResult do
    @moduledoc """
    One engine's real outcome from one `GgenIgniter.EngineRegistry.run_all/4`
    fan-out -- see the parent module's moduledoc for the field contract.
    """

    defstruct [:engine, :status, :rows, :row_count, :elapsed_us, :error]

    @type status :: :ok | :error | :timeout

    @type t :: %__MODULE__{
            engine: atom(),
            status: status(),
            rows: [map()] | nil,
            row_count: non_neg_integer(),
            elapsed_us: non_neg_integer() | nil,
            error: String.t() | nil
          }
  end

  alias __MODULE__.CandidateResult

  @doc """
  Computes `t().pairwise_agreement` over every `status: :ok` pair in
  `candidates` (a `status: :error`/`:timeout` candidate has no real `rows` to
  compare, so it is excluded from every pair rather than silently compared
  against `nil`). Every unordered pair is computed exactly once, keyed
  `{engine_a, engine_b}` with `engine_a` preceding `engine_b` in the input
  list's own order (never both `{a, b}` and `{b, a}`).

  ## Examples

      iex> a = %GgenIgniter.EngineComparisonReport.CandidateResult{engine: :oxigraph, status: :ok, rows: [%{"s" => "x"}], row_count: 1}
      iex> b = %GgenIgniter.EngineComparisonReport.CandidateResult{engine: :sparql, status: :ok, rows: [%{"s" => "x"}], row_count: 1}
      iex> GgenIgniter.EngineComparisonReport.pairwise_agreement([a, b])
      %{{:oxigraph, :sparql} => %{row_set_equal?: true, row_count_diff: 0, order_equal?: true}}

  """
  @spec pairwise_agreement([CandidateResult.t()]) :: %{
          {atom(), atom()} => %{
            row_set_equal?: boolean(),
            row_count_diff: integer(),
            order_equal?: boolean()
          }
        }
  def pairwise_agreement(candidates) when is_list(candidates) do
    ok_candidates = Enum.filter(candidates, &(&1.status == :ok))
    indexed = Enum.with_index(ok_candidates)

    for {a, i} <- indexed,
        {b, j} <- indexed,
        i < j,
        into: %{} do
      {{a.engine, b.engine}, compare_pair(a, b)}
    end
  end

  defp compare_pair(%CandidateResult{rows: rows_a, row_count: count_a}, %CandidateResult{
         rows: rows_b,
         row_count: count_b
       }) do
    %{
      row_set_equal?: MapSet.equal?(MapSet.new(rows_a), MapSet.new(rows_b)),
      row_count_diff: count_a - count_b,
      order_equal?: rows_a == rows_b
    }
  end

  @doc "Renders one report, or a list of reports (see moduledoc), as pretty-printed JSON."
  @spec to_json(t() | [t()]) :: String.t()
  def to_json(%__MODULE__{} = report), do: Jason.encode!(to_json_map(report), pretty: true)

  def to_json(reports) when is_list(reports) do
    Jason.encode!(Enum.map(reports, &to_json_map/1), pretty: true)
  end

  @doc "The plain, JSON-safe map `to_json/1` encodes -- exposed separately so a caller (e.g. `mix ggen_igniter.sync`'s `--engine-report`) can wrap it (adding a `\"query_name\"` field) without re-parsing the encoded string."
  @spec to_json_map(t()) :: map()
  def to_json_map(%__MODULE__{} = report) do
    %{
      "query" => report.query,
      "generated_at" => DateTime.to_iso8601(report.generated_at),
      "candidates" => Enum.map(report.candidates, &candidate_to_json_map/1),
      "pairwise_agreement" => pairwise_agreement_to_json(report.pairwise_agreement)
    }
  end

  defp candidate_to_json_map(%CandidateResult{} = c) do
    %{
      "engine" => Atom.to_string(c.engine),
      "status" => Atom.to_string(c.status),
      "rows" => c.rows,
      "row_count" => c.row_count,
      "elapsed_us" => c.elapsed_us,
      "error" => c.error
    }
  end

  defp pairwise_agreement_to_json(pairwise_agreement) do
    Enum.map(pairwise_agreement, fn {{engine_a, engine_b}, agreement} ->
      %{
        "engine_a" => Atom.to_string(engine_a),
        "engine_b" => Atom.to_string(engine_b),
        "row_set_equal?" => agreement.row_set_equal?,
        "row_count_diff" => agreement.row_count_diff,
        "order_equal?" => agreement.order_equal?
      }
    end)
  end

  @markdown_template """
  # Engine Comparison Report

  **Query:**

  ```sparql
  <%= query %>
  ```

  **Generated at:** <%= generated_at %>

  ## Candidates

  | Engine | Status | Rows | Elapsed (ms) | Error |
  | --- | --- | --- | --- | --- |
  <%= for c <- candidates do %>| <%= c.engine %> | <%= c.status %> | <%= c.row_count %> | <%= if c.elapsed_us, do: Float.round(c.elapsed_us / 1000, 2), else: "-" %> | <%= c.error || "-" %> |
  <% end %>
  ## Pairwise agreement

  | Engine A | Engine B | Row-set equal | Row count diff | Order equal |
  | --- | --- | --- | --- | --- |
  <%= for {{a, b}, agreement} <- pairwise_agreement do %>| <%= a %> | <%= b %> | <%= agreement.row_set_equal? %> | <%= agreement.row_count_diff %> | <%= agreement.order_equal? %> |
  <% end %>
  """

  @doc "Renders one report, or a list of reports (see moduledoc), as a Markdown document (stdlib `EEx.eval_string/2`, `GgenIgniter.Render.render/2`'s own convention -- no second templating path)."
  @spec to_markdown(t() | [t()]) :: String.t()
  def to_markdown(%__MODULE__{} = report), do: render_markdown(report)

  def to_markdown(reports) when is_list(reports) do
    Enum.map_join(reports, "\n---\n\n", &render_markdown/1)
  end

  defp render_markdown(%__MODULE__{} = report) do
    bindings = [
      query: report.query,
      generated_at: DateTime.to_iso8601(report.generated_at),
      candidates: report.candidates,
      pairwise_agreement: Enum.to_list(report.pairwise_agreement)
    ]

    EEx.eval_string(@markdown_template, bindings)
  end
end
