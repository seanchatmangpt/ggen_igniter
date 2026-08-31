defmodule Mix.Tasks.GgenIgniter.Install do
  @moduledoc """
  Installer task: `mix ggen_igniter.install [--domain Module.Name] [--otp-app name] [--yes]`.

  Adds an `:ash` dependency (`~> 3.0`), registers `--domain` (default
  `<OtpApp>.Ash.Domain`) under `config :otp_app, ash_domains: [...]`, and adds the domain
  module as a new child in the consumer's `Application` supervision tree, via real
  `Igniter.Project.Deps`/`Igniter.Project.Config`/`Igniter.Project.Application` codemods
  against the CONSUMER project's own `mix.exs`/`config/config.exs`/`application.ex`.

  Unlike `mix ggen_igniter.sync`/`mix ggen_igniter.doctor` (see `lib/mix/tasks/CLAUDE.md`
  -- CLI-plumbing only, no AST mutation), this task legitimately builds real AST mutations
  against the consumer's own project files: that is exactly what an installer task is for.

  ## Known `Igniter.Project.Deps.add_dep/2,3` defect: inline `deps: [...]` in `project/0`

  `Igniter.Project.Deps.get_dep/2` (called internally by `add_dep/2,3` before it decides
  whether to add-vs-replace a dependency) builds a zipper over the consumer's `mix.exs`,
  then does:

      with {:ok, zipper} <- Igniter.Code.Module.move_to_module_using(zipper, Mix.Project),
           {:ok, zipper} <- Igniter.Code.Function.move_to_defp(zipper, :deps, 0) do
        ...
      else
        _ -> nil
      end

  When the consumer's `mix.exs` declares `deps: [...]` INLINE inside `project/0` rather
  than via a separate `defp deps do ... end`, `move_to_defp(zipper, :deps, 0)` returns
  `:error`, so `get_dep/2` returns bare `nil` (not `{:ok, nil}`/`{:error, _}`) -- a shape
  `Igniter.Project.Deps.add_dependency/4`'s `case get_dep(igniter, name) do ... end` has no
  clause for, raising `CaseClauseError` and crashing the whole `mix ggen_igniter.install`
  run before any patch is ever produced. Confirmed by reading `deps/igniter/lib/igniter/
  project/deps.ex` directly (`get_dep/2`'s `else _ -> nil` fallback vs. `add_dependency/4`'s
  three-clause `case`), not just observed as a crash.

  This task avoids the crash with a defensive pre-check, not an auto-codemod that rewrites
  inline `deps: [...]` into `defp deps do ... end`: before calling `add_dep/2`, it runs the
  EXACT SAME `move_to_module_using/2` + `move_to_defp(zipper, :deps, 0)` probe against a
  zipper built from the consumer's own `mix.exs` source. `{:ok, _}` means `add_dep/2` is
  safe to call normally; `:error` means it would crash, so this task instead calls
  `Igniter.add_issue/2` with the exact remediation (refactor `mix.exs` to `defp deps do
  [...] end`, referenced from `project/0` as `deps: deps()`) and skips `add_dep/2` entirely
  -- a real, fail-closed halt before any write, not a silent partial patch. An
  auto-codemod that hoists an inline keyword-list pair into a new `defp` and rewrites
  `project/0`'s call site is out of scope here: that is itself a nontrivial, separately-
  scoped AST rewrite with real risk of misapplying a patch to the consumer's actual
  `mix.exs`, and this repo's `local-dfcm-manufacturing-engine` discipline treats "never
  fake away a side of a merge" the same way for any nontrivial speculative rewrite.

  ## `children = [...]` auto-insert (fixes `Igniter.Project.Application.add_new_child/2,3`'s
  known insertion-point gap, without patching `deps/igniter`)

  `Igniter.Project.Application.add_new_child/2,3` requires the target `start/2` callback to
  already assign its child list to a `children = [...]` variable before passing it to
  `Supervisor.start_link/2` (confirmed by reading `deps/igniter/lib/igniter/project/
  application.ex`'s own moduledoc example). Against a real `start/2` that inlines the child
  list directly -- `Supervisor.start_link([], opts)`, with no `children =` binding -- the
  codemod cannot locate an insertion point and degrades to a real, honest warning, leaving
  the file untouched (see `test/ggen_igniter_base_project_config_application_test.exs`).

  Unlike the `deps:` defect above, this gap has a safe, semantics-preserving local fix that
  does not require touching `deps/igniter`: `ensure_children_binding/1` runs BEFORE
  `add_new_child/3` and, only when the app module's `start/2` calls `Supervisor.start_link/2`
  (or `Supervisor.start_link/3`) with a bare list literal as its first argument (never a
  variable -- that means a `children = [...]` binding may already exist elsewhere), rewrites

      Supervisor.start_link([...], opts)

  to

      children = [...]
      Supervisor.start_link(children, opts)

  -- a real, targeted `Igniter.Code.Function`/`Sourceror.Zipper` rewrite, purely additive to
  `start/2`'s body (inserts one statement, replaces the call's first argument with a
  variable reference to it), leaving supervision semantics identical. When no app module
  exists yet, or `start/2` isn't found, or the first argument is already a variable (not a
  bare list), this is a no-op and `add_new_child/3` proceeds (or degrades) exactly as before.
  """

  use Igniter.Mix.Task

  @impl Igniter.Mix.Task
  def info(_argv, _composing_task) do
    %Igniter.Mix.Task.Info{
      group: :ggen_igniter,
      schema: [domain: :string, otp_app: :string, yes: :boolean],
      aliases: [y: :yes]
    }
  end

  @impl Mix.Task
  def run(argv) do
    if "--help" in argv do
      print_help_and_halt()
    else
      super(argv)
    end
  end

  @impl Igniter.Mix.Task
  def igniter(igniter) do
    otp_app =
      igniter.args.options[:otp_app] ||
        Igniter.Project.Application.app_name(igniter) |> to_string()

    domain_module =
      case igniter.args.options[:domain] do
        nil ->
          Igniter.Project.Module.module_name(igniter, "Ash.Domain")

        domain_string ->
          Igniter.Project.Module.parse(domain_string)
      end

    case deps_probe(igniter) do
      :ok ->
        igniter
        |> Igniter.Project.Deps.add_dep({:ash, "~> 3.0"})
        |> Igniter.Project.Config.configure_new(
          "config.exs",
          String.to_atom(otp_app),
          [:ash_domains],
          [domain_module]
        )
        |> ensure_children_binding()
        |> Igniter.Project.Application.add_new_child(domain_module, opts_for_child: [])

      :error ->
        Igniter.add_issue(igniter, """
        mix.exs declares deps inline inside project/0 rather than via `defp deps do ... end`.

        Igniter.Project.Deps.add_dep/2,3 requires the `defp deps do ... end` shape and
        crashes (CaseClauseError) against inline `deps: [...]`.

        Please refactor mix.exs to:

            defp deps do
              [...]
            end

        referenced from project/0 as `deps: deps()`, and re-run `mix ggen_igniter.install`.
        """)
    end
  end

  # Routes around `Igniter.Project.Application.add_new_child/2,3`'s known
  # insertion-point gap (see moduledoc) without touching `deps/igniter`: when the app
  # module's `start/2` calls `Supervisor.start_link/2,3` with a bare list literal as
  # its first argument (never a variable -- that would mean a `children = [...]`
  # binding may already exist), rewrites it to introduce that binding first. A no-op
  # (returns `igniter` unchanged) whenever there's no app module, no `start/2`, no
  # matching `Supervisor.start_link` call, or the first argument isn't a bare list.
  defp ensure_children_binding(igniter) do
    case Igniter.Project.Application.app_module(igniter) do
      nil ->
        igniter

      app_module_result ->
        module = elem_or_self(app_module_result)
        do_ensure_children_binding(igniter, module)
    end
  end

  defp elem_or_self({mod, _}), do: mod
  defp elem_or_self(mod), do: mod

  defp do_ensure_children_binding(igniter, module) do
    case Igniter.Project.Module.find_module(igniter, module) do
      {:ok, {igniter, source, zipper}} ->
        case rewrite_children_binding(zipper) do
          {:ok, zipper} ->
            new_source =
              Igniter.update_source(source, igniter, :quoted, Sourceror.Zipper.topmost_root(zipper))

            %{igniter | rewrite: Rewrite.update!(igniter.rewrite, new_source)}

          :no_change ->
            igniter
        end

      :error ->
        igniter
    end
  end

  defp rewrite_children_binding(zipper) do
    with {:ok, zipper} <- Igniter.Code.Function.move_to_def(zipper, :start, 2),
         {:ok, call_zipper} <-
           Igniter.Code.Function.move_to_function_call(zipper, {Supervisor, :start_link}, [2, 3]),
         {form, meta, [first_arg | rest_args]} <- call_zipper.node,
         true <- list_literal?(first_arg) do
      updated_call_zipper =
        Sourceror.Zipper.replace(
          call_zipper,
          {form, meta, [{:children, [], nil} | rest_args]}
        )

      {:ok,
       Igniter.Code.Common.add_code(
         updated_call_zipper,
         {:=, [], [{:children, [], nil}, first_arg]},
         placement: :before
       )}
    else
      _ -> :no_change
    end
  end

  # Sourceror's `literal_encoder` block-wraps a bare `[]` (an atomic literal token)
  # as `{:__block__, meta, [[]]}`, but leaves a non-empty list (`[a, b]`, built from
  # cons cells rather than a single literal token) as a raw Elixir list AST directly
  # -- both are real "a bare list literal was passed as the first argument" shapes
  # this rewrite must recognize.
  defp list_literal?({:__block__, _, [list]}) when is_list(list), do: true
  defp list_literal?(list) when is_list(list), do: true
  defp list_literal?(_), do: false

  # Mirrors the exact probe `Igniter.Project.Deps.get_dep/2` runs internally before
  # `add_dep/2,3` would otherwise crash on an inline `deps: [...]` mix.exs shape (see
  # moduledoc). Returns `:ok` when `add_dep/2` is safe to call, `:error` when it would
  # raise `CaseClauseError`.
  defp deps_probe(igniter) do
    zipper =
      igniter
      |> Igniter.include_existing_file("mix.exs")
      |> Map.get(:rewrite)
      |> Rewrite.source!("mix.exs")
      |> Rewrite.Source.get(:quoted)
      |> Sourceror.Zipper.zip()

    with {:ok, zipper} <- Igniter.Code.Module.move_to_module_using(zipper, Mix.Project),
         {:ok, _zipper} <- Igniter.Code.Function.move_to_defp(zipper, :deps, 0) do
      :ok
    else
      _ -> :error
    end
  end

  defp print_help_and_halt do
    Mix.shell().info("""
    mix ggen_igniter.install [--domain Module.Name] [--otp-app name] [--yes]

    Adds an :ash dependency, registers the domain module under
    `config :otp_app, ash_domains: [...]`, and adds it as a supervised child.

      --domain    domain module name (default: <OtpApp>.Ash.Domain)
      --otp-app   OTP app name (default: derived from mix.exs)
      --yes, -y   answer yes to any prompts
    """)

    System.halt(0)
  end
end
