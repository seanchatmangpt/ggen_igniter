defmodule GgenIgniter.Review.Finding do
  @moduledoc """
  The structured review finding: one record per perspective observation, with a
  deterministic identity and a stable suppression key.

  Identity law: `id` is the hex SHA-256 of
  `"\#{perspective}|\#{file}|\#{line}|\#{normalized_summary}"` truncated to 16 hex
  characters. Two perspectives reporting the same observation at the same file
  and line with the same normalized summary collapse to one id (dedupe in
  `GgenIgniter.Review`); the same observation at a *different line* is a
  different id and a different suppression key — which is the structural
  guarantee behind "never suppress a different-line pre_existing finding".

  Suppression law: `suppression_key` is `"{file}:{line}:{class}"`. It is the
  only cross-round join key (`GgenIgniter.Review.Filter.suppress_repeats/3`).

  `to_map/1` / `from_map/1` are the ONLY encode/decode boundary between a
  Finding and `Jason` string-keyed maps (`GgenIgniter.Review.Store`); nothing
  else may pass raw maps across that seam.
  """

  @enforce_keys [:id, :file, :line, :class, :severity, :summary]
  defstruct [
    :id,
    :file,
    :line,
    :class,
    :severity,
    :summary,
    perspective: nil,
    first_seen_round: nil,
    consecutive_suppressed: 0,
    escalation_candidate: false,
    status: :posted
  ]

  @type class ::
          :correctness | :invariant | :chicago_test | :epoch_law | :style | :diagnostic

  @type severity :: :important | :nit | :pre_existing

  @type t :: %__MODULE__{
          id: String.t(),
          file: String.t(),
          line: pos_integer(),
          class: class(),
          severity: severity(),
          summary: String.t(),
          perspective: atom() | nil,
          first_seen_round: pos_integer() | nil,
          consecutive_suppressed: non_neg_integer(),
          escalation_candidate: boolean(),
          status: :posted | :suppressed
        }

  @classes [:correctness, :invariant, :chicago_test, :epoch_law, :style, :diagnostic]
  @severities [:important, :nit, :pre_existing]

  @doc "The closed class set."
  @spec classes() :: [class(), ...]
  def classes, do: @classes

  @doc "The closed severity set."
  @spec severities() :: [severity(), ...]
  def severities, do: @severities

  @doc """
  Builds a Finding with the deterministic id and suppression key computed from
  its content. `:perspective` is optional; round bookkeeping fields default.
  """
  @spec new(keyword() | map()) :: t()
  def new(attrs) do
    attrs = Enum.into(attrs, %{})

    perspective = Map.get(attrs, :perspective)
    file = Map.fetch!(attrs, :file)
    line = Map.fetch!(attrs, :line)
    class = Map.fetch!(attrs, :class)
    severity = Map.fetch!(attrs, :severity)
    summary = Map.fetch!(attrs, :summary)

    %__MODULE__{
      id: id(perspective, file, line, summary),
      file: file,
      line: line,
      class: class,
      severity: severity,
      summary: summary,
      perspective: perspective,
      first_seen_round: Map.get(attrs, :first_seen_round),
      consecutive_suppressed: Map.get(attrs, :consecutive_suppressed, 0),
      escalation_candidate: Map.get(attrs, :escalation_candidate, false),
      status: Map.get(attrs, :status, :posted)
    }
  end

  @doc "Deterministic id: hex(SHA256(perspective|file|line|normalized_summary)), 16 chars."
  @spec id(atom() | nil, String.t(), pos_integer(), String.t()) :: String.t()
  def id(perspective, file, line, summary) do
    payload = "#{perspective}|#{file}|#{line}|#{normalize(summary)}"

    :crypto.hash(:sha256, payload)
    |> Base.encode16(case: :lower)
    |> binary_part(0, 16)
  end

  @doc "Normalizes a summary for identity: trim, collapse whitespace, downcase."
  @spec normalize(String.t()) :: String.t()
  def normalize(summary) when is_binary(summary) do
    summary
    |> String.trim()
    |> String.replace(~r/\s+/, " ")
    |> String.downcase()
  end

  @doc "The cross-round suppression key: \"{file}:{line}:{class}\"."
  @spec suppression_key(t()) :: String.t()
  def suppression_key(%__MODULE__{} = f), do: "#{f.file}:#{f.line}:#{f.class}"

  @doc "The ONLY Finding -> JSON map boundary (string keys, atoms as strings)."
  @spec to_map(t()) :: %{required(String.t()) => term()}
  def to_map(%__MODULE__{} = f) do
    %{
      "id" => f.id,
      "file" => f.file,
      "line" => f.line,
      "class" => Atom.to_string(f.class),
      "severity" => Atom.to_string(f.severity),
      "summary" => f.summary,
      "perspective" => perspective_string(f.perspective),
      "first_seen_round" => f.first_seen_round,
      "consecutive_suppressed" => f.consecutive_suppressed,
      "escalation_candidate" => f.escalation_candidate,
      "status" => Atom.to_string(f.status),
      "suppression_key" => suppression_key(f)
    }
  end

  @doc "The ONLY JSON map -> Finding boundary. Raises on unknown class/severity/status."
  @spec from_map(%{required(String.t()) => term()}) :: t()
  def from_map(%{} = m) do
    class = string_to_atom!(Map.fetch!(m, "class"), @classes)
    severity = string_to_atom!(Map.fetch!(m, "severity"), @severities)
    status = Map.get(m, "status", "posted")

    %__MODULE__{
      id: Map.fetch!(m, "id"),
      file: Map.fetch!(m, "file"),
      line: Map.fetch!(m, "line"),
      class: class,
      severity: severity,
      summary: Map.fetch!(m, "summary"),
      perspective: string_to_optional_atom(Map.get(m, "perspective")),
      first_seen_round: Map.get(m, "first_seen_round"),
      consecutive_suppressed: Map.get(m, "consecutive_suppressed", 0),
      escalation_candidate: Map.get(m, "escalation_candidate", false),
      status: if(status == "posted", do: :posted, else: :suppressed)
    }
  end

  defp perspective_string(nil), do: nil
  defp perspective_string(p) when is_atom(p), do: Atom.to_string(p)

  defp string_to_optional_atom(nil), do: nil

  defp string_to_optional_atom(s) when is_binary(s),
    do: string_to_atom!(s, [:correctness, :invariants, :chicago_tests, :epoch_law])

  defp string_to_atom!(s, known) do
    atom = String.to_existing_atom(s)

    unless atom in known do
      raise ArgumentError, "unknown value: #{inspect(s)}"
    end

    atom
  end
end
