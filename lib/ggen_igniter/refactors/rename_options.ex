defmodule GgenIgniter.Refactors.RenameOptions do
  @moduledoc """
  Option plumbing for `mix ggen_igniter.rename`: parses `--from`/`--to`
  (`MODULE.function[/arity]`), resolves the arity, validates `--deprecate`, applies
  the `--path` source-index pre-warm and calls
  `GgenIgniter.Refactors.SafeRename.rename_function/4`.

  This is the arity-2 delegate (`rename(igniter, options)`) of the manufactured task
  shell `Mix.Tasks.GgenIgniter.Rename` (`priv/ggen/igniter-task-pack`); the task file
  carries only the ontology-derived shell, this module carries the hand-written body.
  Invalid input prints `ggen_igniter.rename: ...` on the Mix shell and exits
  `{:shutdown, 1}`.
  """

  @doc "Runs the rename described by parsed task `options` against `igniter`."
  @spec rename(Igniter.t(), keyword()) :: Igniter.t()
  def rename(igniter, options) do
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
end
