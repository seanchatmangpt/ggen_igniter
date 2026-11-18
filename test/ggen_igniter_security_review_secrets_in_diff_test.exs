defmodule GgenIgniter.SecurityReviewSecretsInDiffTest do
  @moduledoc """
  Chicago-style: real unified-diff strings parsed by the real
  `GgenIgniter.SecurityReview.DiffSource.parse/1`, then run through the real
  `GgenIgniter.SecurityReview.Checks.SecretsInDiff.check/2`. No doubles; all
  assertions are on the returned finding maps. Credential-shaped literals are
  assembled by concatenation so this source never holds a contiguous secret shape.
  """
  use ExUnit.Case, async: true

  alias GgenIgniter.SecurityReview.Checks.SecretsInDiff
  alias GgenIgniter.SecurityReview.DiffSource

  @aws "AKIA" <> "IOSFODNN7EXAMPLE"
  @val "Zx9Qw" <> "3Er7Ty"

  defp pem(kind), do: "-----BEGIN " <> kind <> "PRIV" <> "ATE KEY-----"

  # name/sep/value joined at runtime: "api_" <> "key", ": ", ...
  defp kv(name, sep, value), do: name <> sep <> value
  defp api_key, do: "api_" <> "key"
  defp token, do: "tok" <> "en"
  defp secret, do: "sec" <> "ret"
  defp password, do: "pass" <> "word"

  # One-file diff whose hunk starts at `start`; `lines` are raw diff body lines
  # (already carrying their +/-/space prefix).
  defp diff_text(path, start, lines) do
    "diff --git a/#{path} b/#{path}\n--- a/#{path}\n+++ b/#{path}\n" <>
      "@@ -1,1 +#{start},#{length(lines)} @@\n" <> Enum.join(lines, "\n") <> "\n"
  end

  defp findings(lines, path \\ "lib/a.ex", start \\ 1) do
    path |> diff_text(start, lines) |> DiffSource.parse() |> SecretsInDiff.check([])
  end

  describe "check/2 (aws access key)" do
    test "AKIA key is flagged high with rule aws_access_key and a masked evidence" do
      assert [f] = findings(["+aws_id = \"#{@aws}\""])
      assert f.category == "secrets"
      assert f.rule == "aws_access_key"
      assert f.severity == :high
      assert f.file == "lib/a.ex"
      assert f.line == 1
      assert f.evidence == "aws_id = \"AKIA...\""
      refute String.contains?(f.evidence, @aws)
    end

    test "a 21-char run starting AKIA is not flagged" do
      assert [] == findings(["+x = \"#{@aws}X\""])
    end

    test "a key preceded by a word char (XAKIA...) is not flagged" do
      assert [] == findings(["+x = \"X#{@aws}\""])
    end
  end

  describe "check/2 (PEM private keys)" do
    test "RSA, EC and bare private-key headers are flagged as private_key" do
      for kind <- ["RSA ", "EC ", ""] do
        assert [f] = findings(["+" <> pem(kind)])
        assert f.rule == "private_key"
        assert f.severity == :high
      end
    end

    test "a PUBLIC key header is not flagged" do
      assert [] == findings(["+-----BEGIN PUBLIC KEY-----"])
    end
  end

  describe "check/2 (credential_assignment)" do
    test "api key with a high-entropy quoted value is flagged and masked" do
      assert [f] = findings(["+" <> kv(api_key(), ": ", "\"" <> @val <> "\"")])
      assert f.rule == "credential_assignment"
      assert f.severity == :high
      assert f.evidence == api_key() <> ": \"Zx9Q...\""
      refute String.contains?(f.evidence, @val)
    end

    test "entropy boundary: 8 distinct chars (exactly 3.0 bits) with digit+letter is flagged" do
      # abc12345 -> 8 distinct graphemes, entropy = log2(8) = 3.0 exactly.
      assert [f] = findings(["+" <> kv(password(), " = ", "abc12345")])
      assert f.rule == "credential_assignment"
      assert f.evidence == password() <> " = abc1..."
    end

    test "low-entropy, digit-only, letter-only and short values are not flagged" do
      assert [] == findings(["+" <> kv(token(), "=", "aaaa1111")])
      assert [] == findings(["+" <> kv(password(), ": ", "12345678")])
      assert [] == findings(["+" <> kv(token(), " = ", "abcdefgh")])
      # 7 chars: below the {8,} floor of the assignment regex
      assert [] == findings(["+" <> kv(token(), "=", "Zx9Qw3E")])
    end

    test "masking never leaks the full secret value" do
      value = "Qm7Lp2" <> "Vn8Xz4"
      assert [f] = findings(["+" <> kv(secret(), " = ", "\"" <> value <> "\" # keep")])
      refute String.contains?(f.evidence, value)
      assert String.contains?(f.evidence, "Qm7L...")
    end

    # CHARACTERIZATION: suspected defect
    # Regex.run/2 returns only the FIRST assignment on a line; the first value is
    # low entropy, so the real credential in the second assignment is missed.
    test "CHARACTERIZATION: second assignment on one line is missed" do
      line = kv(token(), "=", "placeholder ") <> kv(secret(), "=", @val)
      assert [] == findings(["+" <> line])
    end
  end

  describe "check/2 (line selection and attribution)" do
    test "removed and context lines are ignored" do
      assigned = kv(api_key(), ": ", "\"" <> @val <> "\"")
      assert [] == findings(["-" <> assigned, " " <> assigned, "+ok = 1"])
    end

    test "findings carry the right file and new-file line number across files" do
      assigned = kv(api_key(), ": ", "\"" <> @val <> "\"")

      text =
        "diff --git a/lib/one.ex b/lib/one.ex\n--- a/lib/one.ex\n+++ b/lib/one.ex\n" <>
          "@@ -1,2 +5,3 @@\n ctx\n+safe = 1\n+" <>
          assigned <>
          "\ndiff --git a/lib/two.ex b/lib/two.ex\n--- a/lib/two.ex\n+++ b/lib/two.ex\n" <>
          "@@ -1,1 +20,1 @@\n+x = \"#{@aws}\"\n"

      found = text |> DiffSource.parse() |> SecretsInDiff.check([])

      assert [
               %{file: "lib/one.ex", line: 7, rule: "credential_assignment"},
               %{file: "lib/two.ex", line: 20, rule: "aws_access_key"}
             ] = found
    end

    test "empty diff yields no findings" do
      assert [] == SecretsInDiff.check(DiffSource.parse(""), [])
      assert [] == SecretsInDiff.check(%{files: []}, [])
    end
  end
end
