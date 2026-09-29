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

  @schema @schema_path |> File.read!() |> Jason.decode!()

  @entries @schema
           |> Map.fetch!("refusals")
           |> Enum.map(fn e ->
             %{
               code: String.to_atom(e["code"]),
               family: e["family"],
               retryable: e["retryable"],
               owner: e["owner"],
               fix_hint: e["fix_hint"],
               broken_term: e["broken_term"],
               not_applicable_reason: e["not_applicable_reason"],
               hint_group: e["hint_group"],
               example: e["example"]
             }
           end)

  # Internal sub-reasons that are emitted as bare `{:error, :reason}` /
  # `{:refused, :reason}` atoms but always surface under an already-covered
  # parent code (see the schema's top-level `wrapped_reasons`).
  @wrapped @schema
           |> Map.get("wrapped_reasons", [])
           |> Enum.map(fn w ->
             %{reason: w["reason"], parent: String.to_atom(w["parent"]), note: w["note"]}
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
          broken_term: String.t(),
          not_applicable_reason: String.t() | nil,
          hint_group: String.t() | nil,
          example: String.t()
        }
  @type wrapped :: %{reason: String.t(), parent: code(), note: String.t()}

  @doc "Every registry entry."
  @spec all() :: [entry()]
  def all, do: @entries

  @doc "Number of registered codes, derived from the schema (never hardcoded)."
  @spec count() :: non_neg_integer()
  def count, do: length(@entries)

  @doc "Declared internal sub-reasons and the registered code each surfaces under."
  @spec wrapped_reasons() :: [wrapped()]
  def wrapped_reasons, do: @wrapped

  @doc "True when `code` (atom or string, either case) is in the enum."
  @spec known?(code() | String.t()) :: boolean()
  def known?(code) when is_atom(code) or is_binary(code), do: match?({:ok, _}, fetch(code))
  def known?(_), do: false

  @doc "The registry entry for `code` (atom or string, either case)."
  @spec fetch(code() | String.t()) :: {:ok, entry()} | :error
  def fetch(code) when is_atom(code) and not is_nil(code),
    do: code |> Atom.to_string() |> fetch()

  def fetch(code) when is_binary(code) do
    case Map.fetch(@by_string, String.upcase(code)) do
      {:ok, atom} -> Map.fetch(@by_code, atom)
      :error -> :error
    end
  end

  def fetch(_), do: :error

  @doc """
  Upcased atoms of every `{:error, :atom}` / `{:refused, :atom}` literal in
  `source`. Used by the exhaustiveness test to check each is a registered code
  or a declared wrapped reason.
  """
  @spec scan_reason_atoms(String.t()) :: [String.t()]
  def scan_reason_atoms(source) when is_binary(source) do
    ~r/\{:(?:error|refused),\s*:([a-z][a-z0-9_]*)/
    |> Regex.scan(source, capture: :all_but_first)
    |> Enum.map(fn [a] -> String.upcase(a) end)
    |> Enum.uniq()
  end

  @doc """
  Canonical text form `REFUSED:<CODE> <detail>`. Atom and string codes are
  matched case-insensitively and emitted upcased. Raises `ArgumentError`
  naming the code when it is outside the enum (an unenumerated refusal is
  itself a defect). The detail is emitted verbatim after one separator space.
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
              "unknown refusal code #{inspect(code)} (#{String.upcase(to_string(code))}); " <>
                "add it to priv/schema/refusals.schema.json"
    end
  end

  @doc """
  Parses the canonical form and both legacy formats into `{code, detail}`.

  The detail is returned verbatim: only the single separator character after
  the code is dropped, so `parse(format(c, d)) == {:ok, {c, d}}` for every
  binary `d`. Codes are matched case-insensitively and normalised to upper
  case. `{:error, :not_a_refusal}` when the text (or a non-binary) is none of
  the forms, `{:error, {:unknown_code, string}}` when the shape matches but
  the code is outside the enum.
  """
  @spec parse(term()) ::
          {:ok, {code(), String.t()}} | {:error, :not_a_refusal | {:unknown_code, String.t()}}
  def parse(text) when is_binary(text) do
    cond do
      m = Regex.run(~r/\A\s*REFUSED\(([A-Za-z][A-Za-z0-9_]*)\)/, text, return: :index) ->
        finish(text, m)

      m =
          Regex.run(
            ~r/\A\s*REFUSED[:_]([A-Za-z][A-Za-z0-9_]*[A-Za-z0-9]):?(?=[ \t\r\n]|\z)/,
            text,
            return: :index
          ) ->
        finish(text, m)

      true ->
        {:error, :not_a_refusal}
    end
  end

  def parse(_), do: {:error, :not_a_refusal}

  # `m` is [whole, code] as {offset, length} pairs; the detail is everything
  # after the whole prefix, minus one leading separator character.
  defp finish(text, [{ws, wl}, {cs, cl}]) do
    code = text |> binary_part(cs, cl) |> String.upcase()
    rest = binary_part(text, ws + wl, byte_size(text) - ws - wl)

    detail =
      case rest do
        <<sep, tail::binary>> when sep in [?\s, ?\t, ?\r, ?\n] -> tail
        other -> other
      end

    resolve(code, detail)
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
        "| `#{e.code}` | #{e.family} | #{e.retryable} | #{e.broken_term} | `#{e.owner}` | #{e.fix_hint} |"
      end)

    Enum.join([header | rows], "\n")
  end

  @doc "Markdown table of the wrapped sub-reasons, for `docs/reference/refusals.md`."
  @spec wrapped_markdown() :: String.t()
  def wrapped_markdown do
    header = "| reason | surfaces under | note |\n|---|---|---|"

    rows =
      Enum.map(@wrapped, fn w -> "| `#{w.reason}` | `#{w.parent}` | #{w.note} |" end)

    Enum.join([header | rows], "\n")
  end
end
