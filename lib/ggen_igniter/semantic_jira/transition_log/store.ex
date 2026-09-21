defmodule GgenIgniter.SemanticJira.TransitionLog.Store do
  @moduledoc """
  Storage behaviour for the append-only standing-transition log
  (`GgenIgniter.SemanticJira.TransitionLog`).

  A store is addressed by a *ref*: a directory path for
  `GgenIgniter.SemanticJira.TransitionLog.FileStore`, a
  `GgenIgniter.SemanticJira.TransitionLog.PostgresStore` struct for the
  Postgres implementation. Callers hand `TransitionLog` (and
  `GgenIgniter.SemanticJira.Reconciler.reconcile/4`) either a bare path
  (the file store, backward compatible), a `{module, ref}` pair, or a store
  struct; `resolve/1,2` normalises all three.

  ## Invariants every implementation MUST hold

  1. **Exclusive per-digest claim.** An event is identified by its
     `event_digest` (`SemanticJira.digest/1` of the event minus `seq`). Two
     appends of the same event -- sequential or concurrent -- yield exactly
     one stored event; every later append returns
     `{:ok, stored_event, :already_recorded}`.
  2. **Exclusive per-seq claim.** Each `seq` is owned by exactly one event.
     Concurrent writers never share a `seq`. A writer that fails after
     claiming a `seq` may leave a gap, never a duplicate.
  3. **Append-only.** A stored event is never updated or deleted.
  4. **Ordered reads.** `list/1` and `stream/1` return events ordered by
     `seq`.
  5. **Optimistic concurrency.** `append/3` accepts `expected_seq: n`: the
     append succeeds only if the store can claim exactly `seq == n`,
     otherwise it returns `{:error, {:seq_conflict, head}}` and stores
     nothing.

  6. **Same events in every store.** `append/3` refuses with
     `{:error, {:unstorable_event, :nul_character}}` an event any string of
     which (key or value) contains U+0000: Postgres cannot store it, so no
     implementation accepts it, and a log can move between stores.
  7. **Idempotence of a read-back event.** The `event_digest` ignores `"seq"`
     and `"event_digest"` (`event_digest/1`), so appending an event obtained
     from `list/1` is `{:ok, stored, :already_recorded}`.
  8. **The stored event is returned.** `append/3` returns the stored event or
     an error tuple, never a nil event.

  Stored events are string-keyed JSON maps carrying `"event_digest"` and
  `"seq"`.

  Authority stays NONE: a store records admitted transitions, it does not
  perform DO.
  """

  alias GgenIgniter.SemanticJira
  alias GgenIgniter.SemanticJira.TransitionLog.FileStore

  @typedoc "Implementation-specific store address (a path, a struct, ...)."
  @type ref :: term()

  @type event :: map()
  @type append_ok :: {:ok, event(), :appended | :already_recorded}
  @type append_error ::
          {:error, {:seq_conflict, non_neg_integer()} | {:unstorable_event, atom()} | term()}

  @typedoc "Anything `resolve/1` accepts: a path, a `{module, ref}` pair, or a store struct."
  @type spec :: Path.t() | {module(), ref()} | struct()

  @doc """
  Appends `event`. Options: `:expected_seq` (see the moduledoc, invariant 5).
  """
  @callback append(ref(), event(), keyword()) :: append_ok() | append_error()

  @doc "All stored events, ordered by `seq`."
  @callback list(ref()) :: [event()]

  @doc "Lazily enumerates stored events, ordered by `seq`."
  @callback stream(ref()) :: Enumerable.t()

  @doc "The stored event with this `event_digest`, if any."
  @callback get(ref(), digest :: String.t()) :: {:ok, event()} | :error

  @doc "Highest claimed `seq` (0 for an empty store)."
  @callback head(ref()) :: non_neg_integer()

  @doc """
  The `event_digest` of `event`: `SemanticJira.digest/1` of the event without
  `"seq"` and without `"event_digest"`. Dropping `"event_digest"` too makes
  the digest of an event read back from the log equal to the digest it was
  stored under, so re-appending a stored event is `:already_recorded` (and a
  log can be copied between stores without rewriting digests). An event that
  carries neither key keeps exactly the digest it always had.
  """
  @spec event_digest(event()) :: String.t()
  def event_digest(event), do: SemanticJira.digest(Map.drop(event, ["seq", "event_digest"]))

  @doc """
  `:ok` if every store can hold `event`, else
  `{:error, {:unstorable_event, reason}}` (invariant 6: no U+0000 in any string).
  Implementations call this first in `append/3`.
  """
  @spec admit(event()) :: :ok | {:error, {:unstorable_event, :nul_character}}
  def admit(event) do
    if nul?(event), do: {:error, {:unstorable_event, :nul_character}}, else: :ok
  end

  defp nul?(value) when is_binary(value), do: String.contains?(value, <<0>>)
  defp nul?(value) when is_list(value), do: Enum.any?(value, &nul?/1)

  defp nul?(value) when is_map(value),
    do: value |> Map.to_list() |> Enum.any?(fn {k, v} -> nul?(k) or nul?(v) end)

  defp nul?(_value), do: false

  @doc """
  Normalises a store spec to `{module, ref}`.

  A binary or other `Path.t()` (`IO.chardata`, so a charlist too) is a
  `FileStore` directory (the pre-behaviour API); a `{module, ref}` pair
  passes through; a struct whose module implements this behaviour is its own
  ref.
  """
  @spec resolve(spec()) :: {module(), ref()}
  def resolve(path) when is_binary(path), do: {FileStore, path}
  def resolve(path) when is_list(path), do: {FileStore, IO.chardata_to_string(path)}
  def resolve({module, _ref} = pair) when is_atom(module), do: pair

  def resolve(%module{} = ref) do
    if store_module?(module) do
      {module, ref}
    else
      raise ArgumentError,
            "#{inspect(module)} does not implement #{inspect(__MODULE__)}"
    end
  end

  @doc """
  Like `resolve/1`, but `store` (a module, or `nil`) selects the
  implementation for a bare `ref`. `resolve(ref, nil)` is `resolve(ref)`;
  `resolve(dir, SomeStore)` is `{SomeStore, dir}`. A `{module, ref}` pair or
  store struct always wins over `store`.
  """
  @spec resolve(spec() | ref(), module() | nil) :: {module(), ref()}
  def resolve(spec, nil), do: resolve(spec)
  def resolve({module, _ref} = pair, _store) when is_atom(module), do: pair

  def resolve(%module{} = ref, store) do
    if store_module?(module), do: {module, ref}, else: {store, ref}
  end

  def resolve(ref, store) when is_atom(store), do: {store, ref}

  defp store_module?(module) do
    Code.ensure_loaded?(module) and
      Enum.all?([append: 3, list: 1, stream: 1, get: 2, head: 1], fn {f, a} ->
        function_exported?(module, f, a)
      end)
  end
end
