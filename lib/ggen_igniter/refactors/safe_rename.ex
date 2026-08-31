defmodule GgenIgniter.Refactors.SafeRename do
  @moduledoc """
  A local, non-vendored-dependency-patching route around two real, confirmed
  defects in `Igniter.Refactors.Rename.rename_function/4` (`deps/igniter`,
  v0.8.3, `lib/igniter/refactors/rename.ex`) -- reproduced and cited exactly
  in `test/ggen_igniter_upstream_rename_blocker_test.exs`:

  1. **Guard-clause blind spot.** `rename.ex:168-169` and `:325-326` both
     match a def head as bare `{old_function, meta, args}`. A guarded def
     (`def foo(x) when is_binary(x) do`) has head AST
     `{:when, meta, [{:foo, meta2, args}, guard]}`, which does not match --
     the predicate falls through to `false`, so the def is silently left
     un-renamed while call sites elsewhere in the project ARE renamed,
     producing a broken program with no warning.

  2. **`length(nil)` crash.** The same two sites call `length(args)` directly
     on the extracted `args`. A parenless zero-arity def (`def foo do ... end`)
     has `args = nil` (not `[]`) in its AST -- `length(nil)` raises
     `ArgumentError`, crashing `rename_function/4` outright.

  `deps/igniter` is a vendored hex dependency: editing it in place would be
  silently reverted by the next `mix deps.get`, so per this repo's
  `local-dfcm-manufacturing-engine` discipline (never fake away real content,
  and prefer routing around a defect over patching a dependency this repo
  doesn't own) this module works around both defects from the OUTSIDE,
  reusing `Igniter.Refactors.Rename`'s own tested logic for the safe common
  case rather than reimplementing it:

  - **Defect 2 (crash) is neutralized by pre-normalization**: before
    delegating to the real `rename_function/4`, any parenless zero-arity def
    matching `old_function`/`old_module` is rewritten to have explicit `()`
    -- a semantics-null change (`def foo do` and `def foo() do` are
    identical Elixir) that turns `args` from `nil` into `[]`, so upstream's
    `length/1` call no longer crashes and its def-head match succeeds.
  - **Defect 1 (silent skip) is neutralized by a post-pass**: after
    delegating to the real `rename_function/4` (which correctly renames
    every unguarded def and every call site, since call-site renaming
    doesn't go through the buggy def-head matcher), this module searches
    `old_module` (guarded defs are never found by upstream's own
    cross-module "bodies to migrate" scan either, per the same matcher --
    they always stay behind in `old_module`, never migrated) for any
    remaining def whose head still carries the OLD function name under a
    `{:when, ...}` guard wrapper, and renames just that atom in place -- a
    small, targeted zipper edit scoped to exactly the shape upstream misses.

  ## Known limitations (disclosed, not silently narrowed)

  - Only handles a bare/guarded `def`, not `defp`/`defmacro`/`defmacrop` --
    matches the scope `Igniter.Refactors.Rename.rename_function/4` itself
    documents.
  - **Cross-module rename does not migrate a guarded def.** When
    `old_module != new_module`, upstream migrates matching bodies into
    `new_module`; since guarded defs never match its scan, this module's
    post-pass only renames the guarded def's name IN PLACE inside
    `old_module` -- it does not also move it to `new_module`. A guarded def
    being renamed across modules needs manual follow-up; this is disclosed
    here rather than silently narrowed.
  - The post-pass renames the guarded def's OWN name; it does not attempt to
    rename call sites *inside* the guard expression itself (a guard
    referencing the renamed function recursively is out of scope, and
    genuinely rare).
  - Multiple guard clauses for the same function/arity (`def foo(x) when
    guard1; def foo(x) when guard2`) are each independently matched and
    renamed by the post-pass (`Igniter.Code.Common.update_all_matches/3`
    revisits every match, not just the first).
  """

  alias Sourceror.Zipper

  @doc """
  Safe wrapper around `Igniter.Refactors.Rename.rename_function/4` -- same
  signature and return type, routing around the two upstream defects
  documented in this module's moduledoc without editing `deps/igniter`.
  """
  @spec rename_function(
          Igniter.t(),
          old :: {module(), atom()},
          new :: {module(), atom()},
          opts :: Keyword.t()
        ) :: Igniter.t()
  def rename_function(igniter, old, new, opts \\ [])

  def rename_function(igniter, {old_module, old_function}, {new_module, new_function}, opts) do
    igniter
    |> normalize_parenless_defs(old_module, old_function)
    |> Igniter.Refactors.Rename.rename_function(
      {old_module, old_function},
      {new_module, new_function},
      opts
    )
    |> rename_remaining_guarded_defs(old_module, old_function, new_function)
  end

  # Defect 2 workaround: `def old_function do ... end` (args: nil) ->
  # `def old_function() do ... end` (args: []) -- a semantics-null rewrite
  # that prevents upstream's `length(args)` crash and lets its def-head
  # matcher succeed.
  defp normalize_parenless_defs(igniter, module, function_name) do
    case Igniter.Project.Module.find_module(igniter, module) do
      {:ok, {igniter, source, zipper}} ->
        {:ok, zipper} =
          Igniter.Code.Common.update_all_matches(
            zipper,
            fn z ->
              match?(%Zipper{node: {:def, _, [{^function_name, _, nil}, _body]}}, z)
            end,
            fn z ->
              {:def, def_meta, [{^function_name, fn_meta, nil}, body]} = z.node
              {:ok, Zipper.replace(z, {:def, def_meta, [{function_name, fn_meta, []}, body]})}
            end
          )

        write_source(igniter, source, zipper)

      :error ->
        igniter
    end
  end

  # Defect 1 workaround: rename any def head still carrying `old_function`
  # under a `{:when, ...}` guard wrapper, which upstream's def-head matcher
  # never touches. Only the OLD name would still be present after upstream's
  # own pass -- unguarded defs and call sites are already correctly renamed.
  defp rename_remaining_guarded_defs(igniter, module, old_function, new_function) do
    case Igniter.Project.Module.find_module(igniter, module) do
      {:ok, {igniter, source, zipper}} ->
        {:ok, zipper} =
          Igniter.Code.Common.update_all_matches(
            zipper,
            fn z ->
              match?(
                %Zipper{node: {:when, _, [{^old_function, _, _args}, _guard]}},
                z
              )
            end,
            fn z ->
              {:when, when_meta, [{^old_function, fn_meta, args}, guard]} = z.node

              {:ok,
               Zipper.replace(
                 z,
                 {:when, when_meta, [{new_function, fn_meta, args}, guard]}
               )}
            end
          )

        write_source(igniter, source, zipper)

      :error ->
        igniter
    end
  end

  defp write_source(igniter, source, zipper) do
    new_source = Igniter.update_source(source, igniter, :quoted, Zipper.topmost_root(zipper))
    %{igniter | rewrite: Rewrite.update!(igniter.rewrite, new_source)}
  end
end
