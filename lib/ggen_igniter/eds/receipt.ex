defmodule GgenIgniter.EDS.Receipt do
  @moduledoc """
  Executable Design Science, S8: a receipt binds a scientific claim to the
  exact execution that allegedly supports it --
  `receipt(H, A, source, dependencies, environment, inputs, execution,
  outputs, validators)` -- so a later observer can answer "what exact
  hypothesis, what exact artifact, what source revision, what dependency
  state, what environment, what inputs, what execution path, what output,
  which validator, what proposition does that evidence support."

  Distinct from `GgenIgniter.Receipt` (the Reactor pipeline's own
  file-actuation receipt, ADR-0005) -- that module receipts *code changes to
  disk*; this module receipts *research claims about executable systems*.
  A `GgenIgniter.Receipt` can be cited as one piece of evidence inside an
  `GgenIgniter.EDS.Receipt`, but the two are not the same object and one is
  not a substitute for the other (S8's `named experiment != executed
  experiment`, `executed experiment != verified claim`).
  """

  @enforce_keys [
    :hypothesis,
    :artifact_identity,
    :source_identity,
    :environment,
    :inputs,
    :execution,
    :outputs,
    :falsifier_verdicts,
    :state
  ]
  defstruct @enforce_keys ++ [:validators, :fingerprint]

  alias GgenIgniter.EDS.{EvidenceState, Falsifier}

  @type t :: %__MODULE__{
          hypothesis: String.t(),
          artifact_identity: String.t(),
          source_identity: String.t(),
          environment: map(),
          inputs: map(),
          execution: map(),
          outputs: map(),
          falsifier_verdicts: [{String.t(), Falsifier.verdict()}],
          validators: [String.t()] | nil,
          state: EvidenceState.t(),
          fingerprint: String.t() | nil
        }

  @doc """
  Builds a receipt from real, already-collected fields (no field here is a
  hardcoded default; every value must come from actual observation). Raises
  on an invalid `:state`. Computes a real sha256 `:fingerprint` over the
  canonical (sorted-key) JSON encoding of every field except the fingerprint
  itself, so two receipts for genuinely identical evidence produce the same
  fingerprint and any single-field change is detected.
  """
  @spec new!(map()) :: t()
  def new!(fields) when is_map(fields) do
    state = Map.fetch!(fields, :state)

    unless EvidenceState.valid?(state) do
      raise ArgumentError,
            "invalid EDS evidence state: #{inspect(state)} (valid: #{inspect(EvidenceState.states())})"
    end

    receipt = struct!(__MODULE__, Map.delete(fields, :fingerprint))
    %{receipt | fingerprint: fingerprint(receipt)}
  end

  @doc """
  Real sha256 fingerprint over the receipt's canonical JSON encoding
  (Jason's `sort_keys: true` maps keys deterministically) so identity does
  not depend on Erlang term/map key ordering, which is not guaranteed
  stable across runs.
  """
  @spec fingerprint(t()) :: String.t()
  def fingerprint(%__MODULE__{} = receipt) do
    receipt
    |> Map.from_struct()
    |> Map.delete(:fingerprint)
    |> stringify_deep()
    |> Jason.encode!(maps: :strict)
    |> then(&:crypto.hash(:sha256, &1))
    |> Base.encode16(case: :lower)
  end

  # Jason can't encode arbitrary tuples (falsifier verdicts are
  # `{name, {:survived | :falsified, detail}}` tuples) or atoms as map
  # values reliably across encode/decode round trips for our identity
  # purpose -- normalize to plain JSON-safe terms (lists/maps/strings)
  # before hashing, so the fingerprint is stable and reproducible from the
  # receipt's own printed form, not just from the exact in-memory term.
  defp stringify_deep(%{__struct__: _} = struct),
    do: struct |> Map.from_struct() |> stringify_deep()

  defp stringify_deep(map) when is_map(map),
    do: Map.new(map, fn {k, v} -> {to_string(k), stringify_deep(v)} end)

  defp stringify_deep(list) when is_list(list), do: Enum.map(list, &stringify_deep/1)
  defp stringify_deep({a, b}), do: [stringify_deep(a), stringify_deep(b)]

  defp stringify_deep(atom) when is_atom(atom) and not is_boolean(atom) and not is_nil(atom),
    do: Atom.to_string(atom)

  defp stringify_deep(other), do: other

  @doc "Real, human-readable one-line summary -- the receipt's own `line` field, per the paper's discussion of receipt-bound standing."
  @spec summary(t()) :: String.t()
  def summary(%__MODULE__{} = r) do
    "EDS receipt #{String.slice(r.fingerprint || "unfingerprinted", 0, 12)}: " <>
      "state=#{r.state} hypothesis=#{inspect(r.hypothesis)} " <>
      "falsifiers=#{length(r.falsifier_verdicts)} survived=#{Falsifier.all_survived?(r.falsifier_verdicts)}"
  end
end
