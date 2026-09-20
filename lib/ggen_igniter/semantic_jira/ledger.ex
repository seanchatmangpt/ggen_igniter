defmodule GgenIgniter.SemanticJira.Ledger do
  @moduledoc """
  File-backed, append-only ndjson ledger of Semantic Jira standing transitions.

  One JSON object per line, each hash-chained to the previous
  (`GgenIgniter.SemanticJira.Reconciler`). Appends are serialized across OS
  processes by an atomic `mkdir` lock beside the file and are optimistic: an
  event whose `prev_event_digest`/`seq` no longer matches the tail is refused
  with `{:ledger_conflict, tail_digest}`, and `reconcile_and_append/4` re-projects
  and retries.

  Persistence here is the ledger's own bookkeeping, not actuation: events carry
  `"authority" => "NONE"`, and any consequential write stays BRCE-owned.
  """

  alias GgenIgniter.SemanticJira
  alias GgenIgniter.SemanticJira.Reconciler

  @lock_timeout_ms 30_000
  @stale_lock_seconds 60

  @doc "Reads every event; a missing file is an empty ledger."
  @spec read(Path.t()) :: {:ok, [map()]} | {:error, term()}
  def read(path) do
    case File.read(path) do
      {:ok, body} -> decode(body)
      {:error, :enoent} -> {:ok, []}
      {:error, reason} -> {:error, {:ledger_invalid, {:unreadable, reason}}}
    end
  end

  defp decode(body) do
    body
    |> String.split("\n", trim: true)
    |> Enum.with_index(1)
    |> Enum.reduce_while({:ok, []}, fn {line, n}, {:ok, acc} ->
      case Jason.decode(line) do
        {:ok, %{} = event} -> {:cont, {:ok, [event | acc]}}
        _ -> {:halt, {:error, {:ledger_invalid, {:unparseable_line, n}}}}
      end
    end)
    |> case do
      {:ok, acc} -> {:ok, Enum.reverse(acc)}
      error -> error
    end
  end

  @doc """
  Appends one event if it extends the current tail. Returns `:ok`,
  `{:error, {:ledger_conflict, tail_digest}}`, or `{:error, {:ledger_invalid, _}}`.
  """
  @spec append(Path.t(), map()) :: :ok | {:error, term()}
  def append(path, event) when is_map(event) do
    event = Map.new(event, fn {key, value} -> {to_string(key), value} end)

    with_lock(path, fn ->
      with {:ok, events} <- read(path),
           :ok <- extends_tail(event, events) do
        write(path, event)
      end
    end)
  end

  defp extends_tail(event, events) do
    tail = Reconciler.tail_digest(events)

    cond do
      event["prev_event_digest"] != tail or event["seq"] != length(events) + 1 ->
        {:error, {:ledger_conflict, tail}}

      SemanticJira.digest_exact(Map.delete(event, "event_digest")) != event["event_digest"] ->
        {:error, {:ledger_invalid, {:event_digest_mismatch, event["seq"]}}}

      true ->
        :ok
    end
  end

  defp write(path, event) do
    with {:ok, io} <- File.open(path, [:append, :binary]) do
      try do
        IO.binwrite(io, Jason.encode!(event) <> "\n")
        :file.sync(io)
        :ok
      after
        File.close(io)
      end
    end
  end

  @doc """
  Reads the ledger, reconciles `receipt` against `work_orders`, and appends the
  resulting event, retrying up to `retries` times when a concurrent append won
  the race. Returns `{:ok, event}`, `{:ok, :already_applied, event}`, or an error.
  """
  @spec reconcile_and_append([map()], Path.t(), map(), non_neg_integer()) ::
          {:ok, map()} | {:ok, :already_applied, map()} | {:error, term()}
  def reconcile_and_append(work_orders, path, receipt, retries \\ 25) do
    with {:ok, events} <- read(path) do
      case Reconciler.reconcile(work_orders, events, receipt) do
        {:ok, :already_applied, _event} = applied ->
          applied

        {:ok, event} ->
          case append(path, event) do
            :ok ->
              {:ok, event}

            {:error, {:ledger_conflict, _tail}} when retries > 0 ->
              Process.sleep(:rand.uniform(10))
              reconcile_and_append(work_orders, path, receipt, retries - 1)

            other ->
              other
          end

        other ->
          other
      end
    end
  end

  defp with_lock(path, fun) do
    lock = path <> ".lock"

    with :ok <- File.mkdir_p(Path.dirname(path)),
         :ok <- acquire(lock, System.monotonic_time(:millisecond) + @lock_timeout_ms) do
      try do
        fun.()
      after
        File.rmdir(lock)
      end
    else
      {:error, reason} -> {:error, {:ledger_lock, reason}}
    end
  end

  defp acquire(lock, deadline) do
    case File.mkdir(lock) do
      :ok ->
        :ok

      {:error, :eexist} ->
        reclaim_if_stale(lock)

        if System.monotonic_time(:millisecond) > deadline do
          {:error, :lock_timeout}
        else
          Process.sleep(2 + :rand.uniform(8))
          acquire(lock, deadline)
        end

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp reclaim_if_stale(lock) do
    case File.stat(lock, time: :posix) do
      {:ok, %File.Stat{mtime: mtime}} ->
        if System.os_time(:second) - mtime > @stale_lock_seconds, do: File.rmdir(lock)

      _ ->
        :ok
    end
  end
end
