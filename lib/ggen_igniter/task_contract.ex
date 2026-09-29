defmodule GgenIgniter.TaskContract do
  @moduledoc """
  The uniform machine contract for `mix ggen_igniter.*` tasks: one exit-code table and one
  JSON envelope, so a CI job can branch on the exit code alone and parse one stable shape.

  ## Exit-code table (`exit_codes/0`)

  | code | name          | meaning |
  |------|---------------|---------|
  | 0    | `:ok`         | succeeded / clean |
  | 1    | `:refusal`    | a typed refusal or a failed gate (the run was admitted-out or verification failed) |
  | 2    | `:invocation` | bad invocation (missing/unknown flag, unresolvable input) |
  | 3    | `:unsupported`| the request is outside the task's supported scope (`plan`'s read-only path) |
  | 4    | `:drift`      | `sync --check`: committed generated files differ from what the ontology produces |

  Collision analysis: `plan` already used 0/2/3, the `epoch.*` tasks use 0/1/2 (1 = refusal or
  unknown provenance), `verify`/`doctor` use 0/1. Code 4 was unused by every task, so drift
  gets its own code and never aliases a refusal (1) that means "the tool refused", not "the tree
  is stale".

  ## Envelope (`envelope/2`)

      {"schema_version": 1, "task": "sync", "ok": false, "exit_code": 4,
       "standing": "BLOCKED", "refusal": null, "data": {...}}

  `refusal` is `null` or `{"code": "PACK_DIGEST_MISMATCH", "detail": "..."}` (text form
  `REFUSED:<CODE> <detail>`, see `refusal_text/1`). `standing` follows the doctrine vocabulary:
  `ALIVE` (0), `REFUSED` (1), `UNKNOWN` (2), `UNSUPPORTED` (3), `BLOCKED` (4).

  `encode/1` is deterministic: object keys are sorted recursively, so the same envelope always
  encodes to the same bytes.
  """

  @schema_version 1

  @table [
    %{code: 0, name: :ok, standing: "ALIVE", meaning: "succeeded / clean"},
    %{code: 1, name: :refusal, standing: "REFUSED", meaning: "typed refusal or failed gate"},
    %{code: 2, name: :invocation, standing: "UNKNOWN", meaning: "bad invocation"},
    %{
      code: 3,
      name: :unsupported,
      standing: "UNSUPPORTED",
      meaning: "outside the task's supported scope"
    },
    %{
      code: 4,
      name: :drift,
      standing: "BLOCKED",
      meaning: "generated files differ from what the ontology produces (sync --check)"
    }
  ]

  @type name :: :ok | :refusal | :invocation | :unsupported | :drift

  @doc "The documented exit-code table, ordered by code."
  @spec exit_codes() :: [%{code: 0..4, name: name(), standing: String.t(), meaning: String.t()}]
  def exit_codes, do: @table

  @doc "Numeric exit code for a table name."
  @spec exit_code(name()) :: 0..4
  def exit_code(name) when is_atom(name) do
    case Enum.find(@table, &(&1.name == name)) do
      %{code: code} -> code
      nil -> raise ArgumentError, "unknown exit-code name #{inspect(name)}"
    end
  end

  @doc "Doctrine standing string for a table name."
  @spec standing(name()) :: String.t()
  def standing(name) do
    %{standing: s} = Enum.find(@table, &(&1.name == name))
    s
  end

  @doc """
  Builds the envelope map for `task` (string). `outcome` is a table name; `opts`:
  `:data` (map, default `%{}`), `:refusal` (`{code, detail}` or `nil`).
  """
  @spec envelope(String.t(), name(), keyword()) :: map()
  def envelope(task, outcome, opts \\ []) when is_binary(task) and is_atom(outcome) do
    refusal =
      case Keyword.get(opts, :refusal) do
        nil -> nil
        {code, detail} -> %{"code" => code_string(code), "detail" => to_string(detail)}
      end

    %{
      "schema_version" => @schema_version,
      "task" => task,
      "ok" => outcome == :ok,
      "exit_code" => exit_code(outcome),
      "standing" => standing(outcome),
      "refusal" => refusal,
      "data" => Keyword.get(opts, :data, %{})
    }
  end

  @doc "Deterministic (recursively key-sorted) JSON encoding of an envelope or any map."
  @spec encode(term()) :: String.t()
  def encode(term), do: term |> sort_keys() |> Jason.encode!()

  @doc "Human-readable typed-refusal line: `REFUSED:<CODE> <detail>`."
  @spec refusal_text({atom() | String.t(), term()}) :: String.t()
  def refusal_text({code, detail}), do: "REFUSED:#{code_string(code)} #{detail}"

  @doc "Names of the documented exit codes, for documentation-completeness checks."
  @spec documented_codes() :: [0..4]
  def documented_codes, do: Enum.map(@table, & &1.code)

  defp code_string(code) when is_atom(code), do: code |> Atom.to_string() |> String.upcase()
  defp code_string(code) when is_binary(code), do: code

  defp sort_keys(%{} = map) when not is_struct(map) do
    map
    |> Enum.map(fn {k, v} -> {to_string(k), sort_keys(v)} end)
    |> Enum.sort_by(&elem(&1, 0))
    |> Jason.OrderedObject.new()
  end

  defp sort_keys(list) when is_list(list), do: Enum.map(list, &sort_keys/1)
  defp sort_keys(other), do: other
end
