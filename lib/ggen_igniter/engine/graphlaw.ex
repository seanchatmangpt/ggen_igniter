defmodule GgenIgniter.Engine.Graphlaw do
  @moduledoc """
  Runs SPARQL SELECT queries through the graphlaw WebAssembly module
  (`~/graphlaw/wasm` -> `graphlaw_wasm.wasm`, JSON-over-linear-memory ABI:
  `gl_alloc`/`gl_call`/`gl_free`), hosted in-process by `wasmex` over a WASI
  store -- a real, independent SPARQL engine identity (PurRDF), alongside the
  `sparql` hex package, remote QLever, and the native oxigraph NIF.

  Same `[map()]` row-list contract as every other `GgenIgniter.Engine`
  implementation; rows use the same PLAIN normalization as
  `GgenIgniter.Query.Oxigraph`: string keys, plain unwrapped string values
  (IRIs without angle brackets, literals as their lexical form, blank nodes as
  their label). Unbound (null) bindings are omitted from the row map.

  ## Wasm artifact

  The module is MIT-licensed upstream (a fork of the RoXi reasoning engine,
  Ghent University - imec; see the graphlaw repository's LICENSE) and the
  artifact ships inside this hex package at `priv/graphlaw_wasm.wasm`
  (sha256 `8bfff66cccd1e1a4834d61a893888bb479f046c1da1152a29098be7de0fe71a8`),
  so hex consumers get a working graphlaw engine with no extra download.

  `prepare!/2` resolves the artifact in this order:

  1. `Application.get_env(:ggen_igniter, :graphlaw_wasm_path)` (explicit
     override);
  2. the packaged `priv/graphlaw_wasm.wasm` inside this application;
  3. the built-in dev default
     `~/graphlaw/target/wasm32-wasip1/wasm/graphlaw_wasm.wasm`.

  A missing (or non-compilable) artifact fails fast in `prepare!/2` with a
  clear, typed `RuntimeError` naming the exact paths tried and the exact
  build/download commands (a matching checksummed `graphlaw.wasm` is also
  attached to each graphlaw GitHub release), so a sync run never half-fails
  mid-query.

  ## ABI details (from ~/graphlaw/wasm/src/lib.rs and ~/graphlaw/src/abi.rs)

  1. `gl_alloc(len) -> ptr` (null/0 on limit refusal)
  2. host writes the UTF-8 JSON request
     `{"op": "sparql", "data": {"text": <turtle>, "hint": "ttl"}, "query": <query>}`
     into linear memory at `ptr`
  3. `gl_call(ptr, len) -> packed` where `packed = (out_ptr << 32) | out_len`
  4. host reads `out_len` bytes at `out_ptr`, then `gl_free(out_ptr, out_len)`

  A graphlaw response is always JSON: `{"ok": true, ...}` or
  `{"ok": false, "error": {kind, engine, dialect, message, details?}}`; the
  error message is surfaced verbatim in the raised `RuntimeError`.
  """

  @behaviour GgenIgniter.Engine

  import Bitwise, only: [bsr: 2, band: 2]

  @default_wasm_path "~/graphlaw/target/wasm32-wasip1/wasm/graphlaw_wasm.wasm"
  @packaged_wasm_path "priv/graphlaw_wasm.wasm"
  @wasm_sha256 "8bfff66cccd1e1a4834d61a893888bb479f046c1da1152a29098be7de0fe71a8"

  @doc """
  Instantiates the graphlaw wasm module and loads `graph` into the context as
  Turtle text (graphlaw's `op: "sparql"` parses the `data` spec itself, so no
  eager RDF parse happens in `prepare!/2`).

  Returns `%{store: store, module: module, instance: instance, memory: memory,
  turtle: turtle}`.
  """
  @impl true
  @spec prepare!(RDF.Graph.t(), keyword()) :: map()
  def prepare!(%RDF.Graph{} = graph, _opts) do
    wasm_path = wasm_path()
    wasm_bytes = read_wasm!(wasm_path)

    store =
      step!(:graphlaw_wasi_store, wasm_path, fn ->
        Wasmex.Store.new_wasi(%Wasmex.Wasi.WasiOptions{})
      end)

    module =
      step!(:graphlaw_compile, wasm_path, fn ->
        Wasmex.Module.compile(store, wasm_bytes)
      end)

    instance =
      step!(:graphlaw_instantiate, wasm_path, fn ->
        Wasmex.Instance.new(store, module, %{})
      end)

    memory =
      step!(:graphlaw_memory, wasm_path, fn ->
        Wasmex.Instance.memory(store, instance)
      end)

    %{
      store: store,
      module: module,
      instance: instance,
      memory: memory,
      turtle: RDF.Turtle.write_string!(graph)
    }
  end

  @doc """
  Executes one SPARQL SELECT through the wasm module. Raises `RuntimeError`
  with the engine's real refusal message on any failure (missing artifact is a
  `prepare!/2` failure; this callback fails on query/data errors, null
  `gl_alloc` refusals, or an `{"ok": false}` graphlaw response).
  """
  @impl true
  @spec run(map(), String.t()) :: [map()]
  def run(
        %{store: store, instance: instance, memory: memory, turtle: turtle} = _context,
        query
      )
      when is_binary(query) do
    request =
      Jason.encode!(%{
        "op" => "sparql",
        "data" => %{"text" => turtle, "dialect" => "turtle"},
        "query" => query
      })

    response = gl_call(store, instance, memory, request)

    case Jason.decode(response) do
      {:ok, %{"ok" => true, "kind" => "solutions"} = body} ->
        normalize_rows(body["variables"], body["rows"])

      {:ok, %{"ok" => true, "kind" => kind}} ->
        raise RuntimeError,
          message:
            "graphlaw engine query failed: #{kind} results are not SELECT rows " <>
              "(only Solutions are supported, like the oxigraph engine)"

      {:ok, %{"ok" => true}} ->
        raise RuntimeError,
          message: "graphlaw engine query failed: response has no result kind"

      {:ok, %{"ok" => false, "error" => error}} ->
        raise RuntimeError, message: "graphlaw engine query failed: #{error["message"]}"

      {:error, reason} ->
        raise RuntimeError,
          message: "graphlaw engine query failed: response is not JSON: #{inspect(reason)}"
    end
  end

  def run(context, query) when is_binary(query) do
    raise ArgumentError,
      message:
        "graphlaw engine: run/2 requires the exact context map prepare!/2 returned " <>
          "(got: #{inspect(context)})"
  end

  # gl_alloc -> host write -> gl_call -> host read -> gl_free
  defp gl_call(store, instance, memory, request_json) do
    len = byte_size(request_json)

    ptr =
      case call_export(store, instance, "gl_alloc", [len]) do
        [ptr] when is_integer(ptr) and ptr > 0 ->
          ptr

        [ptr] ->
          raise RuntimeError,
            message:
              "graphlaw engine: gl_alloc(#{len}) returned #{ptr} (limit refusal); " <>
                "the request exceeds the module's MAX_REQUEST_BYTES/" <>
                "MAX_OUTSTANDING_ALLOC_BYTES"
      end

    Wasmex.Memory.write_binary(store, memory, ptr, request_json)

    packed =
      case call_export(store, instance, "gl_call", [ptr, len]) do
        [packed] when is_integer(packed) ->
          packed

        other ->
          raise RuntimeError,
            message: "graphlaw engine: bad gl_call result: #{inspect(other)}"
      end

    out_ptr = bsr(packed, 32)
    out_len = band(packed, 0xFFFFFFFF)

    # Memory.read_binary/write_binary return the binary/:ok directly and raise
    # on failure (no {:ok, _} tuple).
    response = Wasmex.Memory.read_binary(store, memory, out_ptr, out_len)

    call_export(store, instance, "gl_free", [out_ptr, out_len])

    response
  end

  defp call_export(store, instance, name, params) do
    # `from` must be a real `{pid, ref}` reply target (a raw `nil` makes the
    # NIF raise ArgumentError); the result arrives as an async `{ref, reply}`
    # message, exactly as the wasmex GenServer itself receives it.
    ref = make_ref()

    :ok = Wasmex.Instance.call_exported_function(store, instance, name, params, {self(), ref})

    receive do
      {^ref, {:ok, results}} when is_list(results) ->
        results

      {^ref, {:error, reason}} ->
        raise RuntimeError, message: "graphlaw engine: #{name} failed: #{reason}"
    after
      10_000 ->
        raise RuntimeError, message: "graphlaw engine: #{name} timed out after 10000ms"
    end
  end

  # Matches GgenIgniter.Query.Oxigraph's PLAIN normalization: plain unwrapped
  # string values (IRIs bare, literals as their lexical form, bnodes as label);
  # unbound variables are omitted from the row map.
  defp normalize_rows(variables, rows) do
    variables = variables || []

    Enum.map(rows, fn row ->
      variables
      |> Enum.zip(row || [])
      |> Enum.reduce(%{}, fn
        {_var, nil}, acc -> acc
        {var, term}, acc -> Map.put(acc, var, term_value(term))
      end)
    end)
  end

  defp term_value(%{"type" => "uri", "value" => v}), do: v
  defp term_value(%{"type" => "bnode", "value" => v}), do: v

  # Literal: lexical form only -- same disclosed scope limit as Oxigraph's
  # normalize_term (plain lexical string regardless of datatype/language tag).
  defp term_value(%{"type" => "literal", "value" => v}), do: v
  defp term_value(%{"type" => "triple", "value" => v}), do: v
  defp term_value(other), do: to_string(other)

  # Resolution: explicit Application env override, then the artifact shipped
  # inside this package, then the built-in dev checkout default.
  defp wasm_path do
    case Application.get_env(:ggen_igniter, :graphlaw_wasm_path) do
      nil ->
        packaged_path() || Path.expand(@default_wasm_path)

      path when is_binary(path) ->
        Path.expand(path)

      other ->
        raise RuntimeError,
          message:
            "ggen_igniter: invalid :graphlaw_wasm_path (must be a binary path or nil): " <>
              inspect(other)
    end
  end

  defp packaged_path do
    case :code.priv_dir(:ggen_igniter) do
      {:error, _} -> nil
      dir -> dir |> to_string() |> Path.join(@packaged_wasm_path) |> existing()
    end
  end

  defp existing(path), do: if(File.exists?(path), do: path, else: nil)

  # Typed boot refusal: the registry code lives in priv/schema/refusals.schema.json
  # (`GRAPHLAW_WASM_ARTIFACT_MISSING`); canonical text form `REFUSED:<CODE> <detail>`.
  @refusal_code "GRAPHLAW_WASM_ARTIFACT_MISSING"

  defp read_wasm!(path) do
    unless File.exists?(path) do
      raise RuntimeError,
        message:
          "REFUSED:#{@refusal_code} path=#{path} -- " <>
            "fix_hint: build via " <>
            "`cd ~/graphlaw && cargo build --target wasm32-wasip1 -p graphlaw-wasm --release`, " <>
            "or point Application env :ggen_igniter, :graphlaw_wasm_path at an existing " <>
            "artifact, or download the checksummed graphlaw.wasm (expected sha256 " <>
            "#{@wasm_sha256}) from a graphlaw GitHub release"
    end

    File.read!(path)
  end

  defp step!(step, wasm_path, fun) do
    case fun.() do
      {:ok, value} ->
        value

      {:error, reason} ->
        raise RuntimeError,
          message: "ggen_igniter: graphlaw engine #{step} failed for #{wasm_path}: #{reason}"
    end
  end
end
