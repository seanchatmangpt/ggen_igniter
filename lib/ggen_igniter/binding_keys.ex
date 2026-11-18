defmodule GgenIgniter.BindingKeys do
  @moduledoc """
  Bounded admission for EEx/template binding keys derived from SPARQL
  result maps or named-query labels.

  Templates historically consume atom keys (`@foo` / `<%= foo %>`). Open
  `String.to_atom/1` on arbitrary SPARQL keys would mint BEAM atoms from
  hostile ontology/query text. This module admits only identifier-shaped
  keys (charset + length), then atomizes — not a closed allowlist (query
  authors choose var names), but refuses non-identifier minting.
  """

  @max_bytes 128
  @identifier ~r/^[A-Za-z_][A-Za-z0-9_]*$/

  @doc "Admit `key` as a binding atom, or raise `ArgumentError`."
  @spec atomize!(term()) :: atom()
  def atomize!(key) when is_atom(key), do: key

  def atomize!(key) when is_binary(key) do
    if byte_size(key) <= @max_bytes and Regex.match?(@identifier, key) do
      String.to_atom(key)
    else
      raise ArgumentError,
            "binding key #{inspect(key)} is not an admitted identifier " <>
              "(must match #{inspect(@identifier.source)}, <= #{@max_bytes} bytes)"
    end
  end

  def atomize!(key) do
    raise ArgumentError, "binding key must be a binary or atom, got: #{inspect(key)}"
  end
end
