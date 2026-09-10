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
                 "native",
                 "tera_wasm_renderer",
                 "target",
                 "wasm32-wasip1",
                 "release",
                 "tera_wasm_renderer.wasm"
               ])
             )

  @doc "Absolute path this module loads the compiled wasm module from."
  @spec wasm_path() :: String.t()
  def wasm_path, do: @wasm_path

  @doc """
  True when `template_path` ends in `.tera` -- the shared predicate real call
  sites use to route a template through this WASM renderer instead of
  `GgenIgniter.Render`'s EEx path. `template_path` may be `nil` (e.g. a
  literal `:out` path template that was never read from a file), in which
  case this always returns `false`.

  Deliberately extension-only, NOT content-sniffing for `{%`: a real fixture
  (`test/fixtures/ash_manufacture_pack/templates/manufacture.ex.eex:434`)
  contains the literal Elixir tuple/map syntax `{%{igniter | ...}` as
  ordinary EEx-template body text -- an earlier content-sniffing version of
  this predicate (`String.contains?(template_string, "{%")`) misrouted that
  real `.eex` template into the tera parser, which then failed to parse it
  (confirmed the hard way: `mix test`'s real full-suite run regressed 14
  tests this way before the fix). `template_string` is still accepted as a
  parameter for API stability / potential future refinement, but is
  currently unused.
  """
  @spec tera_template?(String.t() | nil, String.t()) :: boolean()
  def tera_template?(template_path, template_string) when is_binary(template_string) do
    is_binary(template_path) and String.ends_with?(template_path, ".tera")
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
