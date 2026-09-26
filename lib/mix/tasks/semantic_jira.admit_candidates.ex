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

  Before either gate, the candidate line is refused when it claims what only
  receipts may confer (`candidate_bounds/1`):

    * `standing` other than `"UNKNOWN"` -- a candidate enters at UNKNOWN;
      standing is derived from receipts, never stored as a literal
      (`{:refused_candidate, {:literal_standing, s}}`);
    * `authority_requirement` other than `"NONE"`, or an `evidence_ceiling`
      that is not a string or names an actuation in ANY token -- the value is
      split on every non-alphanumeric character (so `"DO/MERGE"`,
      `"merge-to-main"`, `"\\tdo\\n"` are each tokenized) and a token is refused
      when it is `DO`, `EXECUTE`, or begins with `ACTUAT`, `MERGE`,
      `PUBLISH`, `DEPLOY`, `PUSH`, `RELEASE` (any case). Evidence-ladder
      values (`SPECIFIED`, `IMPLEMENTED_UNVERIFIED`, `EXECUTED_VERIFIED`,
      `LOCAL_RUN`, `repository-local`, `CONSTRUCT`) name evidence, not
      actuation, and pass. The ceiling is at most CONSTRUCT
      (`{:refused_candidate, {:ceiling_exceeds_construct, field, value}}`).

  Within one batch, a later line whose `identity`, `replay_identity`, or
  admitted `work_order_digest` repeats an earlier ADMITTED line is refused
  (`{:refused_candidate, {:duplicate, field, first_line}}`): one candidate,
  one admission.

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
      |> dedupe()

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

        with :ok <- candidate_bounds(candidate),
             {:ok, admitted} <- SemanticJira.admit_work_order(candidate),
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

  # Whole-token actuations, and actuation roots matched as token prefixes
  # (MERGED, PUSHED, DEPLOYMENT, ACTUATE, ACTUATION, ...). EXECUTE is exact:
  # EXECUTED (as in EXECUTED_VERIFIED) is evidence that tests ran, not a DO.
  @actuation_tokens ~w(DO EXECUTE)
  @actuation_roots ~w(ACTUAT MERGE PUBLISH DEPLOY PUSH RELEASE)

  @doc false
  @spec candidate_bounds(map()) :: :ok | {:error, term()}
  def candidate_bounds(candidate) do
    standing = Map.get(candidate, "standing", "UNKNOWN")
    requirement = Map.get(candidate, "authority_requirement", "NONE")
    ceiling = Map.get(candidate, "evidence_ceiling")

    cond do
      standing != "UNKNOWN" ->
        {:error, {:refused_candidate, {:literal_standing, standing}}}

      requirement != "NONE" ->
        {:error,
         {:refused_candidate, {:ceiling_exceeds_construct, "authority_requirement", requirement}}}

      not is_nil(ceiling) and not is_binary(ceiling) ->
        {:error, {:refused_candidate, {:ceiling_exceeds_construct, "evidence_ceiling", ceiling}}}

      is_binary(ceiling) and names_actuation?(ceiling) ->
        {:error, {:refused_candidate, {:ceiling_exceeds_construct, "evidence_ceiling", ceiling}}}

      true ->
        :ok
    end
  end

  @doc false
  @spec names_actuation?(String.t()) :: boolean()
  def names_actuation?(value) when is_binary(value) do
    value
    |> String.upcase()
    |> String.split(~r/[^A-Z0-9]+/u, trim: true)
    |> Enum.any?(fn token ->
      token in @actuation_tokens or Enum.any?(@actuation_roots, &String.starts_with?(token, &1))
    end)
  end

  # One candidate, one admission: a later admitted line that repeats an
  # earlier admitted line's identity, replay_identity, or work_order_digest is
  # refused, naming the field and the first line.
  defp dedupe(verdicts) do
    {out, _seen} =
      Enum.map_reduce(verdicts, %{}, fn
        {n, {:admitted, wo, _digest}} = verdict, seen ->
          keys = for f <- ~w(identity replay_identity work_order_digest), do: {f, wo[f]}

          case Enum.find(keys, &Map.has_key?(seen, &1)) do
            nil ->
              {verdict, Enum.reduce(keys, seen, &Map.put(&2, &1, n))}

            {field, _} = key ->
              {{n,
                {:refused, wo["identity"], {:refused_candidate, {:duplicate, field, seen[key]}}}},
               seen}
          end

        other, seen ->
          {other, seen}
      end)

    out
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
