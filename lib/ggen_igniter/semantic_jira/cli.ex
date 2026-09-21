defmodule GgenIgniter.SemanticJira.Cli do
  @moduledoc """
  Orchestration behind the `mix semantic_jira.*` tasks: `reconcile`, `frontier`,
  `descriptor`, `xaas_receipt` and `observe`.

  Returns `{exit_code, json_map}`: `0` success, `1` typed refusal, `2` invalid
  invocation (missing option, unreadable or non-JSON input). The Mix tasks only
  parse flags and print/exit.
  """

  alias GgenIgniter.SemanticJira.{Descriptor, Ledger, Observation, Reconciler}

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

  @doc "Builds the XaaS execution descriptor for one frontier identity."
  @spec descriptor(keyword()) :: {0 | 1 | 2, map()}
  def descriptor(opts) do
    with {:ok, work_orders} <- work_orders(opts),
         {:ok, ledger} <- required(opts, :ledger),
         {:ok, identity} <- required(opts, :identity),
         {:ok, suite} <- required(opts, :verifier_suite),
         {:ok, aliases} <- aliases(opts) do
      with {:ok, events} <- Ledger.read(ledger),
           {:ok, descriptor} <-
             Descriptor.build(work_orders, events, identity,
               verifier_suite: suite,
               aliases: aliases
             ) do
        {0, descriptor}
      else
        {:error, reason} -> refused(reason)
      end
    else
      {:invalid, reason} -> invalid(reason)
    end
  end

  @doc "Maps a sealed XaaS receipt onto the receipt the reconciler consumes."
  @spec xaas_receipt(keyword()) :: {0 | 1 | 2, map()}
  def xaas_receipt(opts) do
    with {:ok, bridge_doc} <- json_file(opts, :bridge),
         {:ok, receipt} <- json_file(opts, :xaas_receipt) do
      bridge =
        if is_map(bridge_doc), do: Map.get(bridge_doc, "bridge", bridge_doc), else: bridge_doc

      case Descriptor.receipt_from_xaas(receipt, bridge) do
        {:ok, reconciler_receipt} -> {0, reconciler_receipt}
        {:error, reason} -> refused(reason)
      end
    else
      {:invalid, reason} -> invalid(reason)
    end
  end

  @doc "Turns an observed process finding into an admitted candidate WorkOrder."
  @spec observe(keyword()) :: {0 | 1 | 2, map()}
  def observe(opts) do
    with {:ok, finding} <- json_file(opts, :finding),
         {:ok, base} <- json_file(opts, :base_work_order),
         {:ok, repair} <- optional_json(opts, :repair) do
      observe_opts =
        [ontology_path: opts[:ontology], identity: opts[:identity], repair: repair]
        |> Enum.reject(fn {_key, value} -> is_nil(value) end)

      case Observation.candidate(finding, base, observe_opts) do
        {:ok, result} -> {0, result}
        {:error, reason} -> refused(reason)
      end
    else
      {:invalid, reason} -> invalid(reason)
    end
  end

  @doc """
  Prints a result. Success: JSON on stdout (and to `--out` when given), exit 0.
  Refusal or invalid invocation: typed JSON on stderr, non-zero exit.
  """
  @spec emit({0 | 1 | 2, map()}, keyword()) :: :ok
  def emit({0, result}, opts) do
    json = Jason.encode!(result)
    if path = Keyword.get(opts, :out), do: File.write!(path, json <> "\n")
    IO.puts(json)
  end

  def emit({code, result}, _opts) do
    IO.puts(:stderr, Jason.encode!(result))
    exit({:shutdown, code})
  end

  defp optional_json(opts, key) do
    if Keyword.get(opts, key), do: json_file(opts, key), else: {:ok, nil}
  end

  defp aliases(opts) do
    opts
    |> Keyword.get_values(:alias)
    |> Enum.reduce_while({:ok, %{}}, fn pair, {:ok, acc} ->
      case String.split(pair, "=", parts: 2) do
        [repository, alias_name] when repository != "" and alias_name != "" ->
          {:cont, {:ok, Map.put(acc, repository, alias_name)}}

        _ ->
          {:halt, {:invalid, "--alias must be owner/repo=alias, got #{inspect(pair)}"}}
      end
    end)
  end

  defp refused(reason), do: {1, %{"status" => "refused", "reason" => jsonable(reason)}}
  defp invalid(reason), do: {2, %{"status" => "invalid_invocation", "reason" => reason}}

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
         {:ok, body} <- File.read(path) |> or_invalid(path) do
      Jason.decode(body) |> or_invalid(path)
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
