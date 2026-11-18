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

  describe "compensate/undo refund paths" do
    alias GgenIgniter.Reactors.Examples.{RefundLedger, Support}

    defp ledger_for(token), do: Enum.filter(RefundLedger.all(), fn {t, _} -> t == token end)

    test "undo succeeds on later-step failure: charge is refunded in the ledger" do
      assert {:error, _} =
               Reactor.run(ExpenseApprovalReactor, %{
                 email: "alice@example.com",
                 amount: 13,
                 card_token: "tok_undo_ok_1"
               })

      assert {"tok_undo_ok_1", 13} in ledger_for("tok_undo_ok_1")
    end

    test "undo fails visibly: refund_failed surfaces and nothing is recorded" do
      assert {:error, err} =
               Reactor.run(ExpenseApprovalReactor, %{
                 email: "alice@example.com",
                 amount: 13,
                 card_token: "tok_refund_fails"
               })

      assert inspect(err) =~ "refund_failed"
      assert ledger_for("tok_refund_fails") == []
    end

    test "compensate fails: declined charge with failing refund records nothing" do
      assert {:error, _} =
               Reactor.run(ExpenseApprovalReactor, %{
                 email: "alice@example.com",
                 amount: 999_999,
                 card_token: "tok_refund_fails"
               })

      assert ledger_for("tok_refund_fails") == []
    end

    test "compensate success: requested amount is refunded" do
      assert {:error, _} =
               Reactor.run(ExpenseApprovalReactor, %{
                 email: "alice@example.com",
                 amount: 999_999,
                 card_token: "tok_comp_ok"
               })

      assert {"tok_comp_ok", 999_999} in ledger_for("tok_comp_ok")
    end

    test "Support.refund/2 returns a typed error for the failing token" do
      assert Support.refund("tok_refund_fails", 1) == {:error, :refund_failed}
    end
  end
end
