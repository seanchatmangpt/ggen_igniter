defmodule Mix.Tasks.GgenIgniter.Sa2a.Evidence do
  @moduledoc """
  Admits an authority-free SA2A semantic-evidence envelope read from `PATH`.

      mix ggen_igniter.sa2a.evidence PATH

  Prints the JSON reference on admission; raises with the typed refusal
  otherwise. Admission itself lives in `GgenIgniter.SA2A.SemanticEvidence`.
  """
  use Mix.Task

  @shortdoc "Admit an authority-free SA2A semantic-evidence envelope"

  @impl Mix.Task
  def run(args) do
    Mix.Task.run("app.start")

    case args do
      [path] ->
        path
        |> File.read!()
        |> GgenIgniter.SA2A.SemanticEvidence.reference()
        |> emit()

      _ ->
        Mix.raise("usage: mix ggen_igniter.sa2a.evidence PATH")
    end
  end

  defp emit({:ok, ref}), do: Mix.shell().info(Jason.encode!(ref))
  defp emit({:error, refusal}), do: Mix.raise("semantic evidence refused: #{inspect(refusal)}")
end
