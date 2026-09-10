defmodule GgenIgniter.DigestTest do
  use ExUnit.Case, async: true

  alias GgenIgniter.Digest

  # Known SHA-256 vector: sha256("abc") ==
  # ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad
  @known_input "abc"
  @known_hex "ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad"

  describe "hex/1" do
    test "returns the raw lowercase hex digest for a known vector" do
      assert Digest.hex(@known_input) == @known_hex
    end

    test "returns the well-known digest for the empty binary" do
      assert Digest.hex("") ==
               "e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855"
    end

    test "raises FunctionClauseError for a non-binary argument" do
      assert_raise FunctionClauseError, fn -> Digest.hex(123) end
      assert_raise FunctionClauseError, fn -> Digest.hex(nil) end
      assert_raise FunctionClauseError, fn -> Digest.hex(:atom) end
    end
  end

  describe "sha256/1" do
    test "prefixes the known-vector hex digest with \"sha256:\"" do
      assert Digest.sha256(@known_input) == "sha256:" <> @known_hex
    end

    test "raises FunctionClauseError for a non-binary argument" do
      assert_raise FunctionClauseError, fn -> Digest.sha256(123) end
    end
  end
end
