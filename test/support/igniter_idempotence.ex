defmodule GgenIgniter.Test.IgniterIdempotence do
  @moduledoc """
  Chicago-style idempotence harness for Igniter codemods: real
  `Igniter.Test.test_project/1`, real codemod, real `Igniter.Test.apply_igniter!/1`
  (simulated write), state-based assertions only -- no doubles.

  `assert_idempotent/3` = test_project -> apply codemod -> apply_igniter! ->
  apply codemod again -> `Igniter.Test.assert_unchanged/1`. It returns the final
  igniter so callers may add further state assertions.

  The codemod is either a 1-arity function (`igniter -> igniter`) or a task-name
  string, composed via `Igniter.compose_task/3` with `argv`.

  Options (third arg, `project_opts`): everything `Igniter.Test.test_project/1`
  accepts, plus

    * `:expect_change` (default `true`) -- the first run must actually change
      something, otherwise the check is vacuous (a codemod that does nothing is
      trivially idempotent) and the harness raises.

  `assert_refused/2` asserts the igniter carries an issue containing a substring.
  """

  import ExUnit.Assertions

  @type codemod :: (Igniter.t() -> Igniter.t()) | String.t()

  @spec assert_idempotent(codemod(), [String.t()], keyword()) :: Igniter.t()
  def assert_idempotent(codemod, argv \\ [], project_opts \\ []) do
    {expect_change, project_opts} = Keyword.pop(project_opts, :expect_change, true)

    first =
      project_opts
      |> Igniter.Test.test_project()
      |> run_codemod(codemod, argv)

    if expect_change do
      assert Igniter.changed?(first),
             "idempotence check is vacuous: first run changed nothing"
    end

    applied = Igniter.Test.apply_igniter!(first)

    applied
    |> run_codemod(codemod, argv)
    |> Igniter.Test.assert_unchanged()
  end

  @spec assert_refused(Igniter.t(), String.t()) :: Igniter.t()
  def assert_refused(%Igniter{issues: issues} = igniter, issue_substring) do
    assert Enum.any?(issues, &String.contains?(&1, issue_substring)),
           "expected an issue containing #{inspect(issue_substring)}, got: #{inspect(issues)}"

    igniter
  end

  defp run_codemod(igniter, fun, _argv) when is_function(fun, 1), do: fun.(igniter)

  defp run_codemod(igniter, task, argv) when is_binary(task),
    do: Igniter.compose_task(igniter, task, argv)
end
