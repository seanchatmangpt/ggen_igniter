defmodule Mix.Tasks.SemanticJira.AdmitCandidates do
  @shortdoc "Admit or refuse JSONL Semantic Jira work-order candidates, one verdict per line"

  @moduledoc """
  Reads work-order CANDIDATES (one JSON object per line) and prints one
  verdict per non-blank line:

      mix semantic_jira.admit_candidates --candidates PATH [--authority-graph PATH]

  Each candidate is admitted only when BOTH gates pass:

    1. `GgenIgniter.SemanticJira.admit_work_order/1` (shape, subject SHA,
       standing, required relations, `origin_authority` is an IRI); and
    2. its `origin_authority` RESOLVES to an admitted authority in the pinned
       authority index (`GgenIgniter.SemanticJira.Authority.index_from/1`): a
       node typed `sj:StrategicObjective`/`sj:GoalCheckpoint`, not prose,
       whose `sj:admissionDigest` recomputes. A prose origin never admits.

  Output, one line per candidate line, in input order:

      admitted <line> <identity> origin=<iri> origin_digest=<digest> work_order_digest=<digest>
      refused <line> <identity|-> <typed reason>

  followed by one summary line `summary admitted=<n> refused=<n>`.

  Exit `0` when every line was judged (admitted or refused -- a refusal is a
  verdict, not a failure), `2` for an invalid invocation or an unreadable
  candidates file, `1` when the authority index is unavailable (fail closed:
  nothing is admitted). Authority NONE: this task only SELECTs; it writes
  nothing and actuates nothing.
  """

  use Mix.Task

  alias GgenIgniter.SemanticJira
  alias GgenIgniter.SemanticJira.Authority

  @impl Mix.Task
  def run(args) do
    {opts, _rest, invalid} =
      OptionParser.parse(args, strict: [candidates: :string, authority_graph: :string])

    path = opts[:candidates]

    if invalid != [] or is_nil(path) do
      Mix.shell().error(
        "usage: mix semantic_jira.admit_candidates --candidates PATH [--authority-graph PATH]"
      )

      exit({:shutdown, 2})
    end

    judge_file(path, opts[:authority_graph])
  end

  defp judge_file(path, authority_graph) do
    lines =
      case File.read(path) do
        {:ok, bytes} ->
          String.split(bytes, "\n")

        {:error, reason} ->
          Mix.shell().error("refused: cannot read #{path}: #{inspect(reason)}")
          exit({:shutdown, 2})
      end

    index_opts = if authority_graph, do: [authority: authority_graph], else: []

    index =
      case Authority.index_from(index_opts) do
        {:ok, index} ->
          index

        {:error, reason} ->
          Mix.shell().error("refused: authority index unavailable: #{inspect(reason)}")
          exit({:shutdown, 1})
      end

    verdicts =
      lines
      |> Enum.with_index(1)
      |> Enum.reject(fn {line, _n} -> String.trim(line) == "" end)
      |> Enum.map(fn {line, n} -> {n, judge_line(line, index)} end)

    Enum.each(verdicts, fn {n, verdict} -> Mix.shell().info(format(n, verdict)) end)

    admitted = Enum.count(verdicts, fn {_n, v} -> match?({:admitted, _, _}, v) end)

    Mix.shell().info("summary admitted=#{admitted} refused=#{length(verdicts) - admitted}")
  end

  @doc false
  @spec judge_line(String.t(), Authority.index()) ::
          {:admitted, map(), String.t()} | {:refused, String.t() | nil, term()}
  def judge_line(line, index) do
    case Jason.decode(line) do
      {:ok, candidate} when is_map(candidate) ->
        identity = identity_of(candidate)

        with {:ok, admitted} <- SemanticJira.admit_work_order(candidate),
             {:ok, origin_digest} <- Authority.resolve(index, admitted["origin_authority"]) do
          {:admitted, admitted, origin_digest}
        else
          {:error, reason} -> {:refused, identity, reason}
        end

      {:ok, other} ->
        {:refused, nil, {:refused_work_order, {:expected_json_object, type_of(other)}}}

      {:error, %Jason.DecodeError{position: position}} ->
        {:refused, nil, {:refused_work_order, {:invalid_json, position}}}
    end
  end

  defp identity_of(%{"identity" => identity}) when is_binary(identity), do: identity
  defp identity_of(_), do: nil

  defp type_of(value) when is_list(value), do: :array
  defp type_of(value) when is_binary(value), do: :string
  defp type_of(value) when is_number(value), do: :number
  defp type_of(nil), do: :null
  defp type_of(_), do: :other

  defp format(n, {:admitted, work_order, origin_digest}) do
    "admitted #{n} #{work_order["identity"]} origin=#{work_order["origin_authority"]} " <>
      "origin_digest=#{origin_digest} work_order_digest=#{work_order["work_order_digest"]}"
  end

  defp format(n, {:refused, identity, reason}) do
    "refused #{n} #{identity || "-"} #{inspect(reason)}"
  end
end
