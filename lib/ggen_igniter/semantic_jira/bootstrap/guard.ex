defmodule GgenIgniter.SemanticJira.Bootstrap.Guard do
  @moduledoc """
  Input and output fences of the cold bootstrap (GC-26.9.23 gate GC23-1,
  ARD section 16 forbidden dependencies; no-LLM court env F3).

    * `forbidden_path/1` -- a path is refused when any component of its
      expanded form OR of its symlink-resolved real path is `.claude` or
      `.zcode` (Claude/ZCode homes: transcripts, memory, session state), or
      contains `transcript` (case-insensitive). Checking the real path means
      a symlink planted in a scratch dir cannot smuggle `~/.claude` in.
    * `llm_credentials/1` -- the names (never the values) of LLM credential
      variables in an environment map: `ANTHROPIC_*`, `CLAUDE_*`, `OPENAI_*`,
      `ZAI_*`, `Z_AI_*`, `GLM_*`, `ZCODE_*`. A bootstrap run with any of them
      set is refused `llm_credential_present` (broken_term `mu_on_O`).
    * `absolute_paths/1` -- JSON pointers of every string in the state that
      is an absolute path or names a home directory; the state must be
      host-independent so two machines (or two HOMEs) reconstruct the same
      bytes.
  """

  @forbidden_components [".claude", ".zcode"]
  @llm_prefixes ~w(ANTHROPIC_ CLAUDE_ OPENAI_ ZAI_ Z_AI_ GLM_ ZCODE_)
  @max_link_hops 40

  @doc "The LLM credential variable prefixes the bootstrap refuses."
  @spec llm_prefixes() :: [String.t()]
  def llm_prefixes, do: @llm_prefixes

  @doc "Why `path` may not be read, or `nil` when it may."
  @spec forbidden_path(Path.t()) :: String.t() | nil
  def forbidden_path(path) when is_binary(path) do
    expanded = Path.expand(path)

    [expanded, real_path(expanded)]
    |> Enum.uniq()
    |> Enum.find_value(&forbidden_reason/1)
  end

  defp forbidden_reason(path) do
    components = Path.split(path)

    cond do
      Enum.any?(components, &(&1 in @forbidden_components)) ->
        "#{path} is under a Claude/ZCode home (.claude/.zcode); ARD section 16 forbids " <>
          "transcripts, conversation memory and session state as bootstrap inputs"

      Enum.any?(components, &String.contains?(String.downcase(&1), "transcript")) ->
        "#{path} is a transcript path; ARD section 16 forbids transcripts as bootstrap inputs"

      true ->
        nil
    end
  end

  @doc """
  The symlink-resolved absolute form of `path` (every existing component is
  resolved; missing trailing components are kept as written).
  """
  @spec real_path(Path.t()) :: Path.t()
  def real_path(path), do: resolve(path |> Path.expand() |> Path.split(), nil, 0)

  defp resolve(components, _done, hops) when hops > @max_link_hops,
    do: Path.join(components)

  defp resolve([], done, _hops), do: done || "/"

  defp resolve([component | rest], done, hops) do
    current = if done, do: Path.join(done, component), else: component

    case File.read_link(current) do
      {:ok, target} ->
        base = done || "/"
        target |> Path.expand(base) |> Path.split() |> Kernel.++(rest) |> resolve(nil, hops + 1)

      {:error, _not_a_link} ->
        resolve(rest, current, hops)
    end
  end

  @doc "Sorted names of LLM credential variables present (non-empty) in `env`."
  @spec llm_credentials(%{optional(String.t()) => String.t()}) :: [String.t()]
  def llm_credentials(env) when is_map(env) do
    env
    |> Enum.filter(fn {name, value} ->
      is_binary(name) and value not in [nil, ""] and
        Enum.any?(@llm_prefixes, &String.starts_with?(name, &1))
    end)
    |> Enum.map(&elem(&1, 0))
    |> Enum.sort()
  end

  @doc """
  JSON pointers (`/orders/V23-B/title`) of every string value in `state`
  that starts with `/` or contains `/Users/` or `/home/`.
  """
  @spec absolute_paths(term()) :: [String.t()]
  def absolute_paths(state), do: state |> walk("") |> Enum.sort()

  defp walk(%{} = map, pointer) when not is_struct(map) do
    Enum.flat_map(map, fn {key, value} -> walk(value, pointer <> "/" <> to_string(key)) end)
  end

  defp walk(list, pointer) when is_list(list) do
    list
    |> Enum.with_index()
    |> Enum.flat_map(fn {value, index} -> walk(value, "#{pointer}/#{index}") end)
  end

  defp walk(value, pointer) when is_binary(value) do
    if String.starts_with?(value, "/") or String.contains?(value, ["/Users/", "/home/"]),
      do: [pointer],
      else: []
  end

  defp walk(_value, _pointer), do: []
end
