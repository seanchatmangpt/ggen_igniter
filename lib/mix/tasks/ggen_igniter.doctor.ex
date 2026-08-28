defmodule Mix.Tasks.GgenIgniter.Doctor do
  @moduledoc """
  Diagnostic task: `mix ggen_igniter.doctor [--pack NAME | --pack-dir DIR] [--engine sparql|qlever] [--store-id ID] [--fix] [--strict]`.

  Runs a fixed checklist of real checks (no fabricated pass output):

  1. Elixir/OTP version satisfies this project's `mix.exs` requirement (`~> 1.17`, OTP >= 25).
  2. Required deps (`rdf`, `sparql`, `igniter`, and `gno` when `--engine qlever`) are loaded
     with resolvable `:vsn`.
  3. Advisory for the known `sparql` 0.3.12 `FILTER NOT EXISTS` + `BIND` inside `UNION` bug.
  4. The CURRENT project's own `mix.exs` doesn't restrict its direct `igniter` dependency
     with `:only` (real conflict: `ggen_igniter` needs `igniter` unconditionally, so a
     consumer's own `only: [:dev, :test]`-restricted declaration makes Mix's resolver
     refuse). `--fix` relaxes it for real; without `--fix` this is diagnostic only.
  5. Same as 4, for `sourceror` (only applicable if the current project declares it
     directly at all).
  6. `config :dcatr, env: ...` is present in the current project's `config/config.exs`
     whenever `:gno`/`:dcatr` are in its dependency tree (`:gno`'s `Fuseki` adapter raises
     at compile time without it). `--fix` adds the missing entry for real.
  7. Every Ash domain module (`use Ash.Domain`) found under the current project's `lib/`
     is registered in `config :OTP_APP, ash_domains: [...]` (an unregistered domain is a
     hard compile error under `mix compile --warnings-as-errors`). `--fix` registers any
     missing one(s) for real.
  8. (only with `--engine qlever` or a pack ontology naming a `gnoa:Qlever` store via
     `--store-id`) the QLever endpoint is really reachable via a real `ASK` query.
  9. Pack `ontology.ttl` exists and parses as valid Turtle.
  10. At least one gate query (`gates/*.rq`) is present.
  11. At least one template (`templates/*.{eex,tmpl}`) is present.
  12. Every gate query is syntactically valid SPARQL (parse-only, no execution).
  13. Target (cwd) git status -- clean vs dirty is reported, never fails the run by itself.
  14. `native/ggen_graph_nif` is compiled and up to date: the built `priv/native/ggen_graph_nif.so`
      exists and is newer than every `.rs` source file under the crate (a fast mtime proxy); if
      the `.so` is missing or stale, falls back to a real `cargo build --quiet` and reports real
      stderr on failure.
  15. `GgenIgniter.Query.Oxigraph` actually works: runs a real `SELECT * WHERE { ?s ?p ?o }`
      SPARQL query against a tiny real in-memory `%RDF.Graph{}` through the native oxigraph
      engine and confirms it returns without raising -- a functional smoke test, not just
      "does the NIF load".
  16. (only with `--hex-check`, off by default) hex-publish readiness: shells out to a real
      `mix hex.build` and reports its real output, plus checks `mix.exs`'s `package[:description]`
      and `package[:licenses]` are both present and non-empty.
  17. `check_version_policy`: `mix.exs`'s `version:` literal is a *projection* of this
      project's real, observed versioning convention rather than an independently
      maintained field. This repo has no `git tag`s at all (confirmed via
      `git tag --list` returning empty), so `CHANGELOG.md`'s topmost `## vX` entry
      heading is the only real, standing record of "what the current version is" -- a
      calendar-ish `YY.M.D` string (e.g. `26.8.27` for 2026-08-27), matched verbatim
      against `mix.exs`'s `version:`. Reports `MATCH` or a clearly-named `MISMATCH`;
      never silently rewrites `mix.exs`. `--fix` corrects it for real only when the
      derivation is unambiguous (a single topmost `## vX` heading found and `mix.exs`'s
      `version:` is a simple string literal); an ambiguous shape (no CHANGELOG.md, no
      `## v` heading, or a non-literal `version:`) is reported `✘` as informational-only,
      never guessed at.
  18. `GgenIgniter.Lock`'s real cross-process `.ggen_igniter/.sync.lock` file (see
      `GgenIgniter.Lock`'s moduledoc) is checked against the CURRENT project
      (`File.cwd!()`): absent is `✔` (no lock held); present and younger than
      `GgenIgniter.Lock`'s own 5-minute stale threshold is `✔` info naming the real
      holder marker (`pid=... node=... at=...`) written by `GgenIgniter.Lock.acquire/2`
      -- a live/recent lock held by a real, still-running `mix ggen_igniter.sync`/
      `.replay` invocation is not a problem; present and older than 5 minutes is a real
      `⚠` warning naming the exact real remedy (the next `acquire/2` call anywhere
      against this project automatically deletes it -- `GgenIgniter.Lock` has no
      `--force-unlock` flag, so this never invents one). Never `:error`: a held lock,
      stale or not, is advisory information about another invocation, not a defect in
      the current project.

  Checks 9-12 only run when `--pack`/`--pack-dir` is given; without it, only checks 1-3
  and 4-7 (and 8, if `--engine qlever` was explicitly passed with a graph-free reachability
  check is not possible, so 8 is skipped) run. Checks 4-7, 13-15, 17, and 18 always run.
  Check 16 only runs with `--hex-check` (it shells out to `mix hex.build`, which is slow,
  so it stays off by default to keep `mix ggen_igniter.doctor` fast).

  ## `--fix`

  Checks 4-7 and 17 are real fixes (`GgenIgniter.DoctorFixes`), not just diagnostics:
  passing `--fix` applies each detected, safely-recognized fix directly to the CURRENT
  project (`File.cwd!()`) -- the real consumer app `doctor` is running inside, never a
  test-harness scaffold -- and the check line reports exactly what changed (prefixed
  `FIXED:`), or that there was nothing to fix. Without `--fix`, these checks are
  read-only: a real, fixable problem is reported as a `⚠` warning naming the exact fix to
  run; a real problem whose exact shape isn't safely automatable is reported as a `✘`
  error rather than silently skipped or guessed at.

  ## `--strict`

  Without `--strict`, only `:error`-level checks fail the run (exit 1); `:warn`-level
  checks (e.g. "git dirty", "not a git repo", a `--fix`-able hygiene gap reported
  without `--fix`) are advisory only and never affect the exit code. With `--strict`,
  any check currently reporting `:warn` also fails the run (exit 1) -- each such line
  is suffixed `[STRICT]` in human output (and carries `"strict_failure": true` in
  `--json` output) so it's clear which failures are strict-mode-only and would pass
  under the default mode.

  ## Examples

      mix ggen_igniter.doctor

      mix ggen_igniter.doctor --pack audit-trail-pack --json

  ## Exit codes

  - `0` -- all checks passed (under `--strict`, this also means no `:warn` findings).
  - `1` -- ran the full checklist and at least one check came back `:error` (or, under
    `--strict`, at least one came back `:warn`).
  - `2` -- invalid invocation/configuration: an unrecognized flag, `--engine` not one
    of `oxigraph`/`sparql`/`qlever`, or both `--pack` and `--pack-dir` given at once.
    The checklist never runs.
  - `3` -- an explicitly requested capability isn't available on this toolchain (today:
    `--hex-check` without the `hex` Mix archive installed). The checklist never runs.
  - `4` -- blocked by authority/lock/environment (today: `--fix` unable to get
    exclusive access to the current project directory). The checklist never runs.

  ## DX flags

  `--help`/`-h` and `--version`/`-v` print and exit `0` immediately, before any checks
  run. `--json` emits a single JSON object (`checks`, `ok`, `exit_code`) instead of the
  human checklist -- exit code semantics above are unchanged either way. `--quiet`/`-q`
  suppresses passing (`✔`) lines; warnings/errors and the summary line still print.
  `--verbose` and `--no-color` are accepted for consistency with other `mix
  ggen_igniter.*` tasks; this task's output is always plain `✔`/`⚠`/`✘` glyphs with no
  ANSI color and no currently-defined extra verbose detail, so both are no-ops today.
  """
  use Igniter.Mix.Task

  alias GgenIgniter.{DoctorFixes, Ontology, Pack}

  @impl Igniter.Mix.Task
  def info(_argv, _composing_task) do
    %Igniter.Mix.Task.Info{
      group: :ggen_igniter,
      example: "mix ggen_igniter.doctor --pack audit-trail-pack",
      positional: [],
      schema: [
        pack: :string,
        pack_dir: :string,
        engine: :string,
        store_id: :string,
        hex_check: :boolean,
        fix: :boolean,
        strict: :boolean,
        json: :boolean,
        help: :boolean,
        version: :boolean,
        quiet: :boolean,
        verbose: :boolean,
        no_color: :boolean
      ],
      aliases: [h: :help, v: :version, q: :quiet],
      required: []
    }
  end

  # Exit-code contract (PRD):
  #   0 - all checks pass
  #   1 - diagnostic failures found (at least one check returned :error)
  #   2 - invalid invocation/configuration (unknown flag, --engine not in the
  #       real engine registry, --pack and --pack-dir both given, etc.) --
  #       these never even attempt to run the checklist.
  #   3 - unsupported capability requested (a capability that cannot be
  #       provided on this platform/toolchain, distinct from a plain
  #       configuration mistake -- see `unsupported_capability_error/2`).
  #   4 - blocked by authority/lock/environment (`--fix` needs exclusive
  #       write access to CURRENT project state and cannot get it).
  @known_flags ~w(--pack --pack-dir --engine --store-id --hex-check --no-hex-check
                  --fix --no-fix --strict --no-strict --json --no-json --help --version --quiet
                  --no-quiet --verbose --no-verbose --no-color -h -v -q
                  --dry-run --no-dry-run --yes --no-yes --yes-to-deps --no-yes-to-deps
                  --only --check --no-check --scribe --from-igniter-new
                  --no-from-igniter-new --igniter-repeat --no-igniter-repeat
                  --no-no-color)
  @known_engines ["oxigraph", "sparql", "qlever"]

  # `use Igniter.Mix.Task`'s generated `run/1` (see `deps/igniter/lib/mix/
  # task.ex`) validates argv against `info/2`'s schema via
  # `Igniter.Util.Info.validate!/3`, which raises a `Mix.Error` on an
  # unrecognized flag -- Mix's own top-level error handler then reports
  # "Could not invoke task" and exits with **1**, indistinguishable from a
  # real diagnostic failure (per the moduledoc's exit-code contract, an
  # unrecognized flag must be **2**: invalid invocation, distinct from 1:
  # ran the checklist and something failed). Pre-validating here, before
  # calling through to the generated `run/1` via `super/1`, catches the bad
  # flag before Igniter's own validation ever runs and reports it with the
  # correct exit code -- every other flag is untouched and still flows
  # through Igniter's normal `run/1` -> `igniter/1` pipeline.
  # AR-11 (2026-08-28, mirrors the same fix in `Mix.Tasks.GgenIgniter.Sync`/
  # `.Plan`): `Igniter.Mix.Task`'s generated `run/1` intercepts literal
  # `"--help"` in `argv` before `igniter/1` ever runs
  # (`Igniter.Mix.Task.help_requested?/1` never matches `-h`), dispatching to
  # `Mix.Task.run("help", [...])` instead of this task's own concise
  # `print_help_and_halt/0`. Checked here, BEFORE the pre-existing
  # unknown-flag validation below (a bad flag alongside `--help` should still
  # print help and exit 0, matching how `-h` already behaves regardless of
  # other flags via `igniter/1`'s own `cond`), and before falling through to
  # `super/1`.
  @impl Mix.Task
  def run(argv) do
    cond do
      "--help" in argv ->
        print_help_and_halt()

      first_unknown_flag(argv) ->
        invalid_invocation_and_halt(first_unknown_flag(argv), [])

      true ->
        super(argv)
    end
  end

  @impl Igniter.Mix.Task
  def igniter(igniter) do
    argv = igniter.args.argv
    opts = igniter.args.options

    cond do
      opts[:help] ->
        print_help_and_halt()

      opts[:version] ->
        print_version_and_halt()

      (bad = first_unknown_flag(argv)) != nil ->
        invalid_invocation_and_halt(bad, opts)

      opts[:pack] not in [nil, ""] and opts[:pack_dir] not in [nil, ""] ->
        invalid_invocation_and_halt(
          "--pack and --pack-dir are mutually exclusive",
          opts
        )

      opts[:engine] not in [nil | @known_engines] ->
        invalid_invocation_and_halt(
          "--engine #{inspect(opts[:engine])} is not a known engine (must be one of #{Enum.join(@known_engines, ", ")})",
          opts
        )

      opts[:hex_check] == true and not hex_build_available?() ->
        unsupported_capability_and_halt(
          "--hex-check requires the `hex` Mix archive (mix hex.build) but it is not " <>
            "installed on this toolchain -- run `mix local.hex` or drop --hex-check",
          opts
        )

      opts[:fix] == true and not fix_lock_available?() ->
        blocked_and_halt(
          "--fix could not acquire exclusive access to the current project directory " <>
            "(#{File.cwd!()}) -- another --fix run appears to be in progress",
          opts
        )

      true ->
        run_checks(igniter, opts)
    end
  end

  defp run_checks(igniter, opts) do
    pack_dir =
      if opts[:pack] not in [nil, ""] or opts[:pack_dir] not in [nil, ""] do
        Pack.resolve_dir!(opts)
      end

    checks =
      [
        tag("elixir_otp_version", check_elixir_otp_version()),
        tag("deps", check_deps(opts)),
        tag("sparql_advisory", check_sparql_advisory())
      ] ++
        doctor_fix_rule_checks(opts) ++
        [
          tag("version_policy", check_version_policy(opts))
        ] ++
        maybe_check_qlever(opts, pack_dir) ++
        if(pack_dir, do: pack_checks(pack_dir), else: []) ++
        [
          tag("git_status", check_git_status()),
          tag("nif_compiles", check_nif_compiles()),
          tag("oxigraph_smoke_test", check_oxigraph_smoke_test())
        ] ++
        maybe_check_hex_publish(opts)

    strict? = opts[:strict] == true
    has_error? = Enum.any?(checks, fn {status, _id, _msg} -> status == :error end)
    has_warn? = Enum.any?(checks, fn {status, _id, _msg} -> status == :warn end)
    failed? = has_error? or (strict? and has_warn?)

    if opts[:json] do
      print_json(checks, failed?, strict?)
    else
      Enum.each(checks, &print_check(&1, opts, strict?))

      cond do
        failed? and strict? and not has_error? ->
          IO.puts(
            "✘ ggen_igniter.doctor: one or more checks failed under --strict " <>
              "(warnings are treated as failures in --strict mode; see ⚠ [STRICT] lines above)"
          )

        failed? ->
          IO.puts("✘ ggen_igniter.doctor: one or more checks failed (see ✘ lines above)")

        true ->
          IO.puts("✔ ggen_igniter.doctor: all checks passed (see output above)")
      end
    end

    cond do
      failed? ->
        # `Igniter.add_issue/2` only halts the real OS process under `--check`
        # (see `Igniter.halt_if_fails_check!/2`); a doctor task needs a real
        # non-zero exit code unconditionally, so halt directly here. Exit 1 =
        # diagnostic failures found (per the PRD exit-code contract above).
        System.halt(1)

      opts[:json] ->
        # Same rationale as `ggen_igniter.plan`'s identical `System.halt(0)`
        # on its success path: returning `igniter` here to `Igniter.Mix.
        # Task`'s generated runner lets Igniter print its own "No proposed
        # content changes!" footer to stdout AFTER `print_json/3` already
        # wrote a validly-closed JSON document above, corrupting `--json`
        # output with trailing non-JSON bytes a strict single-document JSON
        # parser rejects. This task never mutates the target project, so
        # `igniter` always carries zero proposed changes -- halt directly
        # with the same real exit code (0) the non-JSON branch below would
        # have produced via `Igniter.add_notice/2`, instead of returning to
        # the Igniter runner.
        System.halt(0)

      true ->
        Igniter.add_notice(igniter, "ggen_igniter.doctor: all checks passed (see output above)")
    end
  end

  # Stable, machine-addressable identity for a check result, independent of
  # its human-readable message (AR-10: "Doctor should become scriptable" --
  # a CI script keys off `check_id`, never parses `message` prose). Applied
  # at every call site in `run_checks/2` so every one of the (today) 17
  # checks carries a real snake_case `check_id` into both the human and
  # `--json` output paths.
  defp tag(id, {status, message}), do: {status, id, message}

  defp print_check({status, _id, message}, opts, strict?) do
    # --quiet: only ✘ (and, under --strict, ⚠) lines and the final summary
    # line are shown; the summary line itself is always printed regardless
    # of --quiet.
    if status != :ok or opts[:quiet] != true do
      IO.puts(check_line(status, message, strict?))
    end
  end

  defp check_line(status, message, strict?) do
    prefix = %{ok: "✔", warn: "⚠", error: "✘"}[status]
    # Under --strict, a :warn check also fails the run -- label it so the
    # human/JSON reader can tell "this warning is why exit code is 1" apart
    # from an ordinary advisory warning that never fails anything.
    suffix = if strict? and status == :warn, do: " [STRICT]", else: ""
    "#{prefix} #{message}#{suffix}"
  end

  defp print_json(checks, failed?, strict?) do
    payload = %{
      "checks" =>
        Enum.map(checks, fn {status, id, message} ->
          %{
            "check_id" => id,
            "status" => Atom.to_string(status),
            "message" => message,
            "strict_failure" => strict? and status == :warn
          }
        end),
      "ok" => not failed?,
      "strict" => strict?,
      "exit_code" => if(failed?, do: 1, else: 0)
    }

    IO.puts(Jason.encode!(payload))
  end

  defp print_help_and_halt do
    IO.puts("""
    mix ggen_igniter.doctor -- diagnostic checklist for ggen_igniter

    USAGE
        mix ggen_igniter.doctor [--pack NAME | --pack-dir DIR] [--engine oxigraph|sparql|qlever]
                                 [--store-id ID] [--fix] [--strict] [--hex-check] [--json]
                                 [--quiet] [--verbose] [--no-color] [--help] [--version]

    FLAGS
        --pack NAME       Resolve a marketplace-convention pack by name (priv/ggen/NAME).
        --pack-dir DIR    Use an explicit pack directory (bypasses the --pack convention).
        --engine ENGINE   One of: #{Enum.join(@known_engines, ", ")}. Default: oxigraph.
        --store-id ID     Named store to resolve for --engine qlever reachability checks.
        --fix             Apply real, safely-recognized fixes to the CURRENT project.
        --strict          Treat WARN-level findings as failures too (exit 1), not just ERROR.
                           Strict-mode-only failures are labeled "[STRICT]" in the output.
        --hex-check       Also run the (slow) hex-publish readiness check (mix hex.build).
        --json            Emit machine-readable JSON instead of the human checklist output.
        --quiet, -q       Suppress ✔ (passing) lines; ⚠/✘ lines and the summary still print.
        --verbose         Reserved for future additional diagnostic detail; accepted, no-op today.
        --no-color        Reserved: this task's output uses plain ✔/⚠/✘ glyphs, never ANSI color.
        --help, -h        Print this help and exit 0.
        --version, -v     Print ggen_igniter's version and exit 0.

    EXIT CODES
        0  all checks passed (under --strict, also means no WARN findings)
        1  one or more checks failed (under --strict, WARN also counts)
        2  invalid invocation or configuration (unknown flag, bad --engine, etc.)
        3  unsupported capability requested on this platform/toolchain
        4  blocked by authority/lock/environment (e.g. a concurrent --fix)
    """)

    System.halt(0)
  end

  defp print_version_and_halt do
    version = Mix.Project.config()[:version] || "unknown"
    IO.puts("ggen_igniter #{version}")
    System.halt(0)
  end

  defp first_unknown_flag(argv) do
    Enum.find(argv, fn
      "--" <> _ = flag ->
        # strip a trailing `=value` (e.g. `--engine=qlever`) before matching
        flag |> String.split("=", parts: 2) |> hd() |> then(&(&1 not in @known_flags))

      "-" <> _ = flag when byte_size(flag) == 2 ->
        flag not in @known_flags

      _ ->
        false
    end)
  end

  defp invalid_invocation_and_halt(reason, opts) do
    if opts[:json] do
      IO.puts(Jason.encode!(%{"ok" => false, "exit_code" => 2, "error" => reason}))
    else
      IO.puts("✘ ggen_igniter.doctor: invalid invocation -- #{reason}")
    end

    System.halt(2)
  end

  defp blocked_and_halt(reason, opts) do
    if opts[:json] do
      IO.puts(Jason.encode!(%{"ok" => false, "exit_code" => 4, "error" => reason}))
    else
      IO.puts("✘ ggen_igniter.doctor: blocked -- #{reason}")
    end

    System.halt(4)
  end

  defp unsupported_capability_and_halt(reason, opts) do
    if opts[:json] do
      IO.puts(Jason.encode!(%{"ok" => false, "exit_code" => 3, "error" => reason}))
    else
      IO.puts("✘ ggen_igniter.doctor: unsupported -- #{reason}")
    end

    System.halt(3)
  end

  # `mix hex.build` (check 16, --hex-check) is provided by the `:hex`
  # archive, which is installed separately from the language/OTP toolchain
  # (`mix local.hex`) and is genuinely absent on some real CI/container
  # images. Requesting `--hex-check` where it's absent is not a
  # configuration mistake (the flag itself is valid) -- it's a capability
  # this environment cannot provide, which is exit code 3 per the PRD, not
  # exit code 1 (that's reserved for a real diagnostic failure once the
  # checklist actually ran).
  defp hex_build_available? do
    Code.ensure_loaded?(Hex)
  rescue
    _ -> false
  end

  # `--fix` writes directly to the CURRENT project's real files
  # (`GgenIgniter.DoctorFixes.run_rule/3` and `fix_version_policy!/1`, called
  # from `fix_or_check/3` below). There is no long-lived lock/daemon today,
  # but a concurrent `--fix` run (this same task, invoked twice against the
  # same project) is a real, reachable race, so a real (currently-absent-by-
  # default) marker file is the exclusivity signal: if a previous `--fix`
  # run left `.ggen_igniter/.fix.lock` behind (e.g. it was killed mid-write
  # and never reached its cleanup), a second `--fix` refuses to start rather
  # than racing it -- exit code 4 (blocked by authority/lock/environment)
  # per the PRD, checked BEFORE the checklist runs.
  @fix_lock_path ".ggen_igniter/.fix.lock"
  defp fix_lock_available?, do: not File.exists?(Path.join(File.cwd!(), @fix_lock_path))

  # 1. Elixir/OTP version
  defp check_elixir_otp_version do
    elixir_version = System.version()
    otp_release = :erlang.system_info(:otp_release) |> List.to_string()
    otp_major = otp_release |> String.to_integer()

    elixir_ok? = Version.match?(elixir_version, "~> 1.17")
    otp_ok? = otp_major >= 25

    cond do
      elixir_ok? and otp_ok? ->
        {:ok, "Elixir #{elixir_version} / OTP #{otp_release}"}

      not elixir_ok? ->
        {:error, "Elixir #{elixir_version} does not satisfy ~> 1.17 (mix.exs requirement)"}

      true ->
        {:error, "OTP #{otp_release} is below the required >= 25"}
    end
  end

  # 2. Required deps present + resolvable versions
  defp check_deps(opts) do
    needs_gno? = opts[:engine] == "qlever"

    required = [:rdf, :sparql, :igniter] ++ if needs_gno?, do: [:gno], else: []

    results =
      Enum.map(required, fn app ->
        Application.ensure_loaded(app)

        case Application.spec(app, :vsn) do
          nil -> {:error, app, nil}
          vsn -> {:ok, app, List.to_string(vsn)}
        end
      end)

    case Enum.filter(results, fn {status, _, _} -> status == :error end) do
      [] ->
        summary = Enum.map_join(results, ", ", fn {:ok, app, vsn} -> "#{app} #{vsn}" end)
        {:ok, summary}

      errors ->
        missing = Enum.map_join(errors, ", ", fn {:error, app, _} -> to_string(app) end)
        {:error, ":#{missing} not loaded -- add the missing dep(s) or drop --engine qlever"}
    end
  end

  # 3. Known sparql engine bug advisory
  defp check_sparql_advisory do
    Application.ensure_loaded(:sparql)

    case Application.spec(:sparql, :vsn) do
      nil ->
        {:warn,
         "sparql not loaded -- cannot check for the known 0.3.12 UNION/FILTER NOT EXISTS bug"}

      vsn ->
        version = List.to_string(vsn)

        if Version.match?(version, "<= 0.3.12") do
          {:warn,
           "sparql #{version}: FILTER NOT EXISTS + BIND inside UNION raises Protocol.UndefinedError " <>
             "(see query/qlever.ex moduledoc) -- use --engine qlever for gate queries with this shape"}
        else
          {:ok,
           "sparql #{version} (newer than the known-bad 0.3.12 UNION/FILTER NOT EXISTS advisory)"}
        end
    end
  end

  # 4-7. Real project-hygiene fixes (GgenIgniter.DoctorFixes) -- diagnostic-only
  # without --fix, applied for real to the CURRENT project (File.cwd!()) with
  # it. These four checks are now DATA (`DoctorFixes.default_rules/0`), run
  # through the one generic `DoctorFixes.run_rule/3` engine -- adding a fifth
  # Igniter/Ash wiring-gap class means appending a `%DoctorFixes.Rule{}` to
  # `default_rules/0`, never adding another hand-written `check_*` function
  # here.
  defp doctor_fix_rule_checks(opts) do
    Enum.map(DoctorFixes.default_rules(), &run_rule_check(opts, &1))
  end

  defp run_rule_check(opts, %DoctorFixes.Rule{name: name} = rule) do
    tag(
      name,
      fix_or_check(
        opts,
        fn project_dir -> DoctorFixes.run_rule(rule, project_dir, false) end,
        fn project_dir -> DoctorFixes.run_rule(rule, project_dir, true) end
      )
    )
  end

  # 17. mix.exs version: literal is a projection of the real, observed
  # versioning convention (CHANGELOG.md's topmost `## vX` entry heading --
  # see the moduledoc for why that's the real source of truth, not a guess).
  defp check_version_policy(opts) do
    fix_or_check(
      opts,
      &DoctorFixes.check_version_policy/1,
      &DoctorFixes.fix_version_policy!/1
    )
  end

  # Shared glue between a real `DoctorFixes` check/fix pair and doctor's
  # `{:ok | :warn | :error, message}` check-result vocabulary. Without
  # `--fix`, only inspects (never writes); with `--fix`, applies the real
  # fix and reports what changed -- catching (never letting propagate) the
  # `RuntimeError` a fix raises when it hits a shape it refuses to guess at,
  # turning that into a real `:error` check result instead of crashing the
  # whole doctor run.
  defp fix_or_check(opts, check_fn, fix_fn) do
    project_dir = File.cwd!()

    if opts[:fix] do
      try do
        case fix_fn.(project_dir) do
          {:fixed, msg} -> {:ok, "FIXED: #{msg}"}
          {:ok, msg} -> {:ok, msg}
        end
      rescue
        error -> {:error, Exception.message(error)}
      end
    else
      case check_fn.(project_dir) do
        {:ok, msg} -> {:ok, msg}
        {:fixable, msg} -> {:warn, "#{msg} -- run `mix ggen_igniter.doctor --fix` to fix"}
        {:unrecognized, msg} -> {:error, msg}
      end
    end
  end

  # 8. Qlever endpoint reachable (only if --engine qlever and a store can be resolved)
  defp maybe_check_qlever(opts, pack_dir) do
    if opts[:engine] == "qlever" do
      [tag("qlever_reachable", check_qlever_reachable(opts, pack_dir))]
    else
      []
    end
  end

  defp check_qlever_reachable(opts, pack_dir) do
    store_id = opts[:store_id]
    ontology_path = pack_dir && Pack.default_ontology(pack_dir)

    cond do
      is_nil(store_id) ->
        {:error,
         "--engine qlever given but --store-id is missing -- cannot resolve a QLever store to check"}

      is_nil(ontology_path) or not File.exists?(ontology_path) ->
        {:error,
         "--engine qlever given but no pack ontology found to resolve --store-id #{store_id} against " <>
           "(pass --pack/--pack-dir)"}

      true ->
        try do
          graph = Ontology.load!(ontology_path)
          store = GgenIgniter.Query.Qlever.load_store!(graph, store_id)

          case GgenIgniter.Query.Qlever.run(store, "ASK { ?s ?p ?o }") do
            rows when is_list(rows) ->
              {:ok, "QLever endpoint for #{store_id} reachable"}
          end
        rescue
          error ->
            {:error, "QLever endpoint for #{store_id} unreachable: #{Exception.message(error)}"}
        end
    end
  end

  # 9-12: pack-scoped checks
  defp pack_checks(pack_dir) do
    [
      tag("ontology_valid", check_ontology(pack_dir)),
      tag("gate_queries_present", check_gate_queries_present(pack_dir)),
      tag("template_present", check_template_present(pack_dir)),
      tag("gate_queries_parse", check_gate_queries_parse(pack_dir))
    ]
  end

  # 9. Pack ontology present + valid Turtle
  defp check_ontology(pack_dir) do
    path = Pack.default_ontology(pack_dir)

    if File.exists?(path) do
      case RDF.Turtle.read_file(path) do
        {:ok, %RDF.Graph{} = graph} ->
          {:ok, "ontology.ttl parses (#{RDF.Graph.statement_count(graph)} triples)"}

        {:error, reason} ->
          {:error, "ontology.ttl failed to parse: #{inspect(reason)}"}
      end
    else
      {:error, "ontology.ttl missing at #{path}"}
    end
  end

  # 10. At least one gate query present
  defp check_gate_queries_present(pack_dir) do
    queries = Pack.discover_queries(pack_dir)

    if queries == [] do
      {:error, "no *.rq files in #{Path.join(pack_dir, "gates")}"}
    else
      names = Enum.map_join(queries, ", ", fn {name, _path} -> name end)
      count = length(queries)
      {:ok, "#{count} gate quer#{if count == 1, do: "y", else: "ies"} found: #{names}"}
    end
  end

  # 11. At least one template present
  defp check_template_present(pack_dir) do
    templates_dir = Path.join(pack_dir, "templates")
    paths = Path.wildcard(Path.join(templates_dir, "*.{eex,tmpl}"))

    case paths do
      [] ->
        {:error, "no *.eex/*.tmpl files in #{templates_dir}"}

      _ ->
        names = Enum.map_join(paths, ", ", &Path.basename/1)
        count = length(paths)
        {:ok, "#{count} template#{if count == 1, do: "", else: "s"} found: #{names}"}
    end
  end

  # 12. Gate queries are syntactically valid SPARQL
  defp check_gate_queries_parse(pack_dir) do
    queries = Pack.discover_queries(pack_dir)

    failures =
      queries
      |> Enum.map(fn {name, path} ->
        case SPARQL.query(File.read!(path)) do
          %SPARQL.Query{} -> nil
          {:error, reason} -> "#{name} (#{path}) failed to parse: #{inspect(reason)}"
        end
      end)
      |> Enum.reject(&is_nil/1)
      |> then(fn f -> if f == [], do: nil, else: f end)

    cond do
      queries == [] ->
        {:warn, "no gate queries to parse-check"}

      is_nil(failures) ->
        {:ok, "all #{length(queries)} gate queries parse"}

      true ->
        {:error, Enum.join(failures, "; ")}
    end
  rescue
    error -> {:error, "gate query parse check raised: #{Exception.message(error)}"}
  end

  # 13. Target dir git status
  defp check_git_status do
    case System.cmd("git", ["status", "--porcelain"], cd: File.cwd!(), stderr_to_stdout: true) do
      {output, 0} ->
        dirty_count = output |> String.split("\n", trim: true) |> length()

        if dirty_count == 0 do
          {:ok, "git clean"}
        else
          {:warn, "git dirty (#{dirty_count} uncommitted change(s))"}
        end

      {output, _code} ->
        # `:warn`, not `:error`: this module's own moduledoc (check 13)
        # documents "clean vs dirty is reported, never fails the run by
        # itself" -- `{:error, ...}` here contradicted that (an `:error`
        # status fails the aggregate `mix ggen_igniter.doctor` run, per the
        # `Enum.any?(checks, fn {status, _} -> status == :error end)` gate
        # below). Confirmed as a real, reachable bug via Agent 8's real
        # consumer-scenario audit (2026-08-27): a real, git-free fixture
        # project (e.g. a fresh tmp-dir scaffold before `git init`) made the
        # whole doctor run exit 1 solely because it had no `.git` yet, not
        # because of any real project defect -- not a git repo is advisory
        # information, the same as a dirty working tree, not a checklist
        # failure.
        {:warn, "not a git repo (or git not on PATH): #{String.trim(output)}"}
    end
  rescue
    error -> {:warn, "not a git repo (or git not on PATH): #{Exception.message(error)}"}
  end

  # 14. native/ggen_graph_nif compiles / is up to date
  @nif_crate_dir "native/ggen_graph_nif"
  @nif_so_path "priv/native/ggen_graph_nif.so"

  # The `native/ggen_graph_nif` crate only physically exists inside the
  # `ggen_igniter` package's own directory tree. When this task runs as a
  # *consumer's* Mix task (the real, common case: a consumer app that added
  # `{:ggen_igniter, ...}` as a dependency runs `mix ggen_igniter.doctor`),
  # `File.cwd!()` is the consumer's own project root, which never contains
  # `native/ggen_graph_nif` -- verified directly via a real `mix igniter.new
  # --install ash,ash_phoenix --with phx.new` consumer scaffold: this check
  # unconditionally reported "native/ggen_graph_nif directory not found" and
  # failed the whole doctor run (exit 1) for every such consumer, with no
  # way to pass. `ggen_igniter_root/0` resolves the crate's real location:
  # when this project itself IS `:ggen_igniter` (its own dev/test loop,
  # dogfooding), `Mix.Project.deps_paths/0` won't list itself, so fall back
  # to `File.cwd!()`; when running as a dependency, resolve
  # `Mix.Project.deps_paths()[:ggen_igniter]` for the real on-disk path
  # (works for both a Hex-fetched copy and a `path:`/`git:` dependency).
  defp ggen_igniter_root do
    case Mix.Project.config()[:app] do
      :ggen_igniter ->
        File.cwd!()

      _ ->
        case Mix.Project.deps_paths()[:ggen_igniter] do
          nil -> File.cwd!()
          path -> path
        end
    end
  end

  defp check_nif_compiles do
    root = ggen_igniter_root()
    crate_dir = Path.join(root, @nif_crate_dir)
    so_path = Path.join(root, @nif_so_path)

    cond do
      not File.dir?(crate_dir) ->
        {:error, "#{@nif_crate_dir} directory not found"}

      nif_so_up_to_date?(so_path, crate_dir) ->
        {:ok,
         "#{@nif_so_path} exists and is newer than every .rs source file (skipped real build)"}

      true ->
        case System.cmd("cargo", ["build", "--quiet"], cd: crate_dir, stderr_to_stdout: true) do
          {_output, 0} ->
            {:ok, "#{@nif_crate_dir} compiles (real cargo build --quiet)"}

          {output, code} ->
            {:error,
             "#{@nif_crate_dir} failed to compile (cargo exit #{code}): #{String.trim(output)}"}
        end
    end
  rescue
    error -> {:error, "#{@nif_crate_dir} compile check raised: #{Exception.message(error)}"}
  end

  defp nif_so_up_to_date?(so_path, crate_dir) do
    with true <- File.exists?(so_path),
         {:ok, %File.Stat{mtime: so_mtime}} <- File.stat(so_path) do
      src_dir = Path.join(crate_dir, "src")

      src_dir
      |> Path.join("**/*.rs")
      |> Path.wildcard()
      |> Enum.all?(&rs_source_not_newer_than?(&1, so_mtime))
    else
      _ -> false
    end
  end

  defp rs_source_not_newer_than?(rs_path, so_mtime) do
    case File.stat(rs_path) do
      {:ok, %File.Stat{mtime: rs_mtime}} -> rs_mtime <= so_mtime
      {:error, _} -> false
    end
  end

  # 15. GgenIgniter.Query.Oxigraph functional smoke test
  defp check_oxigraph_smoke_test do
    graph =
      RDF.Graph.new([
        {RDF.iri("http://example.org/s"), RDF.iri("http://example.org/p"),
         RDF.iri("http://example.org/o")}
      ])

    case GgenIgniter.Query.Oxigraph.run(graph, "SELECT * WHERE { ?s ?p ?o }") do
      rows when is_list(rows) ->
        {:ok,
         "GgenIgniter.Query.Oxigraph real SELECT query against an in-memory graph returned #{length(rows)} row(s)"}
    end
  rescue
    error -> {:error, "GgenIgniter.Query.Oxigraph smoke test raised: #{Exception.message(error)}"}
  end

  # 16. hex-publish readiness (only with --hex-check)
  #
  # `--fix` first: `GgenIgniter.DoctorFixes.hex_publish_rules/0` (two real,
  # bounded fixes -- wiring an existing `description/0` function into
  # `package/0`, and wiring a `licenses:` entry from an exact, recognized
  # LICENSE-file SPDX header) run through the same generic
  # `run_rule_check/2` engine checks 4-7/17 use, against the CURRENT
  # project's real `mix.exs`, before the metadata check below runs.
  defp maybe_check_hex_publish(opts) do
    if opts[:hex_check] do
      package_fix_checks = Enum.map(DoctorFixes.hex_publish_rules(), &run_rule_check(opts, &1))
      package_fix_checks ++ [tag("hex_publish_readiness", check_hex_publish_readiness())]
    else
      []
    end
  end

  defp check_hex_publish_readiness do
    # Reads `mix.exs`'s real, CURRENT text directly
    # (`DoctorFixes.package_metadata_keys_present/1`) rather than the
    # in-process `Mix.Project.config()[:package]`, which was loaded once at
    # BEAM boot and does NOT reflect a `--fix` write made earlier in this
    # same `mix ggen_igniter.doctor --hex-check --fix` invocation
    # (`maybe_check_hex_publish/1` applies `package_description_rule`/
    # `package_licenses_rule` before this check runs) -- confirmed as a
    # real, reachable staleness bug via a real break/fix/verify run
    # (2026-08-28): `Mix.Project.config()` still reported both keys
    # missing immediately after their real `--fix` had already rewritten
    # `mix.exs` to contain them.
    keys_present = DoctorFixes.package_metadata_keys_present(File.cwd!())

    metadata_errors =
      []
      |> then(fn acc ->
        if keys_present.description,
          do: acc,
          else: ["package[:description] is missing/empty" | acc]
      end)
      |> then(fn acc ->
        if keys_present.licenses, do: acc, else: ["package[:licenses] is missing/empty" | acc]
      end)

    case System.cmd("mix", ["hex.build"], cd: File.cwd!(), stderr_to_stdout: true) do
      {output, 0} when metadata_errors == [] ->
        {:ok, "mix hex.build succeeded and package metadata is present:\n#{String.trim(output)}"}

      {output, 0} ->
        {:error,
         "mix hex.build succeeded but metadata is incomplete (#{Enum.join(metadata_errors, "; ")}):\n#{String.trim(output)}"}

      {output, code} ->
        {:error, "mix hex.build failed (exit #{code}): #{String.trim(output)}"}
    end
  rescue
    error -> {:error, "hex-publish readiness check raised: #{Exception.message(error)}"}
  end
end
