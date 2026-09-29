defmodule GgenIgniter.RefusalsTest do
  @moduledoc """
  Chicago-style: reads the real `priv/schema/refusals.schema.json` and mines the
  real `lib/**/*.ex` sources from disk with a regex detector; the detector's own
  falsifier runs against a real temp file. No doubles.
  """
  use ExUnit.Case, async: true
  doctest GgenIgniter.Refusals

  alias GgenIgniter.Refusals

  @schema Path.expand("../priv/schema/refusals.schema.json", __DIR__)
  @broken_terms ~w(mu_on_O admission_vacuous mu_unlawful R_missing_identity R_missing_authority
                   R_missing_consequence R_missing_replay R_missing_standing R_not_fed_back)

  # Every refusal-code literal shape emitted in lib/.
  @detectors [
    ~r/REFUSED:([A-Z][A-Z0-9_]*[A-Z0-9])(?![A-Z0-9_*])/,
    ~r/REFUSED_([A-Z][A-Z0-9_]*[A-Z0-9])(?![A-Z0-9_*])/,
    ~r/REFUSED\(([A-Za-z][A-Za-z0-9_]*)\)/,
    ~r/\brefus(?:al|ed)\(\s*:([a-z][a-z0-9_]*)/,
    ~r/:refused_([a-z][a-z0-9_]*)/
  ]

  # Doc placeholders that look like codes but are not: `REFUSED(reason)` in
  # semantic_a2a's standing normaliser docs, `REFUSED(code)` in this vocabulary
  # module's own moduledoc.
  @placeholders MapSet.new(["REASON", "CODE"])

  @doc false
  def mine(source) do
    for re <- @detectors,
        [_, c] <- Regex.scan(re, source),
        into: MapSet.new(),
        do: String.upcase(c)
  end

  defp lib_sources do
    Path.expand("../lib", __DIR__) |> Path.join("**/*.ex") |> Path.wildcard()
  end

  describe "schema validity" do
    test "is a 2020-12 schema whose enum and registry agree and entries are well-formed" do
      schema = @schema |> File.read!() |> Jason.decode!()
      assert schema["$schema"] == "https://json-schema.org/draft/2020-12/schema"
      enum = get_in(schema, ["$defs", "code", "enum"])
      entries = schema["refusals"]
      assert Enum.sort(enum) == Enum.sort(Enum.map(entries, & &1["code"]))
      assert length(enum) == length(Enum.uniq(enum))

      for e <- entries do
        assert Enum.sort(Map.keys(e)) ==
                 ~w(broken_term code example family fix_hint owner retryable)

        assert e["code"] =~ ~r/\A[A-Z][A-Z0-9]*(_[A-Z0-9]+)*\z/
        assert is_boolean(e["retryable"])
        assert e["broken_term"] == nil or e["broken_term"] in @broken_terms
        assert String.starts_with?(e["example"], "REFUSED:")
        assert e["owner"] =~ ~r/\A[A-Z][A-Za-z0-9_.]*\z/
      end
    end
  end

  describe "exhaustiveness (detector over lib/**/*.ex)" do
    test "every refusal-code literal in lib/ is in the enum" do
      known = MapSet.new(Refusals.all(), &Atom.to_string(&1.code))

      missing =
        for path <- lib_sources(),
            code <- mine(File.read!(path)),
            not MapSet.member?(@placeholders, code),
            not MapSet.member?(known, code),
            do: {Path.relative_to(path, Path.expand("..", __DIR__)), code}

      assert missing == []
    end

    test "falsifier: the detector flags an unenumerated code in a real temp file" do
      dir = Path.join(System.tmp_dir!(), "refusals_#{System.unique_integer([:positive])}")
      File.rm_rf!(dir)
      File.mkdir_p!(dir)
      on_exit(fn -> File.rm_rf!(dir) end)
      path = Path.join(dir, "fake.ex")
      File.write!(path, ~s|def f, do: "REFUSED:ZZ_FAKE nope"\n|)

      known = MapSet.new(Refusals.all(), &Atom.to_string(&1.code))
      assert MapSet.difference(mine(File.read!(path)), known) == MapSet.new(["ZZ_FAKE"])
    end
  end

  describe "parse/1 and format/2" do
    test "round-trips the canonical form for every code" do
      for %{code: code} <- Refusals.all() do
        assert {:ok, {^code, "some detail"}} =
                 Refusals.parse(Refusals.format(code, "some detail"))

        assert {:ok, {^code, ""}} = Refusals.parse(Refusals.format(code))
      end
    end

    test "parses legacy REFUSED(code) subject: detail" do
      assert {:ok, {:INPUT_INVALID, "goal.json: bad"}} =
               Refusals.parse("REFUSED(input_invalid) goal.json: bad")

      assert {:ok, {:USAGE, "-: --out is required"}} =
               Refusals.parse("REFUSED(usage) -: --out is required")
    end

    test "parses legacy bare REFUSED_CODE atoms and epoch codes" do
      assert {:ok, {:GENERATED_ARTIFACT_MUTATED, ""}} =
               Refusals.parse("REFUSED_GENERATED_ARTIFACT_MUTATED")

      assert {:ok, {:EPOCH_LEGACY_EDIT, "order-1"}} =
               Refusals.parse("REFUSED_EPOCH_LEGACY_EDIT order-1")

      assert {:ok, {:SUBJECT_EXHAUSTED, "no free subject"}} =
               Refusals.parse("REFUSED_SUBJECT_EXHAUSTED: no free subject")

      assert {:ok, {:SEMANTIC_JIRA_BASE_SHA_UNVERIFIED, "baseSha abc"}} =
               Refusals.parse("REFUSED:SEMANTIC_JIRA_BASE_SHA_UNVERIFIED: baseSha abc")
    end

    test "rejects non-refusals and unknown codes; format raises on unknown" do
      assert {:error, :not_a_refusal} = Refusals.parse("all good")
      assert {:error, {:unknown_code, "ZZ_FAKE"}} = Refusals.parse("REFUSED:ZZ_FAKE x")
      assert_raise ArgumentError, fn -> Refusals.format(:ZZ_FAKE, "x") end
      refute Refusals.known?(:ZZ_FAKE)
      assert Refusals.known?("legacy_edit")
      assert {:ok, %{family: "epoch_verdict"}} = Refusals.fetch(:LEGACY_EDIT)
    end
  end
end
