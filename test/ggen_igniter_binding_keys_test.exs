defmodule GgenIgniter.BindingKeysTest do
  use ExUnit.Case, async: true

  alias GgenIgniter.BindingKeys

  test "atomize!/1 admits identifier-shaped strings and passes atoms through" do
    assert BindingKeys.atomize!("moduleName") == :moduleName
    assert BindingKeys.atomize!(:already) == :already
  end

  test "atomize!/1 refuses non-identifier keys (no open atom mint)" do
    assert_raise ArgumentError, ~r/not an admitted identifier/, fn ->
      BindingKeys.atomize!("evil-key")
    end

    assert_raise ArgumentError, ~r/not an admitted identifier/, fn ->
      BindingKeys.atomize!("with space")
    end

    hostile = String.duplicate("a", 129)

    assert_raise ArgumentError, ~r/not an admitted identifier/, fn ->
      BindingKeys.atomize!(hostile)
    end
  end
end
