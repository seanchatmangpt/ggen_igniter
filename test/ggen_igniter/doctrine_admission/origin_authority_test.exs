defmodule GgenIgniter.DoctrineAdmission.OriginAuthorityTest do
  use ExUnit.Case, async: true
  alias GgenIgniter.DoctrineAdmission.OriginAuthority

  test "admits absolute HTTP IRIs and refuses prose" do
    assert :ok = OriginAuthority.admit("https://example.org/doctrine#objective")

    assert {:error, {:refused_doctrine, :origin_authority, :invalid_iri}} =
             OriginAuthority.admit("the memo said so")
  end
end
