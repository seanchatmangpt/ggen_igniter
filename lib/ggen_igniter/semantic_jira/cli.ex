defmodule GgenIgniter.SemanticJira.Cli do
  @moduledoc """
  Orchestration behind `mix semantic_jira.reconcile` and `mix semantic_jira.frontier`.

  Returns `{exit_code, json_map}`: `0` success, `1` typed refusal, `2` invalid
  invocation (missing option, unreadable or non-JSON input). The Mix tasks only
  parse flags and print/exit.
  """

  alias GgenIgniter.SemanticJira.{Ledger, Reconciler}

  @spec reconcile(keyword()) :: {0 | 1 | 2, map()}
  def reconcile(opts) do
    with {:ok, work_orders} <- work_orders(opts),
         {:ok, receipt} <- json_file(opts, :receipt),
         {:ok, ledger} <- required(opts, :ledger) do
      case Ledger.reconcile_and_append(work_orders, ledger, receipt) do
        {:ok, event} ->
          {0, %{"status" => "applied", "event" => event}}

        {:ok, :already_applied, event} ->
          {0, %{"status" => "already_applied", "event" => event}}

        {:error, reason} ->
          {1, %{"status" => "refused", "reason" => jsonable(reason)}}
      end
    else
      {:invalid, reason} -> {2, %{"status" => "invalid_invocation", "reason" => reason}}
    end
  end

  @spec frontier(keyword()) :: {0 | 1 | 2, map()}
  def frontier(opts) do
    with {:ok, work_orders} <- work_orders(opts),
         {:ok, ledger} <- required(opts, :ledger) do
      with {:ok, events} <- Ledger.read(ledger),
           {:ok, projected, _evidence} <- Reconciler.project(work_orders, events),
           {:ok, frontier} <- Reconciler.frontier(work_orders, events) do
        {0,
         %{
           "status" => "ok",
           "eligible" => frontier.eligible,
           "blocked" => frontier.blocked,
           "standings" => Map.new(projected, &{&1["identity"], &1["standing"]}),
           "events" => length(events),
           "ledger_tail" => Reconciler.tail_digest(events)
         }}
      else
        {:error, reason} -> {1, %{"status" => "refused", "reason" => jsonable(reason)}}
      end
    else
      {:invalid, reason} -> {2, %{"status" => "invalid_invocation", "reason" => reason}}
    end
  end

  defp work_orders(opts) do
    with {:ok, decoded} <- json_file(opts, :work_orders) do
      case decoded do
        list when is_list(list) -> {:ok, list}
        %{"work_orders" => list} when is_list(list) -> {:ok, list}
        _ -> {:invalid, "--work-orders must be a JSON array or {\"work_orders\": [...]}"}
      end
    end
  end

  defp json_file(opts, key) do
    with {:ok, path} <- required(opts, key),
         {:ok, body} <- File.read(path) |> or_invalid(path),
         {:ok, decoded} <- Jason.decode(body) |> or_invalid(path) do
      {:ok, decoded}
    end
  end

  defp or_invalid({:ok, _} = ok, _path), do: ok
  defp or_invalid({:error, reason}, path), do: {:invalid, "#{path}: #{inspect(reason)}"}

  defp required(opts, key) do
    case Keyword.get(opts, key) do
      value when is_binary(value) and value != "" -> {:ok, value}
      _ -> {:invalid, "missing --#{key |> to_string() |> String.replace("_", "-")}"}
    end
  end

  # Typed refusals are tuples/atoms; render them losslessly enough to branch on.
  defp jsonable(value) when is_tuple(value), do: value |> Tuple.to_list() |> jsonable()
  defp jsonable(value) when is_list(value), do: Enum.map(value, &jsonable/1)

  defp jsonable(value) when is_map(value),
    do: Map.new(value, fn {k, v} -> {to_string(k), jsonable(v)} end)

  defp jsonable(value) when is_atom(value) and value not in [nil, true, false],
    do: Atom.to_string(value)

  defp jsonable(value), do: value
end
