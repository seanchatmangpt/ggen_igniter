defmodule GgenIgniter.SemanticJira.TransitionLog do
  @moduledoc """
  Append-only log of standing transition events, behind the
  `GgenIgniter.SemanticJira.TransitionLog.Store` behaviour.

  The first argument of every function is a *store spec*: a bare directory
  path (the file store, one immutable JSON file per event named
  `<seq>-<event_digest>.json` -- the original and default backend), a
  `{module, ref}` pair, or a store struct such as
  `GgenIgniter.SemanticJira.TransitionLog.PostgresStore`. See
  `GgenIgniter.SemanticJira.TransitionLog.FileStore` and `PostgresStore` for
  the backends.

  - `append/2` is safe under concurrent writers: a per-digest and a per-seq
    exclusive claim make each event and each `seq` single-owner. An event
    whose `event_digest` is already present is returned unchanged
    (idempotent). Existing events are never rewritten. A writer that crashes
    after claiming a seq leaves a gap, never a duplicate.
  - `read/1` returns events ordered by `seq`.

  The WorkOrder definition is never touched; current standing is the
  projection `GgenIgniter.SemanticJira.project/2` of this log over the graph.
  """

  alias GgenIgniter.SemanticJira.TransitionLog.Store

  @spec read(Store.spec()) :: [map()]
  def read(spec) do
    {store, ref} = Store.resolve(spec)
    store.list(ref)
  end

  @doc """
  Appends `event` to the store. Option `:expected_seq` requests optimistic
  concurrency (see `GgenIgniter.SemanticJira.TransitionLog.Store`); without
  it the store assigns the next free `seq`. The file store never errors
  without `:expected_seq`; a networked store may return `{:error, reason}`.
  """
  @spec append(Store.spec(), map(), keyword()) :: Store.append_ok() | Store.append_error()
  def append(spec, event, opts \\ []) do
    {store, ref} = Store.resolve(spec)
    store.append(ref, event, opts)
  end

  @doc "Lazily enumerates events ordered by `seq`."
  @spec stream(Store.spec()) :: Enumerable.t()
  def stream(spec) do
    {store, ref} = Store.resolve(spec)
    store.stream(ref)
  end

  @doc "The event with this `event_digest`, if recorded."
  @spec get(Store.spec(), String.t()) :: {:ok, map()} | :error
  def get(spec, digest) do
    {store, ref} = Store.resolve(spec)
    store.get(ref, digest)
  end

  @doc "Highest claimed `seq` (0 for an empty log)."
  @spec head(Store.spec()) :: non_neg_integer()
  def head(spec) do
    {store, ref} = Store.resolve(spec)
    store.head(ref)
  end
end
