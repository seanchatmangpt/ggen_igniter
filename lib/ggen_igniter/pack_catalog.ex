defmodule GgenIgniter.PackCatalog do
  @moduledoc """
  Read-only pack discovery: one map per pack directory under `priv/ggen`
  (and optionally an extra `--pack-dir` root), built by calling
  `GgenIgniter.Pack.parse_manifest/1`, `discover_queries/1` and
  `discover_templates/1` -- no parsing is reimplemented here.

  Each entry is a string-keyed-friendly atom map:

    * `:name` -- `pack.toml` `[pack].name`, else the directory basename
    * `:version`, `:description` -- from `pack.toml`, else `nil`
    * `:metadata_source` -- `:manifest` (pack.toml parsed), `:inferred`
      (no pack.toml; fields nil), or `:invalid_manifest` (pack.toml present
      but refused by `parse_manifest/1`; the diagnostic is in `:manifest_error`)
    * `:dir`, `:ontology` (path or `nil` when `ontology.ttl` is absent)
    * `:gates` -- `[%{name, path}]` from `gates/*.rq`
    * `:templates` -- `[%{stem, path, to, for_each}]`; `to`/`for_each` come
      from the template frontmatter (`nil` when there is none or it cannot be parsed)
    * `:required_flags` -- flags a caller must pass to render the pack
      (`--pack NAME:STEM` when several templates exist; `--for-each NAME`
      when a template fans out over a driver query)
    * `:origin` -- `:priv_ggen` or `:pack_dir`
    * `:hex_shipped` -- whether the pack is included in the hex package,
      mirroring `mix.exs` `shipped_packs/0` (`priv/ggen/*` minus any path
      containing `"ash"`); always `false` for `:pack_dir` origin

  Order is deterministic: sorted by `dir`.
  """

  alias GgenIgniter.Pack

  @type entry :: map()

  @doc """
  Lists packs. Options: `:priv_root` (default `"priv/ggen"`), `:pack_dir`
  (an extra pack root, or a single pack directory when it holds an
  `ontology.ttl`).
  """
  @spec list(keyword()) :: [entry()]
  def list(opts \\ []) do
    priv_root = Keyword.get(opts, :priv_root, "priv/ggen")

    priv = priv_root |> child_dirs() |> Enum.map(&entry(&1, :priv_ggen, priv_root))

    extra =
      case Keyword.get(opts, :pack_dir) do
        nil ->
          []

        dir ->
          dirs =
            if File.regular?(Path.join(dir, "ontology.ttl")), do: [dir], else: child_dirs(dir)

          Enum.map(dirs, &entry(&1, :pack_dir, priv_root))
      end

    (priv ++ extra) |> Enum.sort_by(& &1.dir)
  end

  defp child_dirs(root) do
    case File.ls(root) do
      {:ok, names} ->
        names |> Enum.sort() |> Enum.map(&Path.join(root, &1)) |> Enum.filter(&File.dir?/1)

      {:error, _} ->
        []
    end
  end

  defp entry(dir, origin, priv_root) do
    {name, version, description, source, error} =
      case Pack.parse_manifest(dir) do
        {:ok, m} ->
          {m.name, m.version, m.description, :manifest, nil}

        :absent ->
          {Path.basename(dir), nil, nil, :inferred, nil}

        {:refused, {:pack_manifest_invalid, diagnostic: d}} ->
          {Path.basename(dir), nil, nil, :invalid_manifest, d}
      end

    ontology = Pack.default_ontology(dir)
    templates = dir |> Pack.discover_templates() |> Enum.map(&template/1)

    %{
      name: name,
      version: version,
      description: description,
      metadata_source: source,
      manifest_error: error,
      dir: dir,
      ontology: if(File.regular?(ontology), do: ontology, else: nil),
      gates: dir |> Pack.discover_queries() |> Enum.map(fn {n, p} -> %{name: n, path: p} end),
      templates: templates,
      required_flags: required_flags(name, templates),
      origin: origin,
      hex_shipped: origin == :priv_ggen and shipped?(priv_root, Path.basename(dir))
    }
  end

  # mix.exs shipped_packs/0: Path.wildcard("priv/ggen/*") |> reject contains "ash"
  defp shipped?(priv_root, basename),
    do: not String.contains?(Path.join(priv_root, basename), "ash")

  defp template(path) do
    {to, for_each} =
      try do
        case path |> File.read!() |> GgenIgniter.Frontmatter.split_template() do
          {nil, _mode, _body} -> {nil, nil}
          {fm, _mode, _body} -> {fm.to, fm.for_each}
        end
      rescue
        _ -> {nil, nil}
      end

    stem = path |> Path.basename() |> String.split(".", parts: 2) |> List.first()
    %{stem: stem, path: path, to: to, for_each: for_each}
  end

  defp required_flags(name, templates) do
    stems =
      if length(templates) > 1,
        do: ["--pack #{name}:STEM (one of: #{Enum.map_join(templates, ", ", & &1.stem)})"],
        else: []

    for_each =
      templates
      |> Enum.map(& &1.for_each)
      |> Enum.reject(&is_nil/1)
      |> Enum.uniq()
      |> Enum.sort()
      |> Enum.map(&"--for-each #{&1}")

    stems ++ for_each
  end
end
