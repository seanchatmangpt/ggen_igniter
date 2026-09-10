defmodule Mix.Tasks.GgenIgniter.Pack.Fetch do
  @moduledoc """
  CLI wiring for `GgenIgniter.Pack.fetch_pack!/2`: `mix ggen_igniter.pack.fetch <spec> [--cache-dir DIR] [--json]`.

  Before this task, `fetch_pack!/2` (`lib/ggen_igniter/pack.ex:190`) was real
  and tested but had zero CLI callers -- every existing `mix ggen_igniter.*`
  task only ever calls `Pack.resolve_dir!/1`, `Pack.discover_queries/1`, or
  `Pack.default_ontology/1` against an ALREADY-local pack directory (see
  `docs/status.md`'s row for "Marketplace pack fetch"). This task is the
  thin, additive wiring: parse a `spec`, call `fetch_pack!/2` with the same
  options it already accepts, print the resolved local path, and exit
  non-zero on failure. `fetch_pack!/2` itself is unchanged.

  `spec` accepts either real source `fetch_pack!/2` recognizes:

    * `"github:owner/repo[@ref]"` -- default ref `"main"`.
    * `"hex:name[@version]"` -- default: latest stable version via the Hex API.

  ## Flags

    * `--cache-dir DIR` -- override the cache root `fetch_pack!/2` extracts
      into (default: `~/.cache/ggen_igniter/packs`, via `Pack`'s own
      `default_cache_dir/0`).
    * `--json` -- emit a single JSON object (`{"path": ..., "spec": ...}` on
      success, `{"error": ...}` on failure) instead of a human line.

  ## Exit codes

    * `0` -- fetched (or already-cached and re-extracted) successfully; the
      resolved local path is printed.
    * `1` -- `fetch_pack!/2` raised (bad spec, HTTP failure, hex checksum
      mismatch) -- the real `Exception.message/1` is reported, never a
      fabricated reason.
    * `2` -- invalid invocation (no `spec` positional argument, or an
      unrecognized flag).

  ## Examples

      mix ggen_igniter.pack.fetch hex:ggen_igniter

      mix ggen_igniter.pack.fetch "github:seanchatmangpt/ggen@main" --cache-dir tmp/packs
  """
  use Mix.Task

  alias GgenIgniter.Pack

  @shortdoc "Fetches a marketplace pack (github:/hex:) via GgenIgniter.Pack.fetch_pack!/2"

  @impl Mix.Task
  def run(argv) do
    # `fetch_pack!/2` shells out over real HTTP via `Tesla.Adapter.Finch`,
    # which needs the `GgenIgniter.Finch` pool started by
    # `GgenIgniter.Application`'s supervision tree (see that module) --
    # unlike `mix test`/`mix run`, a bare `mix ggen_igniter.pack.fetch`
    # invocation does NOT start the current project's OTP application on its
    # own. Confirmed as a real, reachable defect (not hypothetical): running
    # this task as a real subprocess without this line raised `unknown
    # registry: GgenIgniter.Finch` on every real fetch. `Igniter.Mix.Task`'s
    # generated `run/1` (used by every other `ggen_igniter.*` task) already
    # does this implicitly; this task uses plain `Mix.Task` (per
    # `Mix.Tasks.GgenIgniter.Replay`'s precedent, since it needs no Igniter
    # project-mutation machinery), so it must start the app itself.
    Mix.Task.run("app.start")

    {opts, positional, invalid} =
      OptionParser.parse(argv,
        strict: [cache_dir: :string, json: :boolean, help: :boolean, version: :boolean],
        aliases: [h: :help, v: :version]
      )

    json? = Keyword.get(opts, :json, false)

    cond do
      opts[:help] ->
        print_help_and_halt()

      opts[:version] ->
        print_version_and_halt()

      invalid != [] ->
        invalid_invocation("unrecognized flag(s): #{inspect(invalid)}", json?)

      positional == [] ->
        invalid_invocation(
          "usage: mix ggen_igniter.pack.fetch <spec> [--cache-dir DIR] [--json]",
          json?
        )

      true ->
        [spec | _rest] = positional
        fetch_opts = if opts[:cache_dir], do: [cache_dir: opts[:cache_dir]], else: []
        do_fetch(spec, fetch_opts, json?)
    end
  end

  defp do_fetch(spec, fetch_opts, json?) do
    path = Pack.fetch_pack!(spec, fetch_opts)

    if json? do
      Mix.shell().info(Jason.encode!(%{"spec" => spec, "path" => path}, pretty: true))
    else
      Mix.shell().info("fetched #{spec} -> #{path}")
    end

    halt(0)
  rescue
    error ->
      message = Exception.message(error)
      Mix.shell().error("ggen_igniter.pack.fetch: #{message}")

      if json? do
        Mix.shell().info(Jason.encode!(%{"spec" => spec, "error" => message}, pretty: true))
      end

      halt(1)
  end

  defp invalid_invocation(message, json?) do
    Mix.shell().error("ggen_igniter.pack.fetch: #{message}")

    if json? do
      Mix.shell().info(Jason.encode!(%{"error" => message}, pretty: true))
    end

    halt(2)
  end

  defp print_help_and_halt do
    IO.puts("""
    mix ggen_igniter.pack.fetch -- fetches a marketplace pack via GgenIgniter.Pack.fetch_pack!/2

    USAGE
        mix ggen_igniter.pack.fetch <spec> [--cache-dir DIR] [--json] [--help] [--version]

    ARGUMENTS
        <spec>              "github:owner/repo[@ref]" or "hex:name[@version]". Required.

    FLAGS
        --cache-dir DIR     Cache root to extract into (default: ~/.cache/ggen_igniter/packs).
        --json              Emit a machine-readable JSON object instead of a human line.
        --help, -h          Print this help and exit 0.
        --version, -v       Print ggen_igniter's version and exit 0.

    EXAMPLES
        mix ggen_igniter.pack.fetch hex:ggen_igniter
        mix ggen_igniter.pack.fetch github:seanchatmangpt/ggen@main --cache-dir tmp/packs

    EXIT CODES
        0  fetched successfully; resolved local path printed
        1  fetch_pack!/2 raised (bad spec, HTTP failure, hex checksum mismatch)
        2  invalid invocation (missing <spec>, or an unrecognized flag)
    """)

    halt(0)
  end

  defp print_version_and_halt do
    version = Application.spec(:ggen_igniter, :vsn) |> to_string()
    IO.puts("ggen_igniter #{version}")
    halt(0)
  rescue
    _ ->
      IO.puts("ggen_igniter unknown")
      halt(0)
  end

  defp halt(code), do: System.halt(code)
end
