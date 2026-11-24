defmodule GgenIgniter.Parity do
  @moduledoc """
  Mechanical ggen-parity register for template frontmatter.

  Reads the field list of the Rust `Frontmatter` struct
  (`<ggen>/crates/ggen-engine/src/template.rs`), diffs it against `GgenIgniter.Frontmatter`'s
  struct keys, and classifies each field by where igniter consumes it:

    * `:pack_sync` -- implemented by `GgenIgniter.PackFrontmatter.Sync`
      (everything not in its `unsupported/0` list)
    * `:mix_sync` -- implemented only by the `mix ggen_igniter.sync` path
      (`inject`, `before`, `after`, `at_line`, `sh_before`, `sh_after`)
    * `:internal` -- pipeline-set, never authored; not required in the Elixir struct
    * `:declared` -- mirrored in the struct, no consumer (registered divergence)

  `check/1` fails (`{:error, report}`) when a Rust field is absent from the Elixir struct.
  When the ggen checkout is absent it returns `{:skip, reason}` -- never a pass.
  """

  alias GgenIgniter.PackFrontmatter.Sync

  # Set by ggen's sync pipeline from the admission receipt, "never authored in template
  # frontmatter" (template.rs doc comments) -- not part of the authored surface.
  @internal ~w(receipt_generation envelope canonical_identity)a
  # `prefixes`/`base` only apply alongside `rdf`/`rdf_inline` (ggen ignores them otherwise);
  # those refuse loudly here, so the two are moot. `determinism` has no consumer.
  @moot ~w(determinism prefixes base)a
  @mix_sync ~w(inject before after at_line sh_before sh_after)a
  @rust_rel "crates/ggen-engine/src/template.rs"

  @type row :: %{
          field: atom(),
          in_elixir: boolean(),
          status: :pack_sync | :mix_sync | :declared | :internal
        }

  @spec rust_fields(String.t()) :: [atom()]
  def rust_fields(source) do
    source
    |> String.split("pub struct Frontmatter {", parts: 2)
    |> Enum.at(1, "")
    |> String.split("\n}", parts: 2)
    |> hd()
    |> then(&Regex.scan(~r/^\s*pub ([a-z_]+):/m, &1))
    |> Enum.map(fn [_, f] -> String.to_atom(f) end)
  end

  @spec check(keyword()) :: {:ok, [row()]} | {:error, [row()]} | {:skip, String.t()}
  def check(opts \\ []) do
    ggen = Keyword.get(opts, :ggen_dir, Path.expand("~/ggen"))
    path = Path.join(ggen, @rust_rel)

    case File.read(path) do
      {:error, _} ->
        {:skip, "ggen checkout absent: #{path}"}

      {:ok, src} ->
        elixir = %GgenIgniter.Frontmatter{to: ""} |> Map.from_struct() |> Map.keys()
        unsupported = Sync.unsupported()

        rows =
          for f <- rust_fields(src) do
            %{
              field: f,
              in_elixir: f in elixir or f in @internal,
              status:
                cond do
                  f in @internal -> :internal
                  f in @mix_sync -> :mix_sync
                  f in unsupported or f in @moot -> :declared
                  true -> :pack_sync
                end
            }
          end

        if Enum.all?(rows, & &1.in_elixir), do: {:ok, rows}, else: {:error, rows}
    end
  end

  @spec render([row()]) :: String.t()
  def render(rows) do
    body =
      Enum.map_join(rows, "\n", fn r ->
        "| `#{r.field}` | #{cond do
          r.status == :internal -> "n/a"
          r.in_elixir -> "yes"
          true -> "MISSING"
        end} | #{r.status} |"
      end)

    "| field | in igniter struct | consumer |\n|---|---|---|\n" <> body <> "\n"
  end
end
