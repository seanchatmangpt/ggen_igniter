defmodule GgenIgniter.TaskShell do
  @moduledoc """
  The one place the `Igniter.Mix.Task` `--help` quirk is fixed, so each CLI task's
  `run/1` override is a one-line delegation instead of a copied `if`.

  `Igniter.Mix.Task`'s generated `run/1` intercepts only the literal `"--help"` argv
  entry (`deps/igniter/lib/mix/task.ex`, `help_requested?/1`) and renders Mix's raw
  `@moduledoc` dump, never the task's own concise help; `-h` is never intercepted.
  See `lib/mix/tasks/CLAUDE.md` "Known `Igniter.Mix.Task` base-class quirks".

    * `run_with_help/3` -- runs `help_fun` (which must end in `System.halt/1`) when
      any of `help_flags` is in `argv`, else calls `continue_fun` (the task's
      `super(argv)`).
    * `help_requested?/2` -- the pure predicate behind it.

  Default `help_flags` is `["--help"]` (the sync/plan/install/fortune5_ready
  behavior, where bare `-h` reaches `igniter/1` and is handled via `opts[:help]`);
  pass `["--help", "-h"]` for tasks that own both spellings (`rename`).
  """

  @doc "True when any of `help_flags` appears verbatim in `argv`."
  @spec help_requested?([String.t()], [String.t()]) :: boolean()
  def help_requested?(argv, help_flags \\ ["--help"]) when is_list(argv) do
    Enum.any?(help_flags, &(&1 in argv))
  end

  @doc """
  Calls `help_fun` when help was requested, otherwise `continue_fun`. Both are
  zero-arity so the caller keeps `super/1` (only callable from inside the
  overriding `run/1`) on its own side.
  """
  @spec run_with_help([String.t()], (-> any()), (-> any()), [String.t()]) :: any()
  def run_with_help(argv, help_fun, continue_fun, help_flags \\ ["--help"])
      when is_function(help_fun, 0) and is_function(continue_fun, 0) do
    if help_requested?(argv, help_flags), do: help_fun.(), else: continue_fun.()
  end
end
