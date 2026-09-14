defmodule GgenIgniter.EphemeralManufacture do
  @moduledoc """
  v26.9.15 composition boundary for graph-generated ephemeral projections.

  This module does not implement actuation. Its only mutating path delegates
  to `GgenIgniter.Reactors.ReconcileReactor.run/1`, which remains the existing
  admitted reconciliation/actuation/receipt path. After that path returns a
  durable `:alive` receipt, this module reads the exact admitted output bytes
  and constructs verified provenance plus authority-free retirement intents.

  Invalid provenance configuration is refused before reconciliation starts.
  A post-reconciliation attestation failure never rewrites the already-durable
  run receipt or invents a different standing; the returned error includes the
  exact receipt so the consequence remains receipted and replayable.
  """

  alias GgenIgniter.{EphemeralProjection, Receipt}
  alias GgenIgniter.Reactors.ReconcileReactor

  @type result :: %{
          receipt: Receipt.t(),
          projections: [EphemeralProjection.t()],
          provenance: [map()],
          retirement_intents: [map()]
        }

  @type attestation_error :: %{
          receipt: Receipt.t(),
          reason: term()
        }

  @doc """
  Runs the existing reconciliation court and, only after its durable `:alive`
  receipt exists, constructs v26.9.15 projection provenance from the exact
  output bytes named by that receipt.
  """
  @spec run(keyword(), keyword()) ::
          {:ok, result()}
          | {:error, Receipt.t()}
          | {:error, attestation_error()}
          | {:error, EphemeralProjection.refusal()}
  def run(reconcile_opts, provenance_opts)
      when is_list(reconcile_opts) and is_list(provenance_opts) do
    with {:ok, admitted_provenance} <-
           EphemeralProjection.admit_provenance_opts(provenance_opts) do
      case ReconcileReactor.run(reconcile_opts) do
        {:ok, %Receipt{} = receipt} -> attest_receipt(receipt, admitted_provenance)
        {:error, %Receipt{} = receipt} -> {:error, receipt}
      end
    end
  end

  @doc """
  Constructs provenance for an already durable receipt.

  Exposed separately so replay/qualification tooling can reconstruct the same
  evidence without repeating actuation. Only `:alive` receipts are eligible:
  a refused/compensated/build-broken attempt did not leave an admitted output
  set to treat as a manufactured projection.
  """
  @spec attest_receipt(Receipt.t(), keyword()) :: {:ok, result()} | {:error, attestation_error()}
  def attest_receipt(%Receipt{standing: :alive} = receipt, provenance_opts)
      when is_list(provenance_opts) do
    with {:ok, graph_digest} <- graph_digest(receipt),
         {:ok, receipt_hash} <- receipt_hash(receipt),
         {:ok, projections} <-
           build_projections(receipt, graph_digest, receipt_hash, provenance_opts) do
      {:ok,
       %{
         receipt: receipt,
         projections: projections,
         provenance: Enum.map(projections, &EphemeralProjection.provenance_statement/1),
         retirement_intents: Enum.map(projections, &retirement_intent!/1)
       }}
    else
      {:error, reason} -> {:error, %{receipt: receipt, reason: reason}}
    end
  end

  def attest_receipt(%Receipt{} = receipt, _provenance_opts) do
    {:error,
     %{
       receipt: receipt,
       reason: {:refused_ephemeral_attestation, :standing, receipt.standing}
     }}
  end

  defp build_projections(receipt, graph_digest, receipt_hash, provenance_opts) do
    Enum.reduce_while(receipt.files, {:ok, []}, fn path, {:ok, acc} ->
      case File.read(path) do
        {:ok, bytes} ->
          opts =
            provenance_opts
            |> Keyword.put(:name, path)
            |> Keyword.put(:graph_digest, graph_digest)

          with {:ok, projection} <- EphemeralProjection.manufacture(bytes, opts),
               {:ok, verified} <- EphemeralProjection.verify(projection, receipt_hash) do
            {:cont, {:ok, [verified | acc]}}
          else
            {:error, reason} -> {:halt, {:error, reason}}
          end

        {:error, reason} ->
          {:halt, {:error, {:ephemeral_projection_unreadable, path, reason}}}
      end
    end)
    |> case do
      {:ok, projections} -> {:ok, Enum.reverse(projections)}
      {:error, _reason} = error -> error
    end
  end

  defp graph_digest(%Receipt{metadata: metadata}) do
    case Map.fetch(metadata, "graph_hash") do
      {:ok, "sha256:" <> _ = digest} -> {:ok, digest}
      {:ok, other} -> {:error, {:refused_ephemeral_attestation, :graph_hash, other}}
      :error -> {:error, {:refused_ephemeral_attestation, :graph_hash, :missing}}
    end
  end

  defp receipt_hash(%Receipt{receipt_hash: "sha256:" <> _ = digest}), do: {:ok, digest}

  defp receipt_hash(%Receipt{receipt_hash: other}),
    do: {:error, {:refused_ephemeral_attestation, :receipt_hash, other}}

  defp retirement_intent!(projection) do
    {:ok, intent} = EphemeralProjection.retirement_intent(projection)
    intent
  end
end
