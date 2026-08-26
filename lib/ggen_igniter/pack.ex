defmodule GgenIgniter.Pack do
  @moduledoc """
  Resolves the `priv/ggen/<pack-name>/` convention (or an explicit `--pack-dir`)
  into sane defaults for `--ontology`/`--query`/`--template`, per the pack
  convention design:

      priv/ggen/<pack-name>/
      ├── pack.toml            # optional, not read here
      ├── ontology.ttl          # default --ontology
      ├── gates/*.rq            # default --query source, one query per file
      └── templates/*.{eex,tmpl} # default --template source (single-file case)

  Pure helper, no `Igniter` dependency, so both `ggen_igniter.sync` and
  `ggen_igniter.doctor` (and tests) can call it directly.
  """

  @doc """
  Resolves the pack directory from `opts[:pack_dir]` (explicit override) or
  `opts[:pack]` (looked up under `priv/ggen/<name>/`). Raises `ArgumentError`
  if neither is given.
  """
  @spec resolve_dir!(keyword() | map()) :: String.t()
  def resolve_dir!(opts) do
    case fetch(opts, :pack_dir) || fetch_pack(opts) do
      nil ->
        raise ArgumentError, "either --pack NAME or --pack-dir DIR is required to resolve a pack"

      dir ->
        dir
    end
  end

  defp fetch_pack(opts) do
    case fetch(opts, :pack) do
      nil -> nil
      name -> Path.join(["priv", "ggen", name])
    end
  end

  defp fetch(opts, key) when is_map(opts), do: Map.get(opts, key)
  defp fetch(opts, key) when is_list(opts), do: Keyword.get(opts, key)

  @doc "Default `--ontology` path for `pack_dir`: `<pack_dir>/ontology.ttl`."
  @spec default_ontology(String.t()) :: String.t()
  def default_ontology(pack_dir), do: Path.join(pack_dir, "ontology.ttl")

  @doc """
  Discovers every `<pack_dir>/gates/*.rq` file, sorted lexically (so the
  `NNN_` numeric-prefix convention controls ordering), mapped to
  `{name, path}` where `name` is the filename stem with any leading
  `^\\d+_` digit-prefix stripped: `010_spec.rq` -> `"spec"`, `entities.rq` ->
  `"entities"` (no prefix, no change).
  """
  @spec discover_queries(String.t()) :: [{String.t(), String.t()}]
  def discover_queries(pack_dir) do
    pack_dir
    |> Path.join("gates/*.rq")
    |> Path.wildcard()
    |> Enum.sort()
    |> Enum.map(fn path -> {query_name(path), path} end)
  end

  defp query_name(path) do
    path
    |> Path.basename(".rq")
    |> String.replace(~r/^\d+_/, "")
  end

  @doc """
  Discovers the default `--template` under `<pack_dir>/templates/`.

  Returns `{:ok, path}` when exactly one `*.eex` or `*.tmpl` file exists,
  `{:error, :none}` when there are zero, or `{:error, {:ambiguous, paths}}`
  when there is more than one (no guessing which of N templates is "the" one).
  """
  @spec discover_template(String.t()) ::
          {:ok, String.t()} | {:error, :none} | {:error, {:ambiguous, [String.t()]}}
  def discover_template(pack_dir) do
    paths =
      [Path.wildcard(Path.join(pack_dir, "templates/*.eex")), Path.wildcard(Path.join(pack_dir, "templates/*.tmpl"))]
      |> List.flatten()
      |> Enum.sort()

    case paths do
      [] -> {:error, :none}
      [single] -> {:ok, single}
      many -> {:error, {:ambiguous, many}}
    end
  end
end
