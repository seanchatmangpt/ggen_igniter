defmodule GgenIgniter.DoctrineAdmission.CompatibilityTest do
  use ExUnit.Case, async: true
  alias GgenIgniter.DoctrineAdmission.Compatibility

  test "admits only the canonical representation version" do
    artifact = %{"schema_version" => "doctrine-admission/v1"}
    assert {:ok, ^artifact} = Compatibility.admit(artifact)

    assert {:error, {:refused_doctrine, :compatibility, {:unsupported_version, "v0"}}} =
             Compatibility.admit(%{"schema_version" => "v0"})
  end
end
