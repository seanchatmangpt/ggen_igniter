defmodule GgenIgniter.DoctorFixes do
  @moduledoc """
  Real, reusable implementations of the project-hygiene fixes that
  `mix ggen_igniter.doctor --fix` applies to the CURRENT project (the real
  consumer app `doctor` is invoked inside -- not a scaffolded test harness).

  Four of these (dep `:only` relaxation x2, `config :dcatr, env: ...`,
  `ash_domains:` registration) started life as hand-rolled helpers in
  `test/e2e/support/e2e_case.ex` (`relax_scaffolded_igniter_dep!/1`,
  `relax_scaffolded_sourceror_dep!/1`, `add_dcatr_env_config!/1`,
  `add_ash_domains_config!/3`), written for one specific scaffolded-app
  shape (an `igniter.new --install ash,ash_phoenix --with phx.new`
  fixture with exact, hard-coded version strings). This module extracts the
  same real fix classes into general-purpose, real production code that
  works against ANY real consumer project's `mix.exs`/`config/config.exs`/
  `lib/` tree, not just that one fixture shape -- version requirements and
  `:only` values are detected from the file's real content rather than
  assumed.

  ## Declarative rule engine

  Each of those four real fixes is data: a `#{inspect(__MODULE__)}.Rule`
  struct of `%Rule{name:, predicate:, transform:, verify:}`, where every
  field is a real function over a real `project_dir` (never `File.cwd!()`
  read internally, so every rule is trivially testable against a real temp
  directory fixture):

  ## Structural codemods, not text/regex splices (`transform`s only)

  Every `transform` in this module (`dep_only_transform!/2`,
  `apply_ash_domains_fix!/4`, `package_description_transform!/1`,
  `package_licenses_transform!/1`, and `fix_version_policy!/1`'s write
  branch) parses the target file with `Sourceror.parse_string!/1`,
  walks/edits the real AST via a `Sourceror.Zipper`, and re-serializes
  with `Sourceror.to_string/1` -- using Igniter's own pure-zipper codemod
  primitives (`Igniter.Code.Module`, `Igniter.Code.Function`,
  `Igniter.Code.List`, `Igniter.Code.Tuple`, `Igniter.Code.Keyword`, and
  `Igniter.Project.Config.modify_config_code/4,5`) rather than hand-rolled
  zipper traversal. Every one of those operates on a plain
  `Sourceror.Zipper.t()` and needs no `%Igniter{}` -- confirmed by reading
  `Igniter.new/0`, `Igniter.Project.Deps`, `Igniter.Project.Config`, and
  `Igniter.Code.Common` before writing any of this. `Igniter.new/0` builds
  a `Rewrite` project that resolves file paths like `"mix.exs"` against
  the running process's own cwd, which is incompatible with this module's
  contract (`project_dir` is an explicit argument, never `File.cwd!()`, so
  every rule stays testable against an arbitrary temp-dir fixture
  regardless of the real process's cwd); building a throwaway `%Igniter{}`
  scoped to `project_dir` would require `File.cd!/2`-ing the whole BEAM
  process into it for the duration of the call, which is unsafe under
  `async: true` tests that may run concurrently in other directories. The
  lower-level `Igniter.Code.*` modules and
  `Igniter.Project.Config.modify_config_code/5` sidestep that entirely:
  they take a `Sourceror.Zipper.t()` built directly from a source string
  and return an updated one, no `%Igniter{}`/`Rewrite`/cwd involved -- an
  exact fit for `run_rule/3`'s real contract (read a real file for a real
  `project_dir`, write a real fixed file, no implicit process-global
  state).

  Only `transform`s were migrated this way -- `predicate`s stay
  regex-based read-only detection heuristics (unchanged, and still the
  thing that decides `:ok`/`:fixable`/`:unrecognized`); a `predicate`
  finding `:fixable` is what licenses a `transform` to run at all, and the
  structural rewrite is expected to always find what the predicate found
  for any shape the predicate recognizes -- a mismatch (predicate says
  fixable, the structural rewrite can't locate the same node) raises a
  `RuntimeError` rather than silently reporting false success or guessing
  a different edit, same discipline as everywhere else in this module.

    * `predicate` -- read-only. Inspects real files and returns
      `{:ok, message}` (nothing wrong), `{:fixable, message}` (a real,
      recognized gap `transform` can safely repair), or
      `{:unrecognized, message}` (a real problem exists, but its exact
      shape isn't one this rule can safely rewrite without guessing).
    * `transform` -- called only when `predicate` returned `:fixable`.
      Applies the real fix (writes the real file) and returns
      `{:fixed, message}` describing exactly what changed.
    * `verify` -- called after `transform` runs. Re-reads the real file and
      confirms the gap is actually gone (re-runs `predicate` and requires
      `:ok`) -- a transform that writes a file but doesn't actually close
      the gap it claimed to fix is a real bug, not a `{:fixed, ...}`
      result.

  `run_rule/3` is the one generic dispatcher every rule goes through: read
  real file -> apply predicate -> if asked to fix, apply transform ->
  verify -> return a real, structured result. A newly-discovered
  Igniter/Ash wiring-gap class is a new `Rule` (data: a
  predicate/transform/verify triple) appended to `default_rules/0`, never a
  new hand-written `check_*`/`fix_*!` function pair, and never a new
  hand-written check function in `Mix.Tasks.GgenIgniter.Doctor` either --
  that task iterates `default_rules/0` generically (see its `igniter/1`).

  `default_rules/0` returns the four rules `mix ggen_igniter.doctor`
  actually runs through the generic engine, in the same order it has
  always run them.

  The six functions below (`check_dep_only/2`, `fix_dep_only!/2`,
  `check_dcatr_env_config/1`, `fix_dcatr_env_config!/1`,
  `check_ash_domains/1`, `fix_ash_domains!/1`) are the same public API this
  module has always exposed -- now thin wrappers over `run_rule/3` and the
  matching `Rule` -- kept for direct callers (including this module's own
  test suite). Reach for `run_rule/3` + `default_rules/0` for any NEW rule;
  the six wrappers exist only to keep the existing call sites unchanged.

  ## Contract shared by every `check_*/fix_*!` pair

    * `check_*` is read-only: it inspects real files and returns
      `{:ok, message}` (nothing wrong), `{:fixable, message}` (a real,
      recognized problem `fix_*!` can safely repair), or
      `{:unrecognized, message}` (a real problem exists, but its exact
      shape isn't one this module can safely rewrite without guessing).
    * `fix_*!` re-runs the same detection, and:
        - no-ops with `{:ok, message}` if there was nothing to fix,
        - applies the fix and returns `{:fixed, message}` if it was
          `:fixable`,
        - `raise`s a `RuntimeError` with the same discipline as the
          original `e2e_case.ex` helpers ("raise a clear error rather than
          guess") if the real shape was `:unrecognized` -- it NEVER
          silently no-ops on a real problem, and never regex-rewrites a
          shape it doesn't precisely recognize.

  ## `check_version_policy/1` / `fix_version_policy!/1`

  A fifth real check/fix pair (`mix.exs`'s `version:` vs. `CHANGELOG.md`'s
  topmost `## vX` heading) lives at the bottom of this module. It predates
  this rule-engine pass, is not one of the four fixes the engine above was
  built to generalize, and is left as a plain function pair here (not
  folded into `default_rules/0`/`hex_publish_rules/0`) -- it fits the same
  `(Predicate, Transformation, Verification)` shape and is a natural future
  `Rule`, but wiring it into the declarative engine (a new public entry
  point, a new `default_rules/0` slot, `Mix.Tasks.GgenIgniter.Doctor`
  wiring) is a separate, larger change than the structural-rewrite pass
  this fix's own `fix_version_policy!/1` already received (see
  `rewrite_version_literal/2`).
  """

  @config_relpath "config/config.exs"
  @import_config_marker "import_config \"\#{config_env()}.exs\""

  defmodule Rule do
    @moduledoc """
    Data shape of one declarative doctor reconciliation rule: a
    `(Predicate, Transformation, Verification)` triple, per
    `GgenIgniter.DoctorFixes`'s moduledoc. Every field is a real,
    single-argument function over a `project_dir` -- no captured mutable
    state, no `File.cwd!()`/`Mix.Project` reads baked in, so a `Rule` is as
    testable against a throwaway temp directory as any of the plain
    functions it replaces.
    """

    @enforce_keys [:name, :predicate, :transform, :verify]
    defstruct [:name, :predicate, :transform, :verify]

    @type predicate_result ::
            {:ok, String.t()} | {:fixable, String.t()} | {:unrecognized, String.t()}

    @type t :: %__MODULE__{
            name: String.t(),
            predicate: (Path.t() -> predicate_result()),
            transform: (Path.t() -> {:fixed, String.t()}),
            verify: (Path.t() -> boolean())
          }
  end

  @doc """
  The one generic engine every `Rule` runs through: read real project
  state (`rule.predicate.(project_dir)`), and:

    * `{:ok, message}` -- nothing to do, passed through as-is.
    * `{:unrecognized, message}` -- a real gap exists but this rule refuses
      to guess how to close it. Returned as data when `fix?` is `false`
      (diagnostic mode); raised as a `RuntimeError` when `fix?` is `true`
      (matching every existing `fix_*!`'s "never silently no-op on a real
      problem" discipline).
    * `{:fixable, message}` -- a real, safely-automatable gap.
      When `fix?` is `false`, returned as-is (diagnostic mode). When `fix?`
      is `true`, `rule.transform.(project_dir)` is applied for real, then
      `rule.verify.(project_dir)` re-reads the real file and confirms the
      gap is actually gone -- raising a `RuntimeError` (never reporting a
      false `{:fixed, ...}`) if the transform ran but the real post-fix
      state still shows the same gap.
  """
  @spec run_rule(Rule.t(), Path.t(), boolean()) ::
          {:ok, String.t()}
          | {:fixed, String.t()}
          | {:fixable, String.t()}
          | {:unrecognized, String.t()}
  def run_rule(%Rule{} = rule, project_dir, fix? \\ false) do
    case rule.predicate.(project_dir) do
      {:ok, msg} ->
        {:ok, msg}

      {:unrecognized, msg} ->
        if fix?, do: raise(RuntimeError, msg), else: {:unrecognized, msg}

      {:fixable, msg} ->
        if fix? do
          {:fixed, fixed_msg} = rule.transform.(project_dir)

          unless rule.verify.(project_dir) do
            raise RuntimeError,
                  "#{rule.name}: transform ran against #{project_dir} but the real " <>
                    "post-fix predicate re-check still finds the same gap -- refusing to " <>
                    "report success"
          end

          {:fixed, fixed_msg}
        else
          {:fixable, msg}
        end
    end
  end

  @doc """
  The four real rules `mix ggen_igniter.doctor` runs through `run_rule/3`,
  in the same order it has always run them. Adding a new Igniter/Ash
  wiring-gap class means appending one more `%Rule{}` here (data) -- never
  writing a new `check_*`/`fix_*!` function pair, and never touching
  `Mix.Tasks.GgenIgniter.Doctor` (it iterates this list generically).
  """
  @spec default_rules() :: [Rule.t()]
  def default_rules do
    [
      dep_only_rule(:igniter),
      dep_only_rule(:sourceror),
      dcatr_env_rule(),
      ash_domains_rule()
    ]
  end

  @doc """
  The two `package[...]` metadata rules `mix ggen_igniter.doctor`'s check 16
  (`--hex-check`) runs through `run_rule/3`, applied to the CURRENT
  project's `mix.exs` -- see `package_description_rule/0` and
  `package_licenses_rule/0`. Kept separate from `default_rules/0` because
  they only matter when `--hex-check` is passed (check 16 is off by
  default; see `Mix.Tasks.GgenIgniter.Doctor`'s moduledoc).
  """
  @spec hex_publish_rules() :: [Rule.t()]
  def hex_publish_rules do
    [package_description_rule(), package_licenses_rule()]
  end

  # ---------------------------------------------------------------------
  # Rule 1 & 2: relax an `:only`-restricted `igniter`/`sourceror` dependency
  # ---------------------------------------------------------------------

  @doc """
  Builds the `Rule` that detects and relaxes an `:only`-restricted `dep`
  (e.g. `:igniter` or `:sourceror`) in `project_dir`'s own `mix.exs` -- the
  same real conflict class this session hit repeatedly: `ggen_igniter`
  itself needs `:igniter`/`:sourceror` unconditionally (every consuming
  app, every `Mix.env/0`), so a consumer's own `:only`-restricted direct
  declaration of the same dependency causes Mix's resolver to refuse
  ("Dependencies have diverged").

  Only recognizes a single-line dependency tuple of the shape
  `{:dep, "VERSION_REQ", only: ONLY_VALUE}` (the real shape generated by
  `igniter.new`/`phx.new`, and the common hand-written shape); returns
  `:unrecognized` rather than guessing for any other shape.
  """
  @spec dep_only_rule(atom()) :: Rule.t()
  def dep_only_rule(dep) do
    %Rule{
      name: "#{dep}_only_relaxation",
      predicate: fn project_dir -> dep_only_predicate(project_dir, dep) end,
      transform: fn project_dir -> dep_only_transform!(project_dir, dep) end,
      verify: fn project_dir -> match?({:ok, _}, dep_only_predicate(project_dir, dep)) end
    }
  end

  @doc "Read-only check for `dep_only_rule/1`. See `GgenIgniter.DoctorFixes.Rule`."
  @spec check_dep_only(Path.t(), atom()) ::
          {:ok, String.t()} | {:fixable, String.t()} | {:unrecognized, String.t()}
  def check_dep_only(project_dir, dep), do: dep_only_predicate(project_dir, dep)

  @doc "Applies `dep_only_rule/1`'s fix for real. See `GgenIgniter.DoctorFixes.Rule`."
  @spec fix_dep_only!(Path.t(), atom()) :: {:ok, String.t()} | {:fixed, String.t()}
  def fix_dep_only!(project_dir, dep), do: run_rule(dep_only_rule(dep), project_dir, true)

  defp dep_only_predicate(project_dir, dep) do
    mix_exs_path = Path.join(project_dir, "mix.exs")
    source = File.read!(mix_exs_path)

    case locate_dep_tuple(source, dep) do
      {:error, :no_deps_fn} ->
        {:unrecognized, "could not locate a deps/0 function body in #{mix_exs_path}"}

      {:ok, :not_declared} ->
        {:ok, "#{dep} is not directly declared in #{mix_exs_path} (nothing to relax)"}

      {:ok, {:tuple, tuple_text}} ->
        if Regex.match?(~r/\bonly:/, tuple_text) do
          case strip_only(tuple_text) do
            nil ->
              {:unrecognized,
               "found a :#{dep} dependency with an `only:` restriction in #{mix_exs_path}, " <>
                 "but its exact shape was not recognized: #{String.trim(tuple_text)}"}

            _fixed ->
              {:fixable,
               "#{dep} dependency in #{mix_exs_path} is restricted (#{String.trim(tuple_text)}) " <>
                 "-- ggen_igniter needs :#{dep} unconditionally, in every Mix.env"}
          end
        else
          {:ok, "#{dep} dependency in #{mix_exs_path} has no :only restriction"}
        end
    end
  end

  # Assumes `dep_only_predicate/2` has already confirmed `:fixable` (the
  # only case `run_rule/3` invokes this from); rewrites `project_dir`'s
  # `mix.exs`, removing the `:only` restriction from `dep`'s dependency
  # tuple (and only that -- any other options on the same tuple, e.g.
  # `runtime: false`, are preserved) via a structural `Sourceror.Zipper`
  # rewrite of the real `deps/0` AST -- never a text/regex replacement.
  defp dep_only_transform!(project_dir, dep) do
    mix_exs_path = Path.join(project_dir, "mix.exs")
    source = File.read!(mix_exs_path)

    case rewrite_dep_only(source, dep) do
      {:ok, %{source: updated, before: before_text}} ->
        File.write!(mix_exs_path, updated)

        {:fixed,
         "relaxed :#{dep} dependency in #{mix_exs_path}: removed `only:` from `#{before_text}`"}

      :error ->
        raise RuntimeError,
              "#{dep}_only_relaxation: predicate found a fixable :only restriction on :#{dep} " <>
                "in #{mix_exs_path}, but the structural Sourceror.Zipper rewrite could not " <>
                "locate/relax the same dependency tuple -- refusing to guess"
    end
  end

  # Structural counterpart of `locate_dep_tuple/2` + `strip_only/1`: parses
  # `source` for real, walks to the `deps/0` list via
  # `Igniter.Code.Module.move_to_module_using/2` +
  # `Igniter.Code.Function.move_to_defp/3` (the same real, pure-zipper
  # primitives `Igniter.Project.Deps.set_dep_option/4` uses), locates
  # `dep`'s tuple via `Igniter.Code.List.move_to_list_item/2` +
  # `Igniter.Code.Tuple.elem_equals?/3`, then removes just the `only:` key
  # from that tuple's options via `Igniter.Code.Keyword.remove_keyword_key/2`
  # -- a real AST edit, not a string splice. Every other option on the
  # tuple (and every other dependency in the list) is left byte-for-byte
  # untouched. Returns `:error` (never a guess) if any step doesn't find
  # what the regex-based predicate already confirmed was there.
  defp rewrite_dep_only(source, dep) do
    zipper = source |> Sourceror.parse_string!() |> Sourceror.Zipper.zip()

    with {:ok, zipper} <- Igniter.Code.Module.move_to_module_using(zipper, Mix.Project),
         {:ok, zipper} <- Igniter.Code.Function.move_to_defp(zipper, :deps, 0),
         true <- Igniter.Code.List.list?(zipper),
         {:ok, tuple_zipper} <-
           Igniter.Code.List.move_to_list_item(zipper, fn item ->
             Igniter.Code.Tuple.tuple?(item) and Igniter.Code.Tuple.elem_equals?(item, 0, dep)
           end),
         before_text <-
           tuple_zipper |> Sourceror.Zipper.node() |> Sourceror.to_string() |> String.trim(),
         {:ok, opts_zipper} <- Igniter.Code.Tuple.tuple_elem(tuple_zipper, 2),
         {:ok, opts_zipper} <- Igniter.Code.Keyword.remove_keyword_key(opts_zipper, :only) do
      final_zipper = collapse_empty_dep_opts(opts_zipper)

      {:ok,
       %{
         source: final_zipper |> Sourceror.Zipper.root() |> Sourceror.to_string(),
         before: before_text
       }}
    else
      _ -> :error
    end
  end

  # After removing `:only` (and possibly other options) leaves a dependency
  # tuple's options list empty (e.g. `{:igniter, "~> 0.8", only: :dev}` had
  # no other options), collapses the now-degenerate `{name, version, []}`
  # 3-tuple back down to the plain `{name, version}` 2-tuple shape
  # `igniter.new`/`phx.new` generate for an unrestricted dependency --
  # matching this rule's own tests, which assert on that exact 2-tuple
  # text. When other options remain (e.g. `runtime: false`), the tuple
  # stays a 3-tuple with the reduced options list untouched.
  defp collapse_empty_dep_opts(opts_zipper) do
    if Sourceror.Zipper.node(opts_zipper) == [] do
      tuple_zipper = Sourceror.Zipper.up(opts_zipper)

      with {:ok, name_zipper} <- Igniter.Code.Tuple.tuple_elem(tuple_zipper, 0),
           {:ok, version_zipper} <- Igniter.Code.Tuple.tuple_elem(tuple_zipper, 1) do
        Sourceror.Zipper.replace(
          tuple_zipper,
          {Sourceror.Zipper.node(name_zipper), Sourceror.Zipper.node(version_zipper)}
        )
      else
        _ -> opts_zipper
      end
    else
      opts_zipper
    end
  end

  # Locates the `defp deps do ... end` / `def deps do ... end` function body
  # in a real mix.exs source string, then finds `dep`'s own dependency tuple
  # inside it. Returns `{:error, :no_deps_fn}` if no deps/0 function body can
  # be found at all, `{:ok, :not_declared}` if `dep` isn't in the list, or
  # `{:ok, {:tuple, text}}` with the exact matched tuple text (a real
  # substring of `source`, suitable for a precise `String.replace/4`).
  defp locate_dep_tuple(source, dep) do
    case Regex.run(~r/def(?:p)?\s+deps\s+do\s*\n(.*?)\n[ \t]*end/s, source) do
      nil ->
        {:error, :no_deps_fn}

      [_, deps_body] ->
        dep_re = ~r/\{\s*:#{Regex.escape(to_string(dep))}\s*,[^{}]*\}/

        case Regex.run(dep_re, deps_body) do
          nil -> {:ok, :not_declared}
          [tuple_text] -> {:ok, {:tuple, tuple_text}}
        end
    end
  end

  # Strips a recognized `only: ...` keyword pair out of a single dependency
  # tuple's text, preserving every other option on the tuple. Returns `nil`
  # (never a guess) if `only:` is present but not in a recognized position.
  defp strip_only(tuple_text) do
    only_value = ~S/(?:\[[^\]]*\]|:[a-zA-Z_][a-zA-Z0-9_]*)/

    cond do
      Regex.match?(~r/,\s*only:\s*#{only_value}\s*,/, tuple_text) ->
        Regex.replace(~r/,\s*only:\s*#{only_value}\s*,/, tuple_text, ",", global: false)

      Regex.match?(~r/,\s*only:\s*#{only_value}\s*\}\z/, tuple_text) ->
        Regex.replace(~r/,\s*only:\s*#{only_value}\s*\}\z/, tuple_text, "}", global: false)

      true ->
        nil
    end
  end

  # ---------------------------------------------------------------------
  # Rule 3: missing `config :dcatr, env: ...` (needed transitively by :gno)
  # ---------------------------------------------------------------------

  @doc """
  Builds the `Rule` that detects and adds a missing `config :dcatr, env:
  ...` entry in `project_dir`'s `config/config.exs`.

  `:gno`'s own `Gno.Store.Adapters.Fuseki` calls `DCATR.Manifest.env/1` at
  compile time, which raises unless `config :dcatr, env: ...` (or the
  `DCATR_ENV`/`MIX_ENV` OS environment variable) is set. Only relevant if
  `:gno` or `:dcatr` is actually present in the CURRENT project's own
  dependency tree (checked the same way `ggen_igniter.doctor`'s existing
  `check_deps/1` checks required deps: `Application.ensure_loaded/1` +
  `Application.spec/2`).
  """
  @spec dcatr_env_rule() :: Rule.t()
  def dcatr_env_rule do
    %Rule{
      name: "dcatr_env_config",
      predicate: &dcatr_env_predicate/1,
      transform: &dcatr_env_transform!/1,
      verify: fn project_dir -> match?({:ok, _}, dcatr_env_predicate(project_dir)) end
    }
  end

  @doc "Read-only check for `dcatr_env_rule/0`. See `GgenIgniter.DoctorFixes.Rule`."
  @spec check_dcatr_env_config(Path.t()) :: {:ok, String.t()} | {:fixable, String.t()}
  def check_dcatr_env_config(project_dir), do: dcatr_env_predicate(project_dir)

  @doc "Applies `dcatr_env_rule/0`'s fix for real. See `GgenIgniter.DoctorFixes.Rule`."
  @spec fix_dcatr_env_config!(Path.t()) :: {:ok, String.t()} | {:fixed, String.t()}
  def fix_dcatr_env_config!(project_dir), do: run_rule(dcatr_env_rule(), project_dir, true)

  defp dcatr_env_predicate(project_dir) do
    config_path = Path.join(project_dir, @config_relpath)

    cond do
      not (app_loaded?(:gno) or app_loaded?(:dcatr)) ->
        {:ok,
         ":gno/:dcatr not present in the dependency tree -- config :dcatr, env: ... not needed"}

      dcatr_env_configured?(config_path) ->
        {:ok, "config :dcatr, env: ... already present in #{config_path}"}

      true ->
        {:fixable,
         ":gno/:dcatr present in the dependency tree but config :dcatr, env: ... is missing " <>
           "from #{config_path}"}
    end
  end

  # Assumes `dcatr_env_predicate/1` has already confirmed `:fixable`.
  # Insertion strategy (never a full-file rewrite):
  #
  #   * if the file already ends with the standard `phx.new`-generated
  #     `import_config "#{config_env()}.exs"` marker, insert immediately
  #     before it (so per-env overrides in `dev.exs`/`test.exs`/`prod.exs`
  #     still take effect after this base value, matching Phoenix's own
  #     convention);
  #   * else if the file exists but has no such marker, append at the end;
  #   * else (no `config/config.exs` at all) create a minimal new one.
  #
  # This never raises: every branch is a safe, additive text insertion, not
  # a guess about existing content's shape.
  defp dcatr_env_transform!(project_dir) do
    config_path = Path.join(project_dir, @config_relpath)
    dcatr_config = "config :dcatr, env: Mix.env()\n\n"

    write_config_insertion!(config_path, dcatr_config)

    {:fixed, "added `config :dcatr, env: Mix.env()` to #{config_path}"}
  end

  defp dcatr_env_configured?(config_path) do
    case File.read(config_path) do
      {:ok, content} -> Regex.match?(~r/config\s+:dcatr\s*,\s*env:/, content)
      {:error, _} -> false
    end
  end

  # ---------------------------------------------------------------------
  # Rule 4: Ash domain modules missing from `config :OTP_APP, ash_domains:`
  # ---------------------------------------------------------------------

  @doc """
  Builds the `Rule` that scans `project_dir`'s `lib/` tree for modules that
  `use Ash.Domain` (a real textual scan -- these fixture/consumer trees are
  not necessarily compiled, so this deliberately does not require
  `Code.ensure_loaded?/1`) and registers any that are missing from
  `config :OTP_APP, ash_domains: [...]` in `config/config.exs`, where
  `OTP_APP` is `project_dir`'s own `mix.exs` `app:` value.

  The predicate returns `{:unrecognized, message}` (never guesses) if
  `config :OTP_APP, ...ash_domains: ...` is present but its value isn't a
  simple literal list this rule can safely merge into.
  """
  @spec ash_domains_rule() :: Rule.t()
  def ash_domains_rule do
    %Rule{
      name: "ash_domains_registration",
      predicate: &ash_domains_predicate/1,
      transform: &ash_domains_transform!/1,
      verify: fn project_dir -> match?({:ok, _}, ash_domains_predicate(project_dir)) end
    }
  end

  @doc "Read-only check for `ash_domains_rule/0`. See `GgenIgniter.DoctorFixes.Rule`."
  @spec check_ash_domains(Path.t()) ::
          {:ok, String.t()} | {:fixable, String.t()} | {:unrecognized, String.t()}
  def check_ash_domains(project_dir), do: ash_domains_predicate(project_dir)

  @doc "Applies `ash_domains_rule/0`'s fix for real. See `GgenIgniter.DoctorFixes.Rule`."
  @spec fix_ash_domains!(Path.t()) :: {:ok, String.t()} | {:fixed, String.t()}
  def fix_ash_domains!(project_dir), do: run_rule(ash_domains_rule(), project_dir, true)

  defp ash_domains_predicate(project_dir) do
    domains = discover_ash_domain_modules(project_dir)

    if domains == [] do
      {:ok, "no `use Ash.Domain` modules found under #{Path.join(project_dir, "lib")}"}
    else
      otp_app = read_otp_app!(project_dir)

      case registered_ash_domains(project_dir, otp_app) do
        {:error, reason} ->
          {:unrecognized, reason}

        {:ok, registered} ->
          missing = domains -- registered

          if missing == [] do
            {:ok,
             "all #{length(domains)} Ash domain module(s) already registered in " <>
               "config :#{otp_app}, ash_domains: [...]"}
          else
            {:fixable,
             "#{length(missing)} Ash domain module(s) not registered in config :#{otp_app}, " <>
               "ash_domains: [...]: #{Enum.join(missing, ", ")}"}
          end
      end
    end
  end

  # Assumes `ash_domains_predicate/1` has already confirmed `:fixable`.
  #
  #   * if no `ash_domains:` entry exists yet for this OTP app, inserts a
  #     new `config :OTP_APP, ash_domains: [...]` block (same insertion
  #     strategy as `dcatr_env_transform!/1`);
  #   * if one already exists as a simple literal list, merges the missing
  #     module(s) into it via a precise, minimal in-place text replacement
  #     of just the bracketed list contents -- every other line of the
  #     file is untouched.
  defp ash_domains_transform!(project_dir) do
    otp_app = read_otp_app!(project_dir)
    domains = discover_ash_domain_modules(project_dir)
    {:ok, registered} = registered_ash_domains(project_dir, otp_app)
    missing = domains -- registered

    config_path = Path.join(project_dir, @config_relpath)
    apply_ash_domains_fix!(config_path, otp_app, registered, missing)

    {:fixed,
     "registered #{length(missing)} Ash domain module(s) in #{config_path}: " <>
       "#{Enum.join(missing, ", ")}"}
  end

  defp discover_ash_domain_modules(project_dir) do
    project_dir
    |> Path.join("lib/**/*.ex")
    |> Path.wildcard()
    |> Enum.flat_map(&extract_ash_domain_modules/1)
    |> Enum.uniq()
  end

  defp extract_ash_domain_modules(file_path) do
    content = File.read!(file_path)

    if String.contains?(content, "use Ash.Domain") do
      content
      |> String.split("\n")
      |> Enum.reduce({[], nil}, fn line, {found, current_module} ->
        cond do
          match = Regex.run(~r/^\s*defmodule\s+([A-Z][A-Za-z0-9_.]*)\s+do/, line) ->
            [_, mod] = match
            {found, mod}

          Regex.match?(~r/^\s*use\s+Ash\.Domain\b/, line) and current_module != nil ->
            {[current_module | found], current_module}

          true ->
            {found, current_module}
        end
      end)
      |> elem(0)
    else
      []
    end
  end

  defp read_otp_app!(project_dir) do
    mix_exs_path = Path.join(project_dir, "mix.exs")
    source = File.read!(mix_exs_path)

    case Regex.run(~r/app:\s*:([a-zA-Z_][a-zA-Z0-9_]*)/, source) do
      [_, app] ->
        app

      nil ->
        raise RuntimeError,
              "could not find `app: :your_app` in #{mix_exs_path} -- refusing to guess the OTP app name"
    end
  end

  defp ash_domains_key_regex(otp_app) do
    ~r/config\s+:#{otp_app}\b(?:(?!\nconfig\s).)*?ash_domains:/s
  end

  defp ash_domains_block_regex(otp_app) do
    ~r/config\s+:#{otp_app}\b(?:(?!\nconfig\s).)*?ash_domains:\s*\[[^\]]*\]/s
  end

  defp registered_ash_domains(project_dir, otp_app) do
    config_path = Path.join(project_dir, @config_relpath)

    case File.read(config_path) do
      {:error, _} ->
        {:ok, []}

      {:ok, content} ->
        cond do
          not Regex.match?(ash_domains_key_regex(otp_app), content) ->
            {:ok, []}

          match = Regex.run(ash_domains_block_regex(otp_app), content) ->
            [block] = match
            {:ok, extract_domain_names(block)}

          true ->
            {:error,
             "found `config :#{otp_app}, ...ash_domains: ...` in #{config_path} but its " <>
               "value isn't a simple literal list -- refusing to guess how to merge into it"}
        end
    end
  end

  defp extract_domain_names(ash_domains_block) do
    [_, inner] = Regex.run(~r/\[([^\]]*)\]\z/, ash_domains_block)

    inner
    |> String.split(",")
    |> Enum.map(&String.trim/1)
    |> Enum.reject(&(&1 == ""))
  end

  # Structural counterpart of the old regex-block-splice: whether
  # `config :OTP_APP, ash_domains: [...]` already exists (as a 2- or
  # 3-arg `config` call, anywhere in the file), or doesn't exist at all
  # yet, `Igniter.Project.Config.modify_config_code/4` (a real,
  # pure-`Sourceror.Zipper` Igniter codemod -- no `%Igniter{}` needed, see
  # this module's moduledoc) handles both cases in one real AST edit:
  # replacing an existing `ash_domains:` value in place, or inserting a
  # brand-new `config :OTP_APP, ash_domains: [...]` node right after
  # `import Config` (before any `import_config "#{config_env()}.exs"`
  # marker, so per-env overrides still take effect after this base value)
  # when neither exists. Every other `config` entry in the file -- for
  # this app or any other -- is left untouched.
  defp apply_ash_domains_fix!(config_path, otp_app, registered, missing) do
    source = File.exists?(config_path) && File.read!(config_path)

    updated = rewrite_ash_domains!(source || "import Config\n", otp_app, registered ++ missing)

    File.mkdir_p!(Path.dirname(config_path))
    File.write!(config_path, updated)
  end

  defp rewrite_ash_domains!(source, otp_app, all_domains) do
    zipper = source |> Sourceror.parse_string!() |> Sourceror.Zipper.zip()
    value = Sourceror.parse_string!("[#{Enum.join(all_domains, ", ")}]")

    case Igniter.Project.Config.modify_config_code(
           zipper,
           [:ash_domains],
           String.to_atom(otp_app),
           value
         ) do
      {:ok, zipper} ->
        zipper |> Sourceror.Zipper.root() |> Sourceror.to_string()

      other ->
        raise RuntimeError,
              "ash_domains_registration: predicate found ash_domains registration fixable for " <>
                ":#{otp_app}, but the structural config codemod could not apply " <>
                "(#{inspect(other)}) -- refusing to guess"
    end
  end

  # ---------------------------------------------------------------------
  # Rule 5: `mix.exs`'s `package/0` missing `description:` -- check 16
  # (`--hex-check`)'s hex-publish-readiness metadata gap.
  # ---------------------------------------------------------------------

  @doc """
  Builds the `Rule` that detects a `package/0` function in `project_dir`'s
  `mix.exs` missing a `description:` entry, when the file already defines a
  `description/0` function elsewhere (the common shape: a project-level
  `description: description()` in `project/0`, with `package/0` simply
  forgetting to also reference it -- this repo's own `mix.exs` shows the
  intended pattern). Only fixable in that exact, unambiguous case: this
  never invents description text, it only wires up a function this project
  already declared. Any other shape (no `package/0` found, no
  `description/0` function defined anywhere in the file) is
  `{:unrecognized, ...}` -- refuses to guess prose.
  """
  @spec package_description_rule() :: Rule.t()
  def package_description_rule do
    %Rule{
      name: "package_description",
      predicate: &package_description_predicate/1,
      transform: &package_description_transform!/1,
      verify: fn project_dir -> match?({:ok, _}, package_description_predicate(project_dir)) end
    }
  end

  @doc """
  Reads `project_dir`'s real, CURRENT `mix.exs` source text directly (never
  the possibly-stale in-process `Mix.Project.config()`, which is loaded
  once and does not reflect a `mix.exs` write made later in the same BEAM
  process) and reports whether `package/0`'s body textually contains a
  `description:`/`licenses:` key. Used by check 16's hex-publish-readiness
  metadata check so a `--fix` applied earlier in the SAME `mix
  ggen_igniter.doctor --hex-check --fix` invocation is reflected
  immediately, not only on the next separate invocation.
  """
  @spec package_metadata_keys_present(Path.t()) :: %{description: boolean(), licenses: boolean()}
  def package_metadata_keys_present(project_dir) do
    mix_exs_path = Path.join(project_dir, "mix.exs")
    source = File.read!(mix_exs_path)

    case locate_fn_body(source, "package") do
      nil ->
        %{description: false, licenses: false}

      package_body ->
        %{
          description: Regex.match?(~r/\bdescription:/, package_body),
          licenses: Regex.match?(~r/\blicenses:/, package_body)
        }
    end
  end

  defp package_description_predicate(project_dir) do
    mix_exs_path = Path.join(project_dir, "mix.exs")
    source = File.read!(mix_exs_path)

    case locate_fn_body(source, "package") do
      nil ->
        {:unrecognized, "could not locate a package/0 function body in #{mix_exs_path}"}

      package_body ->
        cond do
          Regex.match?(~r/\bdescription:/, package_body) ->
            {:ok, "package[:description] already present in #{mix_exs_path}"}

          Regex.match?(~r/def(?:p)?\s+description\s+do/, source) ->
            {:fixable,
             "package/0 in #{mix_exs_path} has no description:, but a description/0 " <>
               "function is already defined in this file -- can wire it in"}

          true ->
            {:unrecognized,
             "package/0 in #{mix_exs_path} has no description: and no description/0 " <>
               "function is defined anywhere in this file to reuse -- refusing to invent text"}
        end
    end
  end

  # Assumes `package_description_predicate/1` has already confirmed
  # `:fixable`: sets `description: description()` in `package/0`'s real
  # keyword-list AST node via `insert_package_key/3` (a structural
  # `Sourceror.Zipper` rewrite) -- never a text splice at the function
  # body's first `[`. Every other entry in `package/0` is preserved
  # untouched.
  defp package_description_transform!(project_dir) do
    mix_exs_path = Path.join(project_dir, "mix.exs")
    source = File.read!(mix_exs_path)

    updated =
      case insert_package_key(source, :description, "description()") do
        {:ok, new_source} ->
          new_source

        :error ->
          raise RuntimeError,
                "package_description: predicate found package/0 fixable in #{mix_exs_path}, " <>
                  "but the structural Sourceror.Zipper rewrite could not locate package/0's " <>
                  "real keyword-list AST node -- refusing to guess"
      end

    File.write!(mix_exs_path, updated)

    {:fixed, "wired description: description() into package/0 in #{mix_exs_path}"}
  end

  # ---------------------------------------------------------------------
  # Rule 6: `mix.exs`'s `package/0` missing `licenses:` -- check 16
  # (`--hex-check`)'s hex-publish-readiness metadata gap.
  # ---------------------------------------------------------------------

  @doc """
  Builds the `Rule` that detects a `package/0` function in `project_dir`'s
  `mix.exs` missing a `licenses:` entry, when a real `LICENSE`/
  `LICENSE.md`/`LICENSE.txt` file exists at the project root whose first
  non-empty line is an EXACT, recognized SPDX license header (today: "MIT
  License" -> `["MIT"]`). Never guesses a license from anything less than
  an exact known header match -- an unrecognized or missing LICENSE file
  text is `{:unrecognized, ...}`, not a guessed default.
  """
  @spec package_licenses_rule() :: Rule.t()
  def package_licenses_rule do
    %Rule{
      name: "package_licenses",
      predicate: &package_licenses_predicate/1,
      transform: &package_licenses_transform!/1,
      verify: fn project_dir -> match?({:ok, _}, package_licenses_predicate(project_dir)) end
    }
  end

  @known_license_headers %{"MIT License" => "MIT"}

  defp package_licenses_predicate(project_dir) do
    mix_exs_path = Path.join(project_dir, "mix.exs")
    source = File.read!(mix_exs_path)

    case locate_fn_body(source, "package") do
      nil ->
        {:unrecognized, "could not locate a package/0 function body in #{mix_exs_path}"}

      package_body ->
        cond do
          Regex.match?(~r/\blicenses:/, package_body) ->
            {:ok, "package[:licenses] already present in #{mix_exs_path}"}

          spdx = detect_known_license(project_dir) ->
            {:fixable,
             "package/0 in #{mix_exs_path} has no licenses:, but the project's LICENSE file " <>
               "is an exact, recognized #{spdx} header -- can wire it in"}

          true ->
            {:unrecognized,
             "package/0 in #{mix_exs_path} has no licenses: and no LICENSE file with an " <>
               "exact, recognized SPDX header was found -- refusing to guess a license"}
        end
    end
  end

  # Assumes `package_licenses_predicate/1` has already confirmed
  # `:fixable`: sets `licenses: [spdx]` in `package/0`'s real keyword-list
  # AST node via `insert_package_key/3` (a structural `Sourceror.Zipper`
  # rewrite) -- never a text splice at the function body's first `[`.
  defp package_licenses_transform!(project_dir) do
    mix_exs_path = Path.join(project_dir, "mix.exs")
    source = File.read!(mix_exs_path)
    spdx = detect_known_license(project_dir)

    updated =
      case insert_package_key(source, :licenses, inspect([spdx])) do
        {:ok, new_source} ->
          new_source

        :error ->
          raise RuntimeError,
                "package_licenses: predicate found package/0 fixable in #{mix_exs_path}, " <>
                  "but the structural Sourceror.Zipper rewrite could not locate package/0's " <>
                  "real keyword-list AST node -- refusing to guess"
      end

    File.write!(mix_exs_path, updated)

    {:fixed, "wired licenses: [#{inspect(spdx)}] into package/0 in #{mix_exs_path}"}
  end

  # Structural helper shared by both `package/0` metadata fixes above:
  # locates `package/0`'s real keyword-list AST node (`def` or `defp`, via
  # `move_to_named_fn/3`) and sets `key` to the parsed AST of
  # `value_source` (a snippet of real Elixir source, e.g. `"description()"`
  # or `inspect([spdx])`) via `Igniter.Code.Keyword.set_keyword_key/4` --
  # never a full-function-body text rewrite. Returns `:error` (never a
  # guess) if `package/0` can't be found or its body isn't a keyword list
  # this rule recognizes.
  defp insert_package_key(source, key, value_source) do
    zipper = source |> Sourceror.parse_string!() |> Sourceror.Zipper.zip()
    value = Sourceror.parse_string!(value_source)

    with {:ok, zipper} <- move_to_named_fn(zipper, :package, 0),
         true <- Igniter.Code.List.list?(zipper),
         {:ok, zipper} <- Igniter.Code.Keyword.set_keyword_key(zipper, key, value, &{:ok, &1}) do
      {:ok, zipper |> Sourceror.Zipper.root() |> Sourceror.to_string()}
    else
      _ -> :error
    end
  end

  # Moves to a `def name/arity` if one exists, else a `defp name/arity` --
  # mirrors the old `locate_fn_body/2` regex's `def(?:p)?` alternation, but
  # structurally.
  defp move_to_named_fn(zipper, name, arity) do
    case Igniter.Code.Function.move_to_def(zipper, name, arity) do
      {:ok, zipper} -> {:ok, zipper}
      :error -> Igniter.Code.Function.move_to_defp(zipper, name, arity)
    end
  end

  defp detect_known_license(project_dir) do
    ~w(LICENSE LICENSE.md LICENSE.txt)
    |> Enum.map(&Path.join(project_dir, &1))
    |> Enum.find_value(fn path ->
      with true <- File.exists?(path),
           {:ok, content} <- File.read(path),
           [first_line | _] <- content |> String.split("\n", trim: true) do
        Map.get(@known_license_headers, String.trim(first_line))
      else
        _ -> nil
      end
    end)
  end

  # Locates a top-level `defp <name> do ... end` / `def <name> do ... end`
  # function body (the raw text between `do` and its matching `end`) in a
  # real mix.exs source string. Shared by the package/0-editing rules
  # above. Returns `nil` if no such function is found.
  defp locate_fn_body(source, fn_name) do
    case Regex.run(~r/def(?:p)?\s+#{fn_name}\s+do\s*\n(.*?)\n[ \t]*end/s, source) do
      nil -> nil
      [_, body] -> body
    end
  end

  # ---------------------------------------------------------------------
  # Shared config/config.exs insertion helper (rules 3 and 4)
  # ---------------------------------------------------------------------

  # Inserts `config_block` into the config file at `config_path`: before the
  # standard phx.new `import_config` marker if present, else appended at the
  # end of the (already-read, if given) `content`, else a fresh minimal file
  # is created. Never touches any content other than adding this block.
  defp write_config_insertion!(config_path, config_block, content \\ nil) do
    content = content || (File.exists?(config_path) && File.read!(config_path))

    updated =
      cond do
        content && String.contains?(content, @import_config_marker) ->
          String.replace(content, @import_config_marker, config_block <> @import_config_marker,
            global: false
          )

        content ->
          String.trim_trailing(content) <> "\n\n" <> config_block

        true ->
          "import Config\n\n" <> config_block
      end

    File.mkdir_p!(Path.dirname(config_path))
    File.write!(config_path, updated)
  end

  defp app_loaded?(app) do
    Application.ensure_loaded(app)
    Application.spec(app, :vsn) != nil
  end

  # ---------------------------------------------------------------------
  # Fix 5: `mix.exs`'s `version:` literal vs. the project's real, observed
  # versioning convention (calendar-ish, mirrored 1:1 from CHANGELOG.md's
  # own top entry header)
  #
  # This predates the rule-engine pass above and is still a plain
  # check_*/fix_*! pair rather than a `Rule` in `default_rules/0` -- folding
  # it into the declarative engine (a new public entry point, a new
  # `default_rules/0` slot, doctor.ex wiring) is a separate, larger change
  # than this pass's scope (migrating `fix_*!`'s *implementation* from
  # text/regex splices to structural `Sourceror.Zipper` rewrites, same
  # external contract). It already fits the same
  # (Predicate, Transformation, Verification) shape and is a natural future
  # `Rule`.
  # ---------------------------------------------------------------------

  @changelog_relpath "CHANGELOG.md"

  @doc """
  Checks whether `project_dir`'s `mix.exs` `version:` literal matches the
  version this project's REAL, observed convention says it should be.

  The real convention, confirmed empirically from this project's own git
  history and `CHANGELOG.md` (not assumed): every release version is a
  calendar-ish `YY.M.D` string (`26.8.27` = 2026-08-27, no leading zeros,
  no `v` prefix in `mix.exs` itself), and `CHANGELOG.md`'s topmost `## vX`
  entry header is the single source of truth for "what the current release
  version is" -- `mix.exs`'s `version:` is a manually-reconciled projection
  of that header today, not the other way around, and there is no separate
  authority (no `git tag` exists in this repo's history at all -- confirmed
  via `git tag --list` returning empty -- so CHANGELOG.md's own top heading
  is the only real, standing record of "the current version").

  This derivation is unambiguous (a single topmost `## vX` heading, matched
  verbatim against `mix.exs`'s `version:` string) precisely because
  CHANGELOG.md always has exactly one topmost heading. This convention is
  specific to `ggen_igniter`'s own release process, not a universal
  requirement of every consuming project, so a project with no
  `CHANGELOG.md` at all (the common case: `ggen_igniter.doctor` also runs
  inside arbitrary CONSUMER apps that never opted into this convention) is
  `{:ok, message}` -- not applicable, not a problem. It only becomes
  `{:unrecognized, message}` when `CHANGELOG.md` DOES exist but its shape
  defeats the derivation (no `## v` heading found, or `mix.exs`'s
  `version:` isn't a simple string literal) -- a real, ambiguous state this
  module refuses to guess a fallback rule for.
  """
  @spec check_version_policy(Path.t()) ::
          {:ok, String.t()} | {:fixable, String.t()} | {:unrecognized, String.t()}
  def check_version_policy(project_dir) do
    mix_exs_path = Path.join(project_dir, "mix.exs")
    changelog_path = Path.join(project_dir, @changelog_relpath)

    if File.exists?(changelog_path) do
      with {:ok, mix_version} <- read_mix_exs_version(mix_exs_path),
           {:ok, changelog_version} <- read_changelog_top_version(changelog_path) do
        if mix_version == changelog_version do
          {:ok,
           "mix.exs version #{inspect(mix_version)} matches CHANGELOG.md's top entry " <>
             "(## v#{changelog_version}) -- MATCH"}
        else
          {:fixable,
           "MISMATCH: mix.exs version is #{inspect(mix_version)} but CHANGELOG.md's top " <>
             "entry (## v#{changelog_version}) says it should be #{inspect(changelog_version)}"}
        end
      else
        {:error, reason} -> {:unrecognized, reason}
      end
    else
      {:ok,
       "no #{@changelog_relpath} found at #{changelog_path} -- ggen_igniter's " <>
         "CHANGELOG.md-derived version policy convention is not applicable here"}
    end
  end

  @doc """
  Applies the fix `check_version_policy/1` detects: rewrites `project_dir`'s
  `mix.exs` `version:` literal to match CHANGELOG.md's topmost `## vX`
  entry header, via a structural `Sourceror.Zipper` rewrite of `project/0`'s
  real keyword-list AST node (see `rewrite_version_literal/2`) -- never a
  full-file text/regex rewrite.

  Raises a `RuntimeError` instead of guessing if the real shape isn't one
  `check_version_policy/1` recognizes (no CHANGELOG.md, no `## v` heading,
  or `mix.exs`'s `version:` isn't a simple string literal).
  """
  @spec fix_version_policy!(Path.t()) :: {:ok, String.t()} | {:fixed, String.t()}
  def fix_version_policy!(project_dir) do
    case check_version_policy(project_dir) do
      {:ok, msg} ->
        {:ok, msg}

      {:unrecognized, msg} ->
        raise RuntimeError, msg

      {:fixable, _msg} ->
        mix_exs_path = Path.join(project_dir, "mix.exs")
        changelog_path = Path.join(project_dir, @changelog_relpath)

        source = File.read!(mix_exs_path)
        {:ok, mix_version} = read_mix_exs_version(mix_exs_path)
        {:ok, changelog_version} = read_changelog_top_version(changelog_path)

        updated =
          case rewrite_version_literal(source, changelog_version) do
            {:ok, new_source} ->
              new_source

            :error ->
              raise RuntimeError,
                    "check_version_policy/1 found a fixable version: mismatch in " <>
                      "#{mix_exs_path}, but the structural Sourceror.Zipper rewrite could not " <>
                      "locate project/0's version: key -- refusing to guess"
          end

        File.write!(mix_exs_path, updated)

        {:fixed,
         "corrected mix.exs version: #{inspect(mix_version)} -> #{inspect(changelog_version)} " <>
           "(per CHANGELOG.md's top entry ## v#{changelog_version})"}
    end
  end

  # Structural counterpart of the old whole-file `version: "OLD"` ->
  # `version: "NEW"` text replacement: parses `source`, walks to
  # `project/0`'s real keyword list (`def` or `defp`, via
  # `move_to_named_fn/3`), and replaces the `version:` key's string-literal
  # value in place via `Igniter.Code.Keyword.set_keyword_key/4` -- scoped
  # to `project/0` specifically (unlike the old whole-source regex), so a
  # `version:` string appearing anywhere else in the file (a doc comment, a
  # different function) can never be mistaken for the real one. Returns
  # `:error` (never a guess) if `project/0` or its `version:` key can't be
  # located structurally.
  defp rewrite_version_literal(source, new_version) do
    zipper = source |> Sourceror.parse_string!() |> Sourceror.Zipper.zip()
    value = Sourceror.parse_string!(inspect(new_version))

    with {:ok, zipper} <- move_to_named_fn(zipper, :project, 0),
         true <- Igniter.Code.List.list?(zipper),
         {:ok, zipper} <-
           Igniter.Code.Keyword.set_keyword_key(zipper, :version, value, fn existing ->
             {:ok, Igniter.Code.Common.replace_code(existing, value)}
           end) do
      {:ok, zipper |> Sourceror.Zipper.root() |> Sourceror.to_string()}
    else
      _ -> :error
    end
  end

  defp read_mix_exs_version(mix_exs_path) do
    case File.read(mix_exs_path) do
      {:error, _} ->
        {:error, "#{mix_exs_path} not found"}

      {:ok, source} ->
        case Regex.run(~r/version:\s*"([^"]+)"/, source) do
          [_, version] -> {:ok, version}
          nil -> {:error, "could not find a simple `version: \"...\"` literal in #{mix_exs_path}"}
        end
    end
  end

  defp read_changelog_top_version(changelog_path) do
    case File.read(changelog_path) do
      {:error, _} ->
        {:error, "#{changelog_path} not found -- cannot derive the expected version"}

      {:ok, content} ->
        case Regex.run(~r/^##\s+v(\S+)/m, content) do
          [_, version] ->
            {:ok, version}

          nil ->
            {:error,
             "no top-level `## vX` entry heading found in #{changelog_path} -- cannot derive the expected version"}
        end
    end
  end
end
