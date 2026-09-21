defmodule Mix.Tasks.GgenIgniter.Rename do
  @moduledoc """
  Renames a function across the project via
  `GgenIgniter.Refactors.SafeRename.rename_function/4` -- the safe,
  defect-routed wrapper around `Igniter.Refactors.Rename.rename_function/4`.

  `GgenIgniter.Refactors.SafeRename` (`lib/ggen_igniter/refactors/safe_rename.ex`) is a
  real, already-tested Sourceror-based codemod primitive with the same signature and
  return type as `Igniter.Refactors.Rename.rename_function/4`, but it routes around two
  confirmed upstream defects (`deps/igniter` v0.8.3, `rename.ex:168-169`/`:325-326`)
  documented in that module's own `@moduledoc`:

    1. A guarded def (`def foo(x) when x > 0 do`) is silently left un-renamed by
       upstream while its call sites ARE renamed, producing a broken program.
    2. A parenless zero-arity def (`def foo do ... end`) crashes upstream's
       `rename_function/4` outright with `length(nil)`.

  Before this task, `SafeRename.rename_function/4` had no CLI surface -- every real
  caller had to invoke it from Elixir directly. This task is the thin, additive wiring:
  parse `--from`/`--to`, call the real `SafeRename.rename_function/4`, and let
  `Igniter.Mix.Task`'s own diff/prompt/`--dry-run`/`--yes` machinery handle the rest.

  ## Options

    * `--from MODULE.function[/arity]` (required) -- the existing module and function,
      e.g. `--from MyApp.Sample.foo` or `--from MyApp.Sample.foo/1` to scope the rename
      to one arity.
    * `--to MODULE.function[/arity]` (required) -- the new module and function. If the
      new module differs from `--from`'s module, the function (and, for the unguarded
      case, its upstream-renamed body) moves there -- same semantics as
      `Igniter.Refactors.Rename.rename_function/4`. An arity given here must match
      `--from`'s arity (or be omitted).
    * `--arity N` -- overrides any arity parsed from `--from`/`--to`; omit to rename
      every arity (`Igniter.Refactors.Rename.rename_function/4`'s own `:any` default).
    * `--deprecate soft|hard` -- leave the old function in place, deprecated, instead of
      removing it (same two upstream deprecation levels; `soft` only affects docs,
      `hard` emits a runtime warning when the old name is still called).
    * `--path DIR` (default: none) -- pre-warms Igniter's source index with every
      `.ex`/`.exs` file under `DIR` before searching for `--from`'s module, for a
      project layout where the module does not live under the configured
      `:source_folders` (default `lib`, `test/support`) or under `test/` (both of which
      `Igniter.Project.Module.find_module/2` already searches without this flag).

  ## Examples

  ```bash
  mix ggen_igniter.rename --from MyApp.Sample.foo --to MyApp.Sample.bar
  mix ggen_igniter.rename --from MyApp.Old.run/2 --to MyApp.New.run --path lib/my_app
  mix ggen_igniter.rename --from MyApp.Sample.foo --to MyApp.Sample.bar --deprecate soft
  ```

  ## Exit codes

    * `0` -- rename applied (or, under `--dry-run`, the diff was printed and nothing
      written).
    * `1` -- invalid `--from`/`--to` format, a mismatched arity between `--from` and
      `--to`, or an invalid `--deprecate` value.
  """

  use Igniter.Mix.Task

  @example "mix ggen_igniter.rename --from OldMod.old_fun --to NewMod.new_fun"

  @impl Igniter.Mix.Task
  def info(_argv, _composing_task) do
    %Igniter.Mix.Task.Info{
      group: :ggen_igniter,
      example: @example,
      positional: [],
      schema: [
        from: :string,
        to: :string,
        arity: :integer,
        deprecate: :string,
        path: :string,
        help: :boolean
      ],
      aliases: [h: :help],
      required: [:from, :to]
    }
  end

  # `Igniter.Mix.Task`'s generated `run/1` only ever matches the literal
  # string "--help" (never the `-h` alias, even though `-h` is aliased to
  # `:help` in info/2's schema above) before dispatching to Mix's generic
  # `mix help ggen_igniter.rename` renderer (the full raw @moduledoc) instead
  # of this task's own concise help text -- the exact AR-11 quirk
  # `lib/mix/tasks/CLAUDE.md` documents and requires every new
  # `Igniter.Mix.Task` to fix the same way `sync.ex`/`doctor.ex`/`plan.ex` do.
  @impl Mix.Task
  def run(argv) do
    if "--help" in argv or "-h" in argv do
      print_help_and_halt()
    else
      super(argv)
    end
  end

  @impl Igniter.Mix.Task
  def igniter(igniter) do
    options = igniter.args.options

    {old_module, old_function, from_arity} = parse_target!(options[:from], "--from")
    {new_module, new_function, to_arity} = parse_target!(options[:to], "--to")

    arity = resolve_arity!(options[:arity], from_arity, to_arity)
    deprecate = parse_deprecate!(options[:deprecate])

    igniter =
      case options[:path] do
        nil -> igniter
        "" -> igniter
        path -> Igniter.include_glob(igniter, Path.join(path, "**/*.{ex,exs}"))
      end

    GgenIgniter.Refactors.SafeRename.rename_function(
      igniter,
      {old_module, old_function},
      {new_module, new_function},
      arity: arity,
      deprecate: deprecate
    )
  end

  # ===========================================================================
  # --from / --to parsing (module.function[/arity] -> {module, atom, arity | :any})
  # ===========================================================================

  defp parse_target!(nil, flag) do
    Mix.shell().error("ggen_igniter.rename: #{flag} is required")
    exit({:shutdown, 1})
  end

  defp parse_target!(input, flag) do
    with parts <- String.split(input, ".", trim: true),
         [_ | _] <- parts,
         fun <- List.last(parts),
         mod_parts <- :lists.droplast(parts),
         true <- mod_parts != [],
         {fun_name, arity} <- fun_to_arity(fun),
         fun_atom <- String.to_atom(fun_name),
         # Plain stdlib `Module.concat/1` over the raw string segments (it
         # prepends the `Elixir.` alias namespace itself), not
         # `Igniter.Project.Module.parse/1` -- `lib/mix/tasks/CLAUDE.md`
         # reserves this task layer for CLI plumbing only and keeps Igniter's
         # AST-mutation API (`Igniter.Project.Module`/`Igniter.Code`/
         # `Sourceror.Zipper`) out of it; the real AST work stays delegated to
         # `GgenIgniter.Refactors.SafeRename`, the library module this task
         # wires up.
         module <- Module.concat(mod_parts) do
      {module, fun_atom, arity}
    else
      _ ->
        Mix.shell().error(
          "ggen_igniter.rename: invalid #{flag} #{inspect(input)} -- expected MODULE.function or MODULE.function/arity"
        )

        exit({:shutdown, 1})
    end
  end

  defp fun_to_arity(fun) do
    case String.split(fun, "/", parts: 2, trim: true) do
      [fun] ->
        {fun, :any}

      [fun, arity_str] ->
        case Integer.parse(arity_str) do
          {arity, ""} -> {fun, arity}
          _ -> :error
        end

      _ ->
        :error
    end
  end

  defp resolve_arity!(explicit_arity, from_arity, to_arity) do
    cond do
      is_integer(explicit_arity) ->
        explicit_arity

      is_integer(from_arity) and to_arity == :any ->
        from_arity

      from_arity != to_arity ->
        Mix.shell().error(
          "ggen_igniter.rename: arity must match between --from and --to " <>
            "(or be omitted on --to), got #{inspect(from_arity)} vs #{inspect(to_arity)}"
        )

        exit({:shutdown, 1})

      true ->
        from_arity
    end
  end

  defp parse_deprecate!(nil), do: nil

  defp parse_deprecate!("soft"), do: :soft
  defp parse_deprecate!("hard"), do: :hard

  defp parse_deprecate!(other) do
    Mix.shell().error(
      "ggen_igniter.rename: invalid --deprecate #{inspect(other)} -- expected soft or hard"
    )

    exit({:shutdown, 1})
  end

  defp print_help_and_halt do
    IO.puts("""
    mix ggen_igniter.rename -- renames a function via the real, tested
    GgenIgniter.Refactors.SafeRename.rename_function/4 (routes around two
    confirmed Igniter.Refactors.Rename.rename_function/4 defects: a silently
    un-renamed guarded def, and a length(nil) crash on a parenless zero-arity
    def)

    USAGE
        #{@example}

    OPTIONS
        --from MODULE.function[/arity]   (required) existing module + function
        --to MODULE.function[/arity]     (required) new module + function
        --arity N                        override the arity parsed above
        --deprecate soft|hard            keep the old function, deprecated
        --path DIR                       pre-warm the source index with DIR
        --dry-run                        print the diff, write nothing
        --yes                            apply without the confirmation prompt
        --help, -h                       print this help and exit 0

    EXAMPLES
        mix ggen_igniter.rename --from MyApp.Sample.foo --to MyApp.Sample.bar
        mix ggen_igniter.rename --from MyApp.Old.run/2 --to MyApp.New.run
        mix ggen_igniter.rename --from MyApp.Sample.foo --to MyApp.Sample.bar --deprecate soft

    EXIT CODES
        0  applied (or, under --dry-run, diff printed and nothing written)
        1  invalid --from/--to/--deprecate, or a --from/--to arity mismatch
    """)

    System.halt(0)
  end
end
