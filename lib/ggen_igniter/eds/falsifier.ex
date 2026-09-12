defmodule GgenIgniter.EDS.Falsifier do
  @moduledoc """
  A first-class falsifier (Executable Design Science, S9): "every strong
  computational claim [must] identify what would weaken it," and the
  research artifact must "make contradictory evidence representable" --
  a check function that CAN return `:falsified`, not one wired to always
  pass.

  `%Falsifier{}` pairs a human-readable statement of what would falsify the
  hypothesis with a real `check` function of arity 1 (taking the artifact's
  evidence) returning `{:survived, detail}` or `{:falsified, detail}`.
  `run/2` executes it for real against real evidence -- no interaction-only
  mock of "the falsifier passed."
  """

  @enforce_keys [:name, :statement, :check]
  defstruct [:name, :statement, :check]

  @type verdict :: {:survived, term()} | {:falsified, term()}
  @type t :: %__MODULE__{
          name: String.t(),
          statement: String.t(),
          check: (term() -> verdict())
        }

  @spec new(String.t(), String.t(), (term() -> verdict())) :: t()
  def new(name, statement, check)
      when is_binary(name) and is_binary(statement) and is_function(check, 1) do
    %__MODULE__{name: name, statement: statement, check: check}
  end

  @doc """
  Executes the falsifier's real check function against real evidence. Any
  raised exception is caught and reported as `:falsified` with the
  exception detail -- a falsifier that crashes has not survived, it has
  been falsified by an unhandled real failure.
  """
  @spec run(t(), term()) :: verdict()
  def run(%__MODULE__{check: check}, evidence) do
    result =
      try do
        {:ok, check.(evidence)}
      rescue
        exception -> {:crashed, Exception.format(:error, exception, __STACKTRACE__)}
      end

    case result do
      {:ok, {:survived, _detail} = ok} ->
        ok

      {:ok, {:falsified, _detail} = falsified} ->
        falsified

      {:crashed, detail} ->
        {:falsified, {:exception, detail}}

      {:ok, other} ->
        raise ArgumentError,
              "falsifier check must return {:survived, _} or {:falsified, _}, got: #{inspect(other)}"
    end
  end

  @doc "Runs every falsifier; returns the list of verdicts paired with each falsifier's name."
  @spec run_all([t()], term()) :: [{String.t(), verdict()}]
  def run_all(falsifiers, evidence) do
    Enum.map(falsifiers, fn f -> {f.name, run(f, evidence)} end)
  end

  @doc "True only if every falsifier in the list survived."
  @spec all_survived?([{String.t(), verdict()}]) :: boolean()
  def all_survived?(verdicts) do
    Enum.all?(verdicts, fn {_name, verdict} -> match?({:survived, _}, verdict) end)
  end
end
