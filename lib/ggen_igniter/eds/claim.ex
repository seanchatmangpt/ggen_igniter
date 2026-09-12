defmodule GgenIgniter.EDS.Claim do
  @moduledoc """
  The Executable Research Claim, `ERC = <H, A, F, E, V>`, operationally
  `ERC+ = <H, A, F, P, I, E, V, R>` (Executable Design Science, S6):

    * `H` hypothesis (a falsifiable statement)
    * `A` artifact (the executable thing operationalizing H)
    * `F` falsifiers (`GgenIgniter.EDS.Falsifier.t()` list)
    * `P` protocol (how the artifact is meant to be exercised)
    * `I` execution identity (source/dependency/environment identity)
    * `E` execution evidence (real collected outputs, once run)
    * `V` verifier (a function turning evidence + falsifier verdicts into a
      `GgenIgniter.EDS.EvidenceState.t()`)
    * `R` receipt (produced by `verify/1`, not supplied up front)

  `A hypothesis with no executable artifact remains legitimate research but
  is not yet an executable research claim` (S6) -- this module therefore
  requires both `hypothesis` and `artifact` at construction, but `evidence`
  and `receipt` are legitimately absent until `execute/2` and `verify/1`
  have actually run. Do not backfill them with placeholder values; a
  `nil` here is a real, honest "not yet observed," not a bug.
  """

  alias GgenIgniter.EDS.{EvidenceState, Falsifier, Receipt}

  @enforce_keys [:hypothesis, :artifact, :protocol, :identity, :verifier]
  defstruct @enforce_keys ++ [falsifiers: [], evidence: nil, state: :proposed, receipt: nil]

  @type verifier_fun :: (term(), [{String.t(), Falsifier.verdict()}] ->
                           {EvidenceState.t(), map()})

  @type t :: %__MODULE__{
          hypothesis: String.t(),
          artifact: term(),
          falsifiers: [Falsifier.t()],
          protocol: String.t(),
          identity: map(),
          evidence: term() | nil,
          verifier: verifier_fun(),
          state: EvidenceState.t(),
          receipt: Receipt.t() | nil
        }

  @spec new(map()) :: t()
  def new(fields) when is_map(fields) do
    claim = struct!(__MODULE__, fields)

    if claim.falsifiers == [] do
      raise ArgumentError,
            "an ERC with no falsifier is a demonstration, not an executable research claim " <>
              "(Executable Design Science S6/S9) -- provide at least one GgenIgniter.EDS.Falsifier"
    end

    claim
  end

  @doc """
  Runs `executor` (a real function producing evidence from `claim.artifact`)
  and transitions `state: :proposed -> :observed` (evidence now exists --
  this is a genuine, legitimate state reached by running the artifact, not
  a collapse). What `execute/2` deliberately does NOT do is set `:verified`
  -- that transition only happens in `verify/1`, after falsifiers have run
  against the evidence; reaching `:observed` here must never be read as
  "the claim holds," only as "evidence now exists to check the claim
  against" (EDS S7: `EXECUTABLE != OBSERVED_CONSEQUENCE`, `OBSERVED != VERIFIED`).
  """
  @spec execute(t(), (term() -> term())) :: t()
  def execute(%__MODULE__{} = claim, executor) when is_function(executor, 1) do
    evidence = executor.(claim.artifact)
    %{claim | evidence: evidence, state: :observed}
  end

  @doc """
  Runs every falsifier against the collected evidence, then calls the
  claim's own `verifier` function with `(evidence, falsifier_verdicts)` to
  produce `{state, receipt_extra_fields}`. Builds and attaches a real
  `GgenIgniter.EDS.Receipt`. Raises if `execute/2` has not been called yet
  (there is no evidence to verify -- verifying an un-executed claim would
  itself be a state collapse: `EXECUTABLE != OBSERVED_CONSEQUENCE`).
  """
  @spec verify(t()) :: t()
  def verify(%__MODULE__{evidence: nil}) do
    raise ArgumentError,
          "cannot verify a claim with no evidence -- call execute/2 first (EXECUTABLE != OBSERVED_CONSEQUENCE)"
  end

  def verify(%__MODULE__{} = claim) do
    verdicts = Falsifier.run_all(claim.falsifiers, claim.evidence)
    {state, extra} = claim.verifier.(claim.evidence, verdicts)

    unless EvidenceState.valid?(state) do
      raise ArgumentError,
            "claim verifier returned an invalid EDS evidence state: #{inspect(state)}"
    end

    receipt =
      Receipt.new!(
        Map.merge(
          %{
            hypothesis: claim.hypothesis,
            artifact_identity: inspect(claim.artifact),
            source_identity: Map.get(claim.identity, :source, "unknown"),
            environment: Map.get(claim.identity, :environment, %{}),
            inputs: Map.get(claim.identity, :inputs, %{}),
            execution: %{protocol: claim.protocol},
            outputs: %{evidence: claim.evidence},
            falsifier_verdicts: verdicts,
            state: state
          },
          extra
        )
      )

    %{claim | state: state, receipt: receipt}
  end
end
