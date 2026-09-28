defmodule GgenIgniter.Render.TeraWasm do
  @moduledoc """
  Real WASM-hosted Tera renderer: loads the compiled `native/tera_wasm_renderer`
  `wasm32-wasip1` module (the real `tera` crate, via `Wasmex`) and drives its
  `alloc`/`render`/`result_len` ptr+len ABI (see that crate's `src/lib.rs` for
  the full calling-convention doc) to render an actual Tera template string
  against a JSON-encoded context.

  This is a separate, additional engine alongside `GgenIgniter.Render` (stdlib
  EEx, the default) and `GgenIgniter.Render.Tera` (the hand-rolled, no-WASM
  Tera subset engine) -- neither of those is modified or replaced by this
  module's existence. `tera_template?/2` is the shared dispatch predicate the
  real call sites (`GgenIgniter.Reconcile.run/1`,
  `GgenIgniter.Reactors.ReconcileReactor.render_target/3`) use to decide
  whether a given template routes here instead of through EEx.
  """

  @wasm_path Path.expand(
               Path.join([
                 __DIR__,
                 "..",
                 "..",
                 "..",
                 "wasm-artifacts",
                 "tera_wasm_renderer.wasm"
               ])
             )

  @doc "Absolute path this module loads the compiled wasm module from."
  @spec wasm_path() :: String.t()
  def wasm_path, do: @wasm_path

  @doc """
  True when `template_path` names a Tera template -- the shared predicate real
  call sites use to route a template (body, frontmatter `to:`/`out`) through
  this WASM renderer instead of `GgenIgniter.Render`'s EEx path. `template_path`
  may be `nil` (e.g. a literal `:out` path template that was never read from a
  file), in which case this always returns `false`.

    * `*.tera` -- always Tera.
    * `*.tmpl` -- Tera, the ggen-marketplace convention (`templates/*.tmpl` in
      Tera syntax, frontmatter `to: "lib/{{ package_name }}/resource.ex"`).
      The one exception is a legacy `.tmpl` written in EEx syntax: a body that
      contains an EEx tag (`<%`) and NO Tera delimiter (`{{`, `{%`, `{#`)
      keeps rendering through EEx, so pre-existing EEx-in-`.tmpl` templates do
      not break. A body with neither marker (plain text) renders identically
      either way and is routed to Tera.
    * everything else (`*.eex`, unknown) -- EEx.

  Deliberately extension-driven, NOT content-sniffing for `{%` on other
  extensions: a real fixture
  (`test/fixtures/ash_manufacture_pack/templates/manufacture.ex.eex:434`)
  contains the literal Elixir tuple/map syntax `{%{igniter | ...}` as
  ordinary EEx-template body text -- an earlier content-sniffing version of
  this predicate (`String.contains?(template_string, "{%")`) misrouted that
  real `.eex` template into the tera parser (14 tests regressed). Sniffing is
  confined to disambiguating `.tmpl`.
  """
  @spec tera_template?(String.t() | nil, String.t()) :: boolean()
  def tera_template?(template_path, template_string) when is_binary(template_string) do
    cond do
      not is_binary(template_path) -> false
      String.ends_with?(template_path, ".tera") -> true
      String.ends_with?(template_path, ".tmpl") -> not eex_syntax_only?(template_string)
      true -> false
    end
  end

  defp eex_syntax_only?(body) do
    String.contains?(body, "<%") and
      not (String.contains?(body, "{{") or String.contains?(body, "{%") or
             String.contains?(body, "{#"))
  end

  @doc """
  Renders `string` (a template body, or a frontmatter `to:`/`out` path
  template) with the engine `template_path`/`kind_body` select via
  `tera_template?/2`: real Tera through `render/2`, else stdlib EEx through
  `GgenIgniter.Render.render/2`. `kind_body` is the template BODY used only to
  decide the engine (so a frontmatter `to:` follows the same engine as its
  template body). Raises on a Tera error.
  """
  @spec render_for!(String.t() | nil, String.t(), String.t(), keyword() | map()) :: String.t()
  def render_for!(template_path, kind_body, string, bindings) do
    if tera_template?(template_path, kind_body) do
      case render(string, bindings) do
        {:ok, rendered} -> rendered
        {:error, reason} -> raise "GgenIgniter.Render.TeraWasm: #{inspect(reason)}"
      end
    else
      GgenIgniter.Render.render(string, bindings)
    end
  end

  @doc """
  Renders `template` (real Tera syntax) against `context` (a map -- atom or
  string keys; keyword lists are accepted and normalized to a map) using the
  real compiled `native/tera_wasm_renderer` wasm module via a real `Wasmex`
  host instance. Returns `{:ok, rendered}` on success, `{:error, reason}` on
  any failure (missing wasm artifact, bad JSON context, template parse/render
  error reported by the real `tera` crate via the `"ERROR: "`-prefixed
  convention documented on the wasm module).
  """
  @spec render(String.t(), map() | keyword()) :: {:ok, String.t()} | {:error, term()}
  def render(template, context) when is_binary(template) do
    context_map = if Keyword.keyword?(context), do: Map.new(context), else: context
    context_json = Jason.encode!(context_map)

    with {:ok, wasm_bytes} <- read_wasm(),
         {:ok, pid} <- Wasmex.start_link(%{bytes: wasm_bytes, wasi: true}),
         {:ok, store} <- Wasmex.store(pid),
         {:ok, memory} <- Wasmex.memory(pid),
         {:ok, template_ptr} <- alloc(pid, byte_size(template)),
         :ok <- Wasmex.Memory.write_binary(store, memory, template_ptr, template),
         {:ok, context_ptr} <- alloc(pid, byte_size(context_json)),
         :ok <- Wasmex.Memory.write_binary(store, memory, context_ptr, context_json),
         {:ok, [result_ptr]} <-
           Wasmex.call_function(pid, "render", [
             template_ptr,
             byte_size(template),
             context_ptr,
             byte_size(context_json)
           ]),
         {:ok, [result_len]} <- Wasmex.call_function(pid, "result_len", []),
         result <- Wasmex.Memory.read_string(store, memory, result_ptr, result_len) do
      case result do
        "ERROR: " <> reason -> {:error, reason}
        rendered -> {:ok, rendered}
      end
    end
  end

  defp alloc(pid, size) do
    case Wasmex.call_function(pid, "alloc", [size]) do
      {:ok, [ptr]} -> {:ok, ptr}
      {:error, reason} -> {:error, reason}
    end
  end

  defp read_wasm do
    if File.exists?(@wasm_path) do
      {:ok, File.read!(@wasm_path)}
    else
      {:error, "GgenIgniter.Render.TeraWasm: compiled wasm module not found at #{@wasm_path}"}
    end
  end
end
