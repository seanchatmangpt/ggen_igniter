defmodule GgenIgniter.Upgrades do
  @moduledoc """
  Version-keyed upgrader registry and range selection for `mix ggen_igniter.upgrade`
  (`mix igniter.upgrade ggen_igniter` passes `from to`).

  Each registered version maps to a module exporting `upgrade/2` (`igniter, opts`).
  An upgrader runs when `from < version <= to` (same window as
  `Igniter.Upgrades.run/5`), in ascending version order.

  Refusals are typed: `{:invalid_version, string}` and `{:downgrade, from, to}`.
  """

  @registry %{
    "26.9.28" => GgenIgniter.Upgrades.V26_9_28
  }

  @doc "Registered `version => module` map."
  @spec registry() :: %{String.t() => module()}
  def registry, do: @registry

  @doc "Upgrader modules to run for `from -> to`, ascending, or a typed refusal."
  @spec select(String.t(), String.t(), map()) ::
          {:ok, [module()]}
          | {:error, {:invalid_version, String.t()} | {:downgrade, String.t(), String.t()}}
  def select(from, to, registry \\ @registry) do
    with {:ok, f} <- parse(from),
         {:ok, t} <- parse(to),
         :ok <- check_order(f, t, from, to) do
      mods =
        registry
        |> Enum.filter(fn {v, _} ->
          {:ok, pv} = parse(v)
          Version.compare(pv, f) == :gt and Version.compare(pv, t) != :gt
        end)
        |> Enum.sort_by(fn {v, _} -> Version.parse!(v) end, Version)
        |> Enum.map(&elem(&1, 1))

      {:ok, mods}
    end
  end

  defp check_order(f, t, from, to) do
    if Version.compare(t, f) == :lt, do: {:error, {:downgrade, from, to}}, else: :ok
  end

  defp parse(v) when is_binary(v) do
    case Version.parse(v) do
      {:ok, ver} -> {:ok, ver}
      :error -> {:error, {:invalid_version, v}}
    end
  end

  defp parse(v), do: {:error, {:invalid_version, inspect(v)}}
end
