defmodule GgenIgniter.Refusals do
  @moduledoc """
  The enumerated, machine-readable refusal vocabulary.

  The registry is `priv/schema/refusals.schema.json` (its top-level `refusals`
  array; `$defs.code` is the closed enum of every code). It is embedded at
  compile time (`@external_resource`), so editing the schema recompiles this
  module. Regenerate the reference table with
  `mix run -e 'IO.puts(GgenIgniter.Refusals.markdown())'` (see
  `docs/reference/refusals.md`).

  ## Canonical text form

      REFUSED:<CODE> <detail>

  A code is an upper-snake-case atom such as `:LEGACY_EDIT` (the `REFUSED_`
  prefix of epoch verdict atoms is not part of the code). `parse/1` also
  accepts the two legacy emitter formats and maps them to `{code, detail}`:

    * `REFUSED(code) subject: detail` (semantic_jira bootstrap/prose) — the
      code is upcased, the detail is `"subject: detail"`;
    * `REFUSED_<CODE> detail` (epoch verdicts, hand_authored) — bare token.

  Emitters are not rewritten by this module; it is the target vocabulary.

  ## Examples

      iex> GgenIgniter.Refusals.format(:LEGACY_EDIT, "lib/a.ex")
      "REFUSED:LEGACY_EDIT lib/a.ex"

      iex> GgenIgniter.Refusals.parse("REFUSED(input_invalid) goal: bad json")
      {:ok, {:INPUT_INVALID, "goal: bad json"}}

      iex> GgenIgniter.Refusals.parse("REFUSED_LEGACY_EDIT lib/a.ex")
      {:ok, {:LEGACY_EDIT, "lib/a.ex"}}
  """

  @schema_path Path.expand("../../priv/schema/refusals.schema.json", __DIR__)
  @external_resource @schema_path

  @entries @schema_path
           |> File.read!()
           |> Jason.decode!()
           |> Map.fetch!("refusals")
           |> Enum.map(fn e ->
             %{
               code: String.to_atom(e["code"]),
               family: e["family"],
               retryable: e["retryable"],
               owner: e["owner"],
               fix_hint: e["fix_hint"],
               broken_term: e["broken_term"],
               example: e["example"]
             }
           end)

  @by_code Map.new(@entries, &{&1.code, &1})
  @by_string Map.new(@entries, &{Atom.to_string(&1.code), &1.code})

  @type code :: atom()
  @type entry :: %{
          code: code(),
          family: String.t(),
          retryable: boolean(),
          owner: String.t(),
          fix_hint: String.t(),
          broken_term: String.t() | nil,
          example: String.t()
        }

  @doc "Every registry entry."
  @spec all() :: [entry()]
  def all, do: @entries

  @doc "True when `code` (atom or string, either case for strings) is in the enum."
  @spec known?(code() | String.t()) :: boolean()
  def known?(code) when is_atom(code), do: Map.has_key?(@by_code, code)
  def known?(code) when is_binary(code), do: Map.has_key?(@by_string, String.upcase(code))

  @doc "The registry entry for `code`."
  @spec fetch(code() | String.t()) :: {:ok, entry()} | :error
  def fetch(code) when is_atom(code), do: Map.fetch(@by_code, code)

  def fetch(code) when is_binary(code) do
    case Map.fetch(@by_string, String.upcase(code)) do
      {:ok, atom} -> Map.fetch(@by_code, atom)
      :error -> :error
    end
  end

  @doc """
  Canonical text form `REFUSED:<CODE> <detail>`. Raises `ArgumentError` for a
  code outside the enum (an unenumerated refusal is itself a defect).
  """
  @spec format(code() | String.t(), String.t()) :: String.t()
  def format(code, detail \\ "") do
    case fetch(code) do
      {:ok, %{code: c}} ->
        case to_string(detail) do
          "" -> "REFUSED:#{c}"
          d -> "REFUSED:#{c} #{d}"
        end

      :error ->
        raise ArgumentError,
              "unknown refusal code #{inspect(code)}; add it to refusals.schema.json"
    end
  end

  @doc """
  Parses the canonical form and both legacy formats into `{code, detail}`.
  `{:error, :not_a_refusal}` when the text is none of them,
  `{:error, {:unknown_code, string}}` when the shape matches but the code is
  outside the enum.
  """
  @spec parse(String.t()) ::
          {:ok, {code(), String.t()}} | {:error, :not_a_refusal | {:unknown_code, String.t()}}
  def parse(text) when is_binary(text) do
    text = String.trim(text)

    cond do
      m = Regex.run(~r/\AREFUSED\(([A-Za-z][A-Za-z0-9_]*)\)\s*(.*)\z/s, text) ->
        [_, code, detail] = m
        resolve(String.upcase(code), detail)

      m = Regex.run(~r/\AREFUSED[:_]([A-Z][A-Z0-9_]*[A-Z0-9]):?(?:\s+(.*))?\z/s, text) ->
        [_, code | rest] = m
        resolve(code, List.first(rest) || "")

      true ->
        {:error, :not_a_refusal}
    end
  end

  defp resolve(code, detail) do
    case Map.fetch(@by_string, code) do
      {:ok, atom} -> {:ok, {atom, detail}}
      :error -> {:error, {:unknown_code, code}}
    end
  end

  @doc "Markdown table of the registry, for `docs/reference/refusals.md`."
  @spec markdown() :: String.t()
  def markdown do
    header =
      "| code | family | retryable | broken_term | owner | fix_hint |\n|---|---|---|---|---|---|"

    rows =
      Enum.map(@entries, fn e ->
        "| `#{e.code}` | #{e.family} | #{e.retryable} | #{e.broken_term || "-"} | `#{e.owner}` | #{e.fix_hint} |"
      end)

    Enum.join([header | rows], "\n")
  end
end
