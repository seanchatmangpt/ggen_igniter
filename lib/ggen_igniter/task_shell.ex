defmodule GgenIgniter.TaskShell do
  @moduledoc """
  The one place the `Igniter.Mix.Task` help-flag quirk is fixed, so each CLI task's
  `run/1` override is a one-line delegation instead of a copied conditional.

  `Igniter.Mix.Task`'s generated `run/1` does not provide symmetric task-owned
  handling for both conventional help spellings. This boundary intercepts both
  `--help` and `-h` before the base task can emit wrapper output, keeping the
  task's concise help path byte-for-byte consistent across spellings.

    * `run_with_help/3` -- runs `help_fun` (which must end in `System.halt/1`) when
      any of `help_flags` is in `argv`, else calls `continue_fun` (the task's
      `super(argv)`).
    * `help_requested?/2` -- the pure predicate behind it.

  Default `help_flags` is `["--help", "-h"]`; callers may pass a narrower explicit
  set only when a task intentionally assigns different semantics to a spelling.
  """

  @default_help_flags ["--help", "-h"]

  @doc "True when any of `help_flags` appears verbatim in `argv`."
  @spec help_requested?([String.t()], [String.t()]) :: boolean()
  def help_requested?(argv, help_flags \\ @default_help_flags) when is_list(argv) do
    Enum.any?(help_flags, &(&1 in argv))
  end

  @doc """
  Calls `help_fun` when help was requested, otherwise `continue_fun`. Both are
  zero-arity so the caller keeps `super/1` (only callable from inside the
  overriding `run/1`) on its own side.
  """
  @spec run_with_help([String.t()], (-> any()), (-> any()), [String.t()]) :: any()
  def run_with_help(argv, help_fun, continue_fun, help_flags \\ @default_help_flags)
      when is_function(help_fun, 0) and is_function(continue_fun, 0) do
    if help_requested?(argv, help_flags), do: help_fun.(), else: continue_fun.()
  end
end
