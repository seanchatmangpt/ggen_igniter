defmodule GgenIgniter.Reactors.Examples.ExpenseApprovalReactorTest do
  @moduledoc """
  Chicago-style tests over the real, ontology-generated
  `GgenIgniter.Reactors.Examples.ExpenseApprovalReactor` (see
  `priv/ggen/reactor-scaffold-pack/`) — real `Reactor.run/4` calls against
  the real `GgenIgniter.Reactors.Examples.Support` collaborator, state-based
  assertions on the real returned/refunded values. No mocks.
  """
  use ExUnit.Case, async: true

  alias GgenIgniter.Reactors.Examples.ExpenseApprovalReactor

  test "happy path: active user, valid charge, returns the real charge" do
    assert {:ok, charge} =
             Reactor.run(ExpenseApprovalReactor, %{
               email: "alice@example.com",
               amount: 42,
               card_token: "tok_123"
             })

    assert charge.amount == 42
    assert charge.card_token == "tok_123"
  end

  test "unknown user: fetch_user fails, whole run fails with the real reason" do
    assert {:error, _reason} =
             Reactor.run(ExpenseApprovalReactor, %{
               email: "nobody@example.com",
               amount: 42,
               card_token: "tok_123"
             })
  end

  test "inactive user: validate_user fails before any charge is attempted" do
    assert {:error, %Reactor.Error.Invalid{errors: [%{error: :inactive_user}]}} =
             Reactor.run(ExpenseApprovalReactor, %{
               email: "bob@example.com",
               amount: 42,
               card_token: "tok_456"
             })
  end

  test "declined charge: charge_payment's real run fails, no undo needed (nothing to roll back yet)" do
    assert {:error, %Reactor.Error.Invalid{errors: [%{error: :declined}]}} =
             Reactor.run(ExpenseApprovalReactor, %{
               email: "alice@example.com",
               amount: 999_999,
               card_token: "tok_789"
             })
  end
end
