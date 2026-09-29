defmodule Mix.Tasks.GgenIgniter.Pack.Fetch do
  # `halt/1` wraps `System.halt/1`, which never returns to the caller by
  # design (a real process exit code). Every function below propagates that
  # non-return through its own real exit path (`run/1`'s `cond` branches,
  # `do_fetch/3`'s success/rescue, `invalid_invocation/2`, and the
  # help/version printers) -- Dialyzer correctly observes each has no local
  # return and flags it `:no_return`; that is the intended CLI-exit
  # contract here, not a bug.
  @dialyzer {:no_return, halt: 1}
  @dialyzer {:no_return, print_version_and_halt: 0}
  @dialyzer {:no_return, print_help_and_halt: 0}
  @dialyzer {:no_return, invalid_invocation: 2}
  @dialyzer {:no_return, do_fetch: 3}
  @dialyzer {:no_return, do_fetch_locked: 4}
  @dialyzer {:no_return, refuse: 3}
  @dialyzer {:no_return, run: 1}

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

    * `"github:owner/repo[@ref][#subpath]"` -- default ref `"main"`. A
      `#subpath` (or `//subpath`) fetches a monorepo directory as the pack
      root, e.g. `github:seanchatmangpt/ggen-marketplace#packs/ash-extension-pack`
      (paths escaping the archive via `..`/absolute/symlink are refused).
    * `"hex:name[@version]"` -- default: latest stable version via the Hex API.

  ## Consumer requirement

  The HTTP layer is `Tesla`, an `optional: true` dependency of `ggen_igniter`:
  a consuming app must add `{:tesla, "~> 1.8"}` to its own `mix.exs` deps to
  use this task (without it `fetch_pack!/2` raises a `RuntimeError` that says
  so).

  ## Flags

    * `--cache-dir DIR` -- override the cache root `fetch_pack!/2` extracts
      into (default: `~/.cache/ggen_igniter/packs`, via `Pack`'s own
      `default_cache_dir/0`).
    * `--lock PATH` -- record the fetched pack's content sha256 in the lockfile
      (`GgenIgniter.PackLock`); an existing entry with a different digest is
      refused (`REFUSED:PACK_DIGEST_MISMATCH`, exit 1) and the real cache is
      not overwritten. See `docs/reference/cli/pack-lock.md`.
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
        strict: [
          cache_dir: :string,
          lock: :string,
          json: :boolean,
          help: :boolean,
          version: :boolean
        ],
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

        if opts[:lock],
          do: do_fetch_locked(spec, fetch_opts, opts[:lock], json?),
          else: do_fetch(spec, fetch_opts, json?)
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

  # `--lock PATH`: fetch into a staging cache first (fetch_pack!/2 replaces its
  # destination in place), compare the content digest with any existing lock
  # entry, and only on match/new copy into the real cache and record the entry.
  # A mismatch leaves the real cache untouched (REFUSED:PACK_DIGEST_MISMATCH).
  defp do_fetch_locked(spec, fetch_opts, lock_path, json?) do
    alias GgenIgniter.PackLock

    staging =
      Path.join(
        System.tmp_dir!(),
        "ggen_igniter_pack_fetch_#{System.unique_integer([:positive])}"
      )

    File.mkdir_p!(staging)

    try do
      staged = Pack.fetch_pack!(spec, cache_dir: staging)
      name = Path.basename(staged)
      entry = PackLock.entry(staged, spec, lock_version(spec))

      lock =
        case PackLock.read(lock_path) do
          {:ok, l} -> l
          _ -> PackLock.empty()
        end

      actual_sha = entry["sha256"]

      case get_in(lock, ["packs", name, "sha256"]) do
        existing when is_binary(existing) and existing != actual_sha ->
          reason =
            {:pack_digest_mismatch, %{pack: name, expected: existing, actual: entry["sha256"]}}

          refuse(PackLock.refusal_text(reason), spec, json?)

        _ ->
          cache_root =
            Keyword.get_lazy(fetch_opts, :cache_dir, fn ->
              Path.join([System.user_home!(), ".cache", "ggen_igniter", "packs"])
            end)

          dest = Path.join(cache_root, name)
          File.mkdir_p!(cache_root)
          File.rm_rf!(dest)
          File.cp_r!(staged, dest)
          PackLock.write(lock_path, PackLock.put(lock, name, entry))

          if json? do
            Mix.shell().info(
              Jason.encode!(
                %{
                  "spec" => spec,
                  "path" => dest,
                  "sha256" => entry["sha256"],
                  "lock" => lock_path
                },
                pretty: true
              )
            )
          else
            Mix.shell().info(
              "fetched #{spec} -> #{dest} (sha256=#{entry["sha256"]}, locked in #{lock_path})"
            )
          end

          File.rm_rf!(staging)
          halt(0)
      end
    rescue
      error ->
        File.rm_rf(staging)
        refuse(Exception.message(error), spec, json?)
    end
  end

  defp lock_version(spec) do
    case Pack.parse_spec(spec) do
      {:github, _, _, ref, _} -> ref
      {:hex, _, version} -> version
      _ -> nil
    end
  end

  defp refuse(message, spec, json?) do
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
        --lock PATH         Record the fetched pack's sha256 in PATH (ggen_igniter.pack.lock);
                            an existing entry with a different digest is refused (exit 1) and
                            the cache is left untouched.
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
