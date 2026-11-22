defmodule Mix.Tasks.GgenIgniter.SpatialCourt do
  @shortdoc "Emit a Playwright Spatial Court from a SHACL PropertyGroup ontology"
  @moduledoc """
  Step-3 Spatial Court emitter — orthogonal to Semantic Jira courts.

      mix ggen_igniter.spatial_court --ontology PATH --out PATH \\
        [--base-url URL] [--route PATH] [--suite NAME] \\
        [--no-gestalt] [--no-text-spacing] [--template PATH]

  Reads Turtle (or `.nt`/`.nq`) containing `sh:PropertyGroup` nodes whose
  member property shapes carry `sh:group` + `shui:selector`
  (or named-IRI `data-testid` fallback), then writes a
  `*.spatial-court.spec.ts` Playwright court that sweeps
  `[320,375,393,414,600,768,840,1024,1280]` and asserts overflow / rRLG-lite /
  touch≥44 / gap≥8 / optional Gestalt + WCAG 1.4.12 text-spacing.

  Exit `0` on success (prints the written path); `1` typed refusal JSON on
  stderr; `2` invalid invocation.
  """

  use Mix.Task

  alias GgenIgniter.SpatialCourt

  @impl Mix.Task
  def run(args) do
    {opts, _rest, invalid} =
      OptionParser.parse(args,
        strict: [
          ontology: :string,
          out: :string,
          base_url: :string,
          route: :string,
          suite: :string,
          template: :string,
          gestalt: :boolean,
          text_spacing: :boolean,
          help: :boolean
        ],
        aliases: [h: :help, o: :ontology]
      )

    cond do
      opts[:help] ->
        Mix.shell().info(@moduledoc)

      invalid != [] ->
        refuse(2, %{"status" => "invalid_invocation", "reason" => "unknown_options", "detail" => invalid})

      !(is_binary(opts[:ontology]) and opts[:ontology] != "") ->
        refuse(2, %{"status" => "invalid_invocation", "reason" => "missing --ontology"})

      !(is_binary(opts[:out]) and opts[:out] != "") ->
        refuse(2, %{"status" => "invalid_invocation", "reason" => "missing --out"})

      true ->
        emit_court(opts)
    end
  end

  defp emit_court(opts) do
    render_opts =
      [
        out: opts[:out],
        base_url: opts[:base_url],
        route: opts[:route],
        suite: opts[:suite],
        template: opts[:template],
        gestalt: Keyword.get(opts, :gestalt, true),
        text_spacing: Keyword.get(opts, :text_spacing, true)
      ]
      |> Enum.reject(fn {_k, v} -> is_nil(v) end)

    with {:ok, court} <- SpatialCourt.from_ontology(opts[:ontology]),
         {:ok, path} <- SpatialCourt.emit(court, render_opts) do
      IO.puts(Jason.encode!(%{"status" => "ok", "path" => path}))
    else
      {:error, reason} ->
        refuse(1, %{"status" => "refused", "reason" => jsonable(reason)})
    end
  end

  defp refuse(code, map) do
    IO.puts(:stderr, Jason.encode!(map))
    exit({:shutdown, code})
  end

  defp jsonable(term) when is_atom(term), do: Atom.to_string(term)
  defp jsonable(term) when is_binary(term), do: term
  defp jsonable(term) when is_number(term), do: term
  defp jsonable(term) when is_list(term), do: Enum.map(term, &jsonable/1)

  defp jsonable(term) when is_tuple(term),
    do: term |> Tuple.to_list() |> Enum.map(&jsonable/1)

  defp jsonable(%{} = map), do: Map.new(map, fn {k, v} -> {to_string(k), jsonable(v)} end)
  defp jsonable(other), do: inspect(other)
end
