defmodule GgenIgniter.RefusalsTest do
  @moduledoc """
  Chicago-style: reads the real `priv/schema/refusals.schema.json` and mines the
  real `lib/**/*.ex` sources from disk with a regex detector; the detector's own
  falsifier runs against a real temp file. No doubles.
  """
  use ExUnit.Case, async: true
  use ExUnitProperties
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

      required = ~w(broken_term code example family fix_hint owner retryable)
      optional = ~w(hint_group not_applicable_reason)

      for e <- entries do
        keys = Map.keys(e)
        assert required -- keys == [], "#{e["code"]} lacks required keys"
        assert keys -- (required ++ optional) == [], "#{e["code"]} has unknown keys"

        assert e["code"] =~ ~r/\A[A-Z][A-Z0-9]*(_[A-Z0-9]+)*\z/
        assert is_boolean(e["retryable"])
        assert String.starts_with?(e["example"], "REFUSED:")
        assert e["owner"] =~ ~r/\A[A-Z][A-Za-z0-9_.]*\z/
      end
    end
  end

  describe "registry quality" do
    setup do
      {:ok, entries: @schema |> File.read!() |> Jason.decode!() |> Map.fetch!("refusals")}
    end

    test "no entry has a null broken_term; not_applicable carries a reason", %{entries: entries} do
      for e <- entries do
        assert is_binary(e["broken_term"]), "#{e["code"]}: broken_term is null"
        assert e["broken_term"] in (@broken_terms ++ ["not_applicable"]), e["code"]

        if e["broken_term"] == "not_applicable" do
          assert is_binary(e["not_applicable_reason"]) and e["not_applicable_reason"] != "",
                 "#{e["code"]}: not_applicable needs not_applicable_reason"
        else
          refute Map.has_key?(e, "not_applicable_reason"), e["code"]
        end
      end
    end

    test "fix_hints are specific: no template text, no sharing without a hint_group",
         %{entries: entries} do
      for e <- entries do
        refute e["fix_hint"] =~ "tuple's reason", "#{e["code"]}: templated fix_hint"
        refute e["fix_hint"] =~ "repair its subject", "#{e["code"]}: templated fix_hint"
        assert String.length(e["fix_hint"]) >= 12, e["code"]
      end

      shared =
        entries
        |> Enum.group_by(& &1["fix_hint"])
        |> Enum.filter(fn {_hint, es} -> length(es) > 1 end)

      for {hint, es} <- shared do
        groups = es |> Enum.map(& &1["hint_group"]) |> Enum.uniq()

        assert match?([g] when is_binary(g), groups),
               "#{inspect(Enum.map(es, & &1["code"]))} share fix_hint #{inspect(hint)} without one hint_group"
      end
    end

    test "DO's hint and broken_term agree with its emitter (origin refusal / claim store / precondition)",
         %{entries: entries} do
      do_entry = Enum.find(entries, &(&1["code"] == "DO"))
      assert do_entry["broken_term"] == "R_missing_authority"
      assert do_entry["fix_hint"] =~ "claim"
      assert do_entry["fix_hint"] =~ "precondition"
    end

    test "count is derived from the schema (never hardcoded) and docs state it", %{
      entries: entries
    } do
      schema = @schema |> File.read!() |> Jason.decode!()
      assert Refusals.count() == length(entries)
      assert Refusals.count() == length(get_in(schema, ["$defs", "code", "enum"]))

      doc = File.read!(Path.expand("../docs/reference/refusals.md", __DIR__))
      assert doc =~ "#{Refusals.count()} codes"

      [_, registry] = String.split(doc, "## Registry", parts: 2)
      rows = registry |> String.split("\n") |> Enum.count(&String.starts_with?(&1, "| `"))
      assert rows == Refusals.count() + length(Refusals.wrapped_reasons())
    end

    test "wrapped_reasons name a parent code and do not collide with codes", %{entries: entries} do
      wrapped = @schema |> File.read!() |> Jason.decode!() |> Map.fetch!("wrapped_reasons")
      codes = MapSet.new(entries, & &1["code"])

      for w <- wrapped do
        assert Enum.sort(Map.keys(w)) == ~w(note parent reason)
        assert MapSet.member?(codes, w["parent"]), "#{w["reason"]}: unknown parent #{w["parent"]}"
        assert w["reason"] =~ ~r/\A[A-Z][A-Z0-9_]*\z/

        refute MapSet.member?(codes, w["reason"]),
               "#{w["reason"]} is both code and wrapped reason"
      end

      reasons = Enum.map(wrapped, & &1["reason"])
      assert reasons == Enum.uniq(reasons)
    end

    test "the pinned seam codes exist with pinned metadata", %{entries: entries} do
      by = Map.new(entries, &{&1["code"], &1})

      for {code, term} <- [
            {"PACK_SYMLINK_ESCAPE", "R_missing_identity"},
            {"PACK_LOCK_INVALID", "admission_vacuous"},
            {"PACK_FILE_UNREADABLE", "R_missing_identity"}
          ] do
        assert %{"retryable" => false, "owner" => "GgenIgniter.PackLock"} = e = by[code]
        assert e["broken_term"] == term
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

  describe "exhaustiveness (reason atoms in emitter modules)" do
    @emitters ~w(
      lib/ggen_igniter/semantic_jira.ex
      lib/ggen_igniter/semantic_work_order.ex
      lib/ggen_igniter/enterprise_architecture.ex
      lib/ggen_igniter/gate_verify.ex
      lib/ggen_igniter/semantic_jira/cs2_batch.ex
    )
    # Posix/File error atoms that are I/O results, not refusals.
    @io_atoms MapSet.new(~w(ENOENT EACCES EEXIST EISDIR ENOTDIR))

    defp accounted do
      wrapped = Enum.map(Refusals.wrapped_reasons(), & &1.reason)
      codes = Enum.map(Refusals.all(), &Atom.to_string(&1.code))
      MapSet.new(wrapped ++ codes)
    end

    test "every {:error, :atom} / {:refused, :atom} in the emitters is a code or a wrapped reason" do
      root = Path.expand("..", __DIR__)

      undeclared =
        for rel <- @emitters,
            atom <- Refusals.scan_reason_atoms(File.read!(Path.join(root, rel))),
            not MapSet.member?(@io_atoms, atom),
            not MapSet.member?(accounted(), atom),
            do: {rel, atom}

      assert undeclared == []
    end

    test "the audit-named atoms are declared" do
      for a <-
            ~w(INTENT_DIGEST_MISMATCH STALE_INTENT SCOPE_EXPANSION INTENT_NOT_BOUND_TO_WORK_ORDER
                  WORK_ORDER_DRIFT PACKAGE_DIGEST_MISMATCH ABB_MISMATCH AUTHORITY_WIDENING
                  MISSING_ANCHOR DUPLICATE_WORK_IDENTITY) do
        assert MapSet.member?(accounted(), a), "#{a} undeclared"
      end
    end

    test "falsifier: a temp file with an undeclared {:error, :zz_fake} is flagged" do
      dir = Path.join(System.tmp_dir!(), "refusals_atoms_#{System.unique_integer([:positive])}")
      File.rm_rf!(dir)
      File.mkdir_p!(dir)
      on_exit(fn -> File.rm_rf!(dir) end)
      path = Path.join(dir, "fake.ex")
      File.write!(path, "def f(x), do: {:error, :zz_fake}\ndef g, do: {:refused, :zz_other}\n")

      flagged =
        for atom <- Refusals.scan_reason_atoms(File.read!(path)),
            not MapSet.member?(accounted(), atom),
            do: atom

      assert Enum.sort(flagged) == ["ZZ_FAKE", "ZZ_OTHER"]
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

    test "legacy REFUSED(code) emitter form no longer parses (D2 removal law)" do
      assert {:error, :not_a_refusal} = Refusals.parse("REFUSED(input_invalid) goal.json: bad")
      assert {:error, :not_a_refusal} = Refusals.parse("REFUSED(usage) -: --out is required")
    end

    test "legacy bare REFUSED_CODE emitter form no longer parses (D2 removal law)" do
      assert {:error, :not_a_refusal} = Refusals.parse("REFUSED_GENERATED_ARTIFACT_MUTATED")
      assert {:error, :not_a_refusal} = Refusals.parse("REFUSED_EPOCH_LEGACY_EDIT order-1")

      assert {:error, :not_a_refusal} =
               Refusals.parse("REFUSED_SUBJECT_EXHAUSTED: no free subject")

      # the canonical colon form is the ONE parseable form
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

    test "parse keeps the detail verbatim: only the separator space is stripped" do
      assert {:ok, {:LEGACY_EDIT, "   x  "}} = Refusals.parse("REFUSED:LEGACY_EDIT    x  ")
      assert {:ok, {:LEGACY_EDIT, "a\n"}} = Refusals.parse("REFUSED:LEGACY_EDIT a\n")
      assert {:ok, {:INPUT_INVALID, " lead"}} = Refusals.parse("REFUSED:INPUT_INVALID  lead")
    end

    test "parse normalises lowercase and mixed-case codes; non-binaries are not refusals" do
      assert {:ok, {:LEGACY_EDIT, "x"}} = Refusals.parse("REFUSED:legacy_edit x")
      assert {:ok, {:LEGACY_EDIT, "x"}} = Refusals.parse("REFUSED:Legacy_Edit x")
      assert {:error, :not_a_refusal} = Refusals.parse(nil)
      assert {:error, :not_a_refusal} = Refusals.parse(:REFUSED)
      assert {:error, :not_a_refusal} = Refusals.parse(123)
    end

    test "format accepts atom codes case-insensitively; unknown codes raise naming the code" do
      assert Refusals.format(:legacy_edit, "x") == "REFUSED:LEGACY_EDIT x"
      assert Refusals.format("legacy_edit", "x") == "REFUSED:LEGACY_EDIT x"

      err = assert_raise ArgumentError, fn -> Refusals.format(:zz_fake, "x") end
      assert err.message =~ "ZZ_FAKE" or err.message =~ "zz_fake"
    end

    property "parse(format(c, d)) == {:ok, {c, d}} for arbitrary details" do
      codes = Enum.map(Refusals.all(), & &1.code)

      check all(
              code <- member_of(codes),
              detail <-
                one_of([
                  string(:printable),
                  string(:utf8),
                  map(string(:ascii), &(" \n\t" <> &1 <> "  \n")),
                  constant("  "),
                  constant("\n"),
                  constant("é✓🙂 ünï")
                ]),
              max_runs: 200
            ) do
        assert {:ok, {^code, ^detail}} = Refusals.parse(Refusals.format(code, detail))
      end
    end

    test "round-trips a 200k-character detail with edge whitespace" do
      detail = " \n" <> String.duplicate("ab\n🙂 ", 40_000) <> "  "
      assert String.length(detail) > 200_000

      assert {:ok, {:LEGACY_EDIT, ^detail}} =
               Refusals.parse(Refusals.format(:LEGACY_EDIT, detail))
    end
  end
end
