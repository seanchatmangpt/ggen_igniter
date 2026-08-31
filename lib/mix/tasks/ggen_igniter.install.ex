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
