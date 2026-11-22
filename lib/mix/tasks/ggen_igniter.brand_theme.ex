defmodule Mix.Tasks.GgenIgniter.BrandTheme do
  @shortdoc "Emit Tailwind @theme fluid spacing CSS from a DTCG brand.toml"
  @moduledoc """
  OI-15 theme half — sibling of `mix ggen_igniter.spatial_court`.

      mix ggen_igniter.brand_theme --brand PATH --out PATH [--template PATH]

  Reads a DTCG 2025.10-aligned `*.brand.toml` (primitive → semantic →
  component, curly-brace `{token.path}` aliases), resolves aliases to
  `var(--spacing-*)`, and writes a Tailwind CSS v4 `@theme` stylesheet with
  fluid `clamp()+cqi` tokens plus Fourth Watch utility shell
  (`.fw-cq`, `.fw-shell`, touch floors, hover/pointer media).

  Exit `0` on success (prints JSON `{"status":"ok","path":...}`); `1` typed
  refusal JSON on stderr; `2` invalid invocation.
  """

  use Mix.Task

  alias GgenIgniter.BrandTheme

  @impl Mix.Task
  def run(args) do
    {opts, _rest, invalid} =
      OptionParser.parse(args,
        strict: [
          brand: :string,
          out: :string,
          template: :string,
          help: :boolean
        ],
        aliases: [h: :help, b: :brand, o: :out]
      )

    cond do
      opts[:help] ->
        Mix.shell().info(@moduledoc)

      invalid != [] ->
        refuse(2, %{"status" => "invalid_invocation", "reason" => "unknown_options", "detail" => invalid})

      !(is_binary(opts[:brand]) and opts[:brand] != "") ->
        refuse(2, %{"status" => "invalid_invocation", "reason" => "missing --brand"})

      !(is_binary(opts[:out]) and opts[:out] != "") ->
        refuse(2, %{"status" => "invalid_invocation", "reason" => "missing --out"})

      true ->
        emit_theme(opts)
    end
  end

  defp emit_theme(opts) do
    render_opts =
      [out: opts[:out], template: opts[:template]]
      |> Enum.reject(fn {_k, v} -> is_nil(v) end)

    with {:ok, brand} <- BrandTheme.from_brand(opts[:brand]),
         {:ok, path} <- BrandTheme.emit(brand, render_opts) do
      IO.puts(Jason.encode!(%{"status" => "ok", "path" => path, "tokens" => length(brand.tokens)}))
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
