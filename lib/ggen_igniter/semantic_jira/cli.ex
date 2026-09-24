defmodule GgenIgniter.SemanticJira.Cli do
  @moduledoc """
  Orchestration behind the `mix semantic_jira.*` tasks: `reconcile`, `frontier`,
  `descriptor`, `xaas_receipt`, `observe` and `court_map`.

  Returns `{exit_code, json_map}`: `0` success, `1` typed refusal, `2` invalid
  invocation (missing option, unreadable or non-JSON input). The Mix tasks only
  parse flags and print/exit.

  `observe` requires `--origin-authority` (INVARIANT A): its absence is a
  typed refusal at exit 1, not invalid invocation.
  """

  alias GgenIgniter.SemanticJira.{CourtMap, Descriptor, Observation, Reconciler, TransitionLog}

  @spec reconcile(keyword()) :: {0 | 1 | 2, map()}
  def reconcile(opts) do
    with {:ok, work_orders} <- work_orders(opts),
         {:ok, receipt} <- json_file(opts, :receipt),
         {:ok, dir} <- required(opts, :ledger) do
      case reconcile_receipt(work_orders, receipt, dir) do
        {:ok, event, :appended} ->
          {0, %{"status" => "applied", "event" => event}}

        {:ok, event, :already_recorded} ->
          {0, %{"status" => "already_applied", "event" => event}}

        {:error, reason} ->
          {1, %{"status" => "refused", "reason" => jsonable(reason)}}
      end
    else
      {:invalid, reason} -> {2, %{"status" => "invalid_invocation", "reason" => reason}}
    end
  end

  # The canonical reconciler binds one receipt to one WorkOrder by definition
  # digest (`Reconciler.reconcile/4` + the file-backed TransitionLog); the CLI
  # accepts the whole graph and finds the row the receipt targets. A
  # definition mismatch on a non-targeting row is skipped, not fatal.
  defp reconcile_receipt(work_orders, receipt, dir) do
    Enum.find_value(work_orders, {:error, {:refused, :no_matching_work_order}}, fn work_order ->
      case Reconciler.reconcile(work_order, receipt, dir) do
        {:ok, event, which} -> {:ok, event, which}
        {:error, {:refused, :definition_mismatch}} -> nil
        {:error, _} = refusal -> refusal
      end
    end)
  end

  # The ledger is read through `TransitionLog.fetch/1`: `read/1` returns a
  # plain event list, `fetch/1` wraps it as `{:ok, events}` and refuses a
  # tampered or undecodable ledger (`{:error, {:ledger_refused, _}}`).
  @spec frontier(keyword()) :: {0 | 1 | 2, map()}
  def frontier(opts) do
    with {:ok, work_orders} <- work_orders(opts),
         {:ok, dir} <- required(opts, :ledger) do
      with {:ok, events} <- TransitionLog.fetch(dir),
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
         {:ok, dir} <- required(opts, :ledger),
         {:ok, identity} <- required(opts, :identity),
         {:ok, suite} <- required(opts, :verifier_suite),
         {:ok, aliases} <- aliases(opts),
         {:ok, court_map} <- optional_court_map(opts),
         {:ok, provider} <- optional(opts, :provider) do
      contract_opts =
        [verifier_suite: suite, aliases: aliases, court_map: court_map, provider: provider]
        |> Enum.reject(fn {_key, value} -> is_nil(value) end)

      with {:ok, events} <- TransitionLog.fetch(dir),
           {:ok, descriptor} <-
             Descriptor.build_xaas_contract(work_orders, events, identity, contract_opts) do
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
        [
          ontology_path: opts[:ontology],
          identity: opts[:identity],
          origin_authority: opts[:origin_authority],
          origin_observation: opts[:origin_observation],
          repair: repair
        ]
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
  Mints the court map of one work order from a Turtle ontology file
  (`CourtMap.from_ontology/2`). Refusals are typed JSON (exit 1), never a
  crash on encoding the refusal tuple.
  """
  @spec court_map(keyword()) :: {0 | 1 | 2, map()}
  def court_map(opts) do
    with {:ok, ontology_path} <- required(opts, :ontology),
         {:ok, identity} <- required(opts, :identity) do
      with {:ok, ttl} <- read_ontology(ontology_path),
           {:ok, court_map} <- CourtMap.from_ontology(ttl, identity) do
        {0, court_map}
      else
        {:error, reason} -> refused(reason)
      end
    else
      {:invalid, reason} -> invalid(reason)
    end
  end

  defp read_ontology(path) do
    case File.read(path) do
      {:ok, ttl} -> {:ok, ttl}
      {:error, reason} -> {:error, {:ontology_unreadable, path, inspect(reason)}}
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

  # --court-map PATH: the minted court map JSON (mix semantic_jira.court_map).
  # Absent = no court receipt contract; present but non-JSON = invalid.
  defp optional_court_map(opts) do
    case optional_json(opts, :court_map) do
      {:ok, nil} -> {:ok, nil}
      {:ok, value} when is_map(value) -> {:ok, value}
      {:ok, _other} -> {:invalid, "--court-map must be a JSON object"}
      {:invalid, _} = invalid -> invalid
    end
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
      body |> Jason.decode() |> or_invalid(path)
    end
  end

  defp or_invalid({:ok, _} = ok, _path), do: ok
  defp or_invalid({:error, reason}, path), do: {:invalid, "#{path}: #{inspect(reason)}"}

  # Absent = default (nil); present but empty = invalid invocation.
  defp optional(opts, key) do
    if Keyword.has_key?(opts, key), do: required(opts, key), else: {:ok, nil}
  end

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
