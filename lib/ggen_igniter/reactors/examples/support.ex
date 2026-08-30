defmodule GgenIgniter.Reactors.Examples.Support do
  @moduledoc """
  Hand-authored (not ggen-manufactured) real collaborator functions backing
  the ontology-generated `GgenIgniter.Reactors.Examples.ExpenseApprovalReactor`
  practice/dogfood example. Deliberately simple, deterministic, real logic
  (no external I/O, no mocks) so
  `test/ggen_igniter_expense_approval_reactor_test.exs` can exercise the
  generated Reactor's real `run`/`compensate`/`undo` paths per this repo's
  Chicago-testing discipline — a real collaborator, not a stub standing in
  for one.
  """

  defmodule User do
    @moduledoc "A minimal in-memory user record for the example domain."
    defstruct [:email, :active?]
  end

  defmodule Charge do
    @moduledoc "A minimal in-memory charge record for the example domain."
    defstruct [:card_token, :amount, :refunded?]
  end

  @doc "Looks up a known user by email; unknown emails are a real error."
  @spec fetch_user(String.t()) :: {:ok, User.t()} | {:error, :not_found}
  def fetch_user(email) do
    known_users = %{
      "alice@example.com" => %User{email: "alice@example.com", active?: true},
      "bob@example.com" => %User{email: "bob@example.com", active?: false}
    }

    case Map.fetch(known_users, email) do
      {:ok, user} -> {:ok, user}
      :error -> {:error, :not_found}
    end
  end

  @doc """
  Charges a card for real (in-process, deterministic): amounts over 10_000
  are treated as a real declined-charge failure, to exercise the Reactor's
  compensate/undo paths in tests without any external payment gateway.
  """
  @spec charge(User.t(), number(), String.t()) :: {:ok, Charge.t()} | {:error, :declined}
  def charge(%User{}, amount, _card_token) when amount > 10_000,
    do: {:error, :declined}

  def charge(%User{}, amount, card_token),
    do: {:ok, %Charge{card_token: card_token, amount: amount, refunded?: false}}

  @doc """
  Refunds a charge for real: appends a real fact to the real,
  test-observable `GgenIgniter.Reactors.Examples.RefundLedger` process
  (a genuine collaborator with real state, not a mock) so tests can assert
  a `compensate`/`undo` step actually ran, not just that it compiled.
  """
  @spec refund(String.t(), number()) :: :ok
  def refund(card_token, amount) do
    GgenIgniter.Reactors.Examples.RefundLedger.record(card_token, amount)
    :ok
  end

  @doc """
  Builds a real receipt string from a user and a charge — fails for real
  (exercising `charge_payment`'s `undo` path) when the amount is exactly
  `13` (an intentionally silly, deterministic "unlucky amount" domain rule,
  chosen only so tests can trigger a real downstream failure without any
  external I/O).
  """
  @spec send_receipt(User.t(), Charge.t()) :: {:ok, String.t()} | {:error, :unlucky_amount}
  def send_receipt(%User{}, %Charge{amount: 13}), do: {:error, :unlucky_amount}

  def send_receipt(%User{email: email}, %Charge{amount: amount}),
    do: {:ok, "Receipt sent to #{email} for #{amount}"}

  @doc """
  `group`'s real `before_all/3` callback: passes arguments/context/steps
  through unchanged (no domain reason to modify them here), real 3-arity
  shape per `Reactor.Step.Group.before_fun/0`.
  """
  @spec audit_before(map(), map(), list()) :: {:ok, map(), map(), list()}
  def audit_before(arguments, context, steps), do: {:ok, arguments, context, steps}

  @doc """
  `group`'s real `after_all/1` callback: folds the nested step results into
  one real audited-summary value, per `Reactor.Step.Group.after_fun/0`.
  """
  @spec audit_after(map()) :: {:ok, String.t()}
  def audit_after(results), do: {:ok, "audited: #{inspect(Map.keys(results))}"}

  @doc """
  `around`'s real 4-arity wrapper function: logs entry/exit for real via
  `Logger`, then calls the real `callback` to actually run the wrapped
  steps — per `Reactor.Step.Around.around_fun/0`.
  """
  @spec with_logging(map(), map(), list(), (map(), map(), list() ->
                                              {:ok, any()} | {:error, any()})) ::
          {:ok, any()} | {:error, any()}
  def with_logging(arguments, context, steps, callback) do
    require Logger
    Logger.debug("around: entering wrapped steps")
    result = callback.(arguments, context, steps)
    Logger.debug("around: leaving wrapped steps")
    result
  end
end
