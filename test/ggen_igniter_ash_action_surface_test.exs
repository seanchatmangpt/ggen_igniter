defmodule GgenIgniter.AshActionSurfaceTest do
  @moduledoc """
  Chicago-style: renders `priv/ggen/ash-igniter-api-pack` from a consumer ontology with a REAL
  `mix ggen_igniter.sync` subprocess, compiles the rendered `Igniter.Mix.Task`, runs it against a
  real in-memory `Igniter.Test.test_project/1` (real `ash.gen.resource`, `ash.extend`,
  `Ash.Resource.Igniter.*`), compiles the RESULTING resource/domain sources with the real compiler
  and drives them with real Ash calls on the ETS data layer. Assertions are on final state:
  `Ash.Resource.Info`, `{:error, %Ash.Error.Invalid{}}` plus the stored rows, loaded aggregates,
  No doubles, no mocks.

  Falsifiers (each re-renders a MUTATED ontology and asserts the state assertion flips):
  drop the validation facts -> the invalid create succeeds; drop the multitenancy fact -> the
  strategy disappears. Aggregates and code interfaces live in
  `ggen_igniter_ash_aggregates_interfaces_test.exs`; policies in `..._policies_enforce_test.exs`.

  Regeneration: hand-added lines inside a generated action survive byte-identical; a changed
  `accepts` fact does NOT rewrite an existing action (add_new_action skips by name) and surfaces
  as the typed warning `ASH_API_ACCEPT_DRIFT`.
  """
  use ExUnit.Case, async: false

  import ExUnit.CaptureIO
  import Igniter.Test

  alias GgenIgniter.Test.PackCompile

  @moduletag :integration
  @moduletag timeout: 1_800_000

  @domain Shelf.Library
  @book Shelf.Library.Book
  @author Shelf.Library.Author
  @loan Shelf.Library.Loan
  @task Mix.Tasks.Shelf.Manufacture.Surface

  @prefix """
  @prefix aia: <https://ggen-igniter.dev/ontology/ash-igniter-api#> .
  """

  @ontology @prefix <>
              """
              aia:project a aia:Project ;
                  aia:otpApp "shelf" ;
                  aia:taskModule "Mix.Tasks.Shelf.Manufacture.Surface" ;
                  aia:taskName "shelf.manufacture.surface" .

              aia:resBook a aia:Resource ; aia:resourceModule "Shelf.Library.Book" ; aia:domainModule "Shelf.Library" ; aia:order 1 .
              aia:resAuthor a aia:Resource ; aia:resourceModule "Shelf.Library.Author" ; aia:domainModule "Shelf.Library" ; aia:order 2 .
              aia:resLoan a aia:Resource ; aia:resourceModule "Shelf.Library.Loan" ; aia:domainModule "Shelf.Library" ; aia:order 3 .

              aia:extBook a aia:Extension ; aia:resourceOf aia:resBook ; aia:extensionName "ets" ; aia:order 1 .
              aia:extAuthor a aia:Extension ; aia:resourceOf aia:resAuthor ; aia:extensionName "ets" ; aia:order 1 .
              aia:extLoan a aia:Extension ; aia:resourceOf aia:resLoan ; aia:extensionName "ets" ; aia:order 1 .

              # ---- Book ----
              aia:attrTitle a aia:Attribute ; aia:resourceOf aia:resBook ; aia:attributeName "title" ;
                  aia:attributeType "string" ; aia:isPublic true ; aia:isRequired true ; aia:order 1 .
              aia:attrIsbn a aia:Attribute ; aia:resourceOf aia:resBook ; aia:attributeName "isbn" ;
                  aia:attributeType "string" ; aia:isPublic true ; aia:isRequired false ; aia:order 2 .
              aia:attrPages a aia:Attribute ; aia:resourceOf aia:resBook ; aia:attributeName "pages" ;
                  aia:attributeType "integer" ; aia:isPublic true ; aia:isRequired false ; aia:order 3 .
              aia:attrStatus a aia:Attribute ; aia:resourceOf aia:resBook ; aia:attributeName "status" ;
                  aia:attributeType "string" ; aia:isPublic true ; aia:isRequired false ; aia:order 4 .

              aia:actRead a aia:Action ; aia:resourceOf aia:resBook ; aia:actionName "read" ;
                  aia:actionType "read" ; aia:accepts "" ; aia:order 1 .
              aia:primRead a aia:PrimaryAction ; aia:actionOf aia:actRead .
              aia:actRegister a aia:Action ; aia:resourceOf aia:resBook ; aia:actionName "register" ;
                  aia:actionType "create" ; aia:accepts "title,isbn,pages" ; aia:order 2 .

              aia:argNotes a aia:Argument ; aia:actionOf aia:actRegister ; aia:argumentName "notes" ;
                  aia:argumentType "string" ; aia:allowNil true ; aia:order 1 .
              aia:argAuthorRef a aia:Argument ; aia:actionOf aia:actRegister ; aia:argumentName "author_ref" ;
                  aia:argumentType "uuid" ; aia:allowNil true ; aia:order 2 .
              aia:chgStatus a aia:SetAttribute ; aia:actionOf aia:actRegister ; aia:attributeName "status" ;
                  aia:valueLiteral "draft" ; aia:valueType "string" ; aia:order 1 .
              aia:chgAuthor a aia:ManageRelationship ; aia:actionOf aia:actRegister ; aia:argumentName "author_ref" ;
                  aia:relationshipName "author" ; aia:manageType "append" ; aia:order 1 .
              aia:valIsbnPresent a aia:Validation ; aia:actionOf aia:actRegister ; aia:validationKind "present" ;
                  aia:validationSubject "isbn" ; aia:validationOption "" ; aia:validationValue "" ;
                  aia:validationValueType "string" ; aia:order 1 .
              aia:valIsbnMatch a aia:Validation ; aia:actionOf aia:actRegister ; aia:validationKind "match" ;
                  aia:validationSubject "isbn" ; aia:validationOption "" ; aia:validationValue "^[0-9]{10}$" ;
                  aia:validationValueType "string" ; aia:order 2 .
              aia:valPagesCompare a aia:Validation ; aia:actionOf aia:actRegister ; aia:validationKind "compare" ;
                  aia:validationSubject "pages" ; aia:validationOption "greater_than" ; aia:validationValue "0" ;
                  aia:validationValueType "integer" ; aia:order 3 .

              aia:relAuthor a aia:Relationship ; aia:resourceOf aia:resBook ; aia:relationshipKind "belongs_to" ;
                  aia:relationshipName "author" ; aia:destination "Shelf.Library.Author" ;
                  aia:isPublic true ; aia:isRequired false ; aia:order 1 .
              aia:idIsbn a aia:Identity ; aia:resourceOf aia:resBook ; aia:identityName "unique_isbn" ;
                  aia:identityKeys "isbn" ; aia:order 1 .


              # ---- Author ----
              aia:attrAuthorName a aia:Attribute ; aia:resourceOf aia:resAuthor ; aia:attributeName "name" ;
                  aia:attributeType "string" ; aia:isPublic true ; aia:isRequired true ; aia:order 1 .
              aia:actEnroll a aia:Action ; aia:resourceOf aia:resAuthor ; aia:actionName "enroll" ;
                  aia:actionType "create" ; aia:accepts "name" ; aia:order 1 .
              aia:ensureAuthorRead a aia:EnsurePrimary ; aia:resourceOf aia:resAuthor ; aia:actionType "read" .
              aia:relBooks a aia:Relationship ; aia:resourceOf aia:resAuthor ; aia:relationshipKind "has_many" ;
                  aia:relationshipName "books" ; aia:destination "Shelf.Library.Book" ;
                  aia:isPublic true ; aia:isRequired false ; aia:order 1 .


              # ---- Loan: multitenancy + timestamps + pagination + default sort ----
              aia:attrLoanOrg a aia:Attribute ; aia:resourceOf aia:resLoan ; aia:attributeName "org_id" ;
                  aia:attributeType "string" ; aia:isPublic true ; aia:isRequired true ; aia:order 1 .
              aia:attrLoanItem a aia:Attribute ; aia:resourceOf aia:resLoan ; aia:attributeName "item" ;
                  aia:attributeType "string" ; aia:isPublic true ; aia:isRequired true ; aia:order 2 .
              aia:tenantLoan a aia:Multitenancy ; aia:resourceOf aia:resLoan ; aia:tenantStrategy "attribute" ;
                  aia:tenantAttribute "org_id" .
              aia:tsLoan a aia:Timestamps ; aia:resourceOf aia:resLoan .
              aia:actLoanRead a aia:Action ; aia:resourceOf aia:resLoan ; aia:actionName "read" ;
                  aia:actionType "read" ; aia:accepts "" ; aia:order 1 .
              aia:primLoanRead a aia:PrimaryAction ; aia:actionOf aia:actLoanRead .
              aia:actLoanList a aia:Action ; aia:resourceOf aia:resLoan ; aia:actionName "list_loans" ;
                  aia:actionType "read" ; aia:accepts "" ; aia:order 2 .
              aia:pageLoanList a aia:Pagination ; aia:actionOf aia:actLoanList ; aia:paginationOffset true ;
                  aia:paginationKeyset false ; aia:defaultLimit 2 ; aia:countable true .
              aia:sortLoanList a aia:DefaultSort ; aia:actionOf aia:actLoanList ; aia:sortField "item" ;
                  aia:sortDirection "asc" ; aia:order 1 .
              aia:actLend a aia:Action ; aia:resourceOf aia:resLoan ; aia:actionName "lend" ;
                  aia:actionType "create" ; aia:accepts "item" ; aia:order 3 .
              """

  setup do
    on_exit(fn ->
      for m <- [@book, @author, @loan] do
        if Code.ensure_loaded?(m) and function_exported?(m, :spark_dsl_config, 0),
          do: Ash.DataLayer.Ets.stop(m)
      end
    end)

    :ok
  end

  # ------------------------------------------------------------------ (1)

  describe "action arguments, changes, validations as facts" do
    test "the compiled action lists its arguments; validation refuses; the change applies" do
      with_built(@ontology, fn built ->
        action = Ash.Resource.Info.action(@book, :register)
        assert [:notes, :author_ref] == Enum.map(action.arguments, & &1.name)
        assert Enum.all?(action.arguments, & &1.allow_nil?)

        bad =
          Ash.Changeset.for_create(@book, :register, %{title: "T", isbn: "not-an-isbn", pages: 5})

        assert {:error, %Ash.Error.Invalid{}} = Ash.create(bad)

        neg = %{title: "T", isbn: "1234567890", pages: -5}
        assert {:error, %Ash.Error.Invalid{}} = Ash.create(@book, neg, action: :register)

        missing = %{title: "T", pages: 5}
        assert {:error, %Ash.Error.Invalid{}} = Ash.create(@book, missing, action: :register)

        # state unchanged by the refused creates
        assert [] == Ash.read!(@book)

        good = %{title: "Good", isbn: "1234567890", pages: 5}
        assert {:ok, book} = Ash.create(@book, good, action: :register)
        assert book.status == "draft"
        assert [%{title: "Good", status: "draft"}] = Ash.read!(@book)

        # generated source shows the facts as structured code, never raw strings in the template
        assert built.sources[@book] =~ "validate(present(:isbn))"
        assert built.sources[@book] =~ "change(set_attribute(:status, \"draft\"))"
      end)
    end

    test "manage_relationship change relates the book to an existing author" do
      with_built(@ontology, fn _built ->
        author = Ash.Seed.seed!(@author, %{name: "Le Guin"})
        attrs = %{title: "Dispossessed", isbn: "1234567890", pages: 300, author_ref: author.id}
        assert {:ok, book} = Ash.create(@book, attrs, action: :register)
        assert book.author_id == author.id
      end)
    end

    test "FALSIFIER: dropping the validation facts lets the invalid create succeed" do
      variant =
        @ontology
        |> String.replace(~r/aia:valIsbnMatch a aia:Validation.*?aia:order 2 \./s, "")
        |> String.replace(~r/aia:valPagesCompare a aia:Validation.*?aia:order 3 \./s, "")

      refute variant =~ "valIsbnMatch"

      with_built(variant, fn _built ->
        assert {:ok, _} =
                 Ash.create(@book, %{title: "T", isbn: "not-an-isbn", pages: -5},
                   action: :register
                 )
      end)
    end

    test "NEGATIVE: a validation on a missing action is refused, typed, nothing written" do
      bad =
        @ontology <>
          """
          aia:valOrphan a aia:Validation ; aia:actionOf aia:noSuchAction ; aia:validationKind "present" ;
              aia:validationSubject "isbn" ; aia:validationOption "" ; aia:validationValue "" ;
              aia:validationValueType "string" ; aia:order 9 .
          """

      assert {output, code, false} = sync_refused(bad)
      assert code != 0
      assert output =~ "REFUSED_ASH_API_SURFACE"
      assert output =~ "DANGLING_ACTION"
    end

    test "NEGATIVE: interpolating/malformed match patterns are refused, nothing written" do
      for {label, value} <- [
            {"interpolation", ~S|#{IO.puts(:pwned_aia)}|},
            {"trailing backslash", ~S|abc\\|},
            {"newline", "a\nb"}
          ] do
        bad =
          @ontology <>
            """
            aia:valInject a aia:Validation ; aia:actionOf aia:actRegister ; aia:validationKind "match" ;
                aia:validationSubject "isbn" ; aia:validationOption "" ; aia:validationValue "#{escape_ttl(value)}" ;
                aia:validationValueType "string" ; aia:order 9 .
            """

        assert {output, code, false} = sync_refused(bad), label
        assert code != 0, label
        assert output =~ "REFUSED_ASH_API_SURFACE", label
        assert output =~ "MALFORMED_MATCH_PATTERN", label
      end
    end

    test "NEGATIVE: injected validationOption and relationship destination are refused" do
      bad_option =
        String.replace(
          @ontology,
          ~s|aia:validationOption "greater_than"|,
          ~s|aia:validationOption "greater_than, x: System.halt()"|
        )

      refute bad_option == @ontology
      assert {output, code, false} = sync_refused(bad_option)
      assert code != 0
      assert output =~ "MALFORMED_VALIDATION_OPTION"

      bad_dest =
        String.replace(
          @ontology,
          ~s|aia:destination "Shelf.Library.Author"|,
          ~s|aia:destination "Shelf.Library.Author, foo: System.halt()"|
        )

      refute bad_dest == @ontology
      assert {output, code, false} = sync_refused(bad_dest)
      assert code != 0
      assert output =~ "MALFORMED_DESTINATION"
    end

    test "NEGATIVE: an unknown validation kind and an incomplete argument are refused" do
      bad =
        @ontology <>
          """
          aia:valWeird a aia:Validation ; aia:actionOf aia:actRegister ; aia:validationKind "eval" ;
              aia:validationSubject "isbn" ; aia:validationOption "" ; aia:validationValue "" ;
              aia:validationValueType "string" ; aia:order 9 .
          aia:argHalf a aia:Argument ; aia:actionOf aia:actRegister ; aia:argumentName "half" .
          """

      assert {output, code, false} = sync_refused(bad)
      assert code != 0
      assert output =~ "UNKNOWN_VALIDATION_KIND"
      assert output =~ "INCOMPLETE_ARGUMENT"
    end
  end

  # ------------------------------------------------------------------ (5)

  describe "resource configuration as facts" do
    test "multitenancy, timestamps, pagination, default sort, primary actions" do
      with_built(@ontology, fn _built ->
        assert Ash.Resource.Info.multitenancy_strategy(@loan) == :attribute
        assert Ash.Resource.Info.multitenancy_attribute(@loan) == :org_id
        assert Ash.Resource.Info.attribute(@loan, :created_at)
        assert Ash.Resource.Info.attribute(@loan, :updated_at)

        list = Ash.Resource.Info.action(@loan, :list_loans)
        assert list.pagination.offset?
        refute list.pagination.keyset?
        assert list.pagination.default_limit == 2
        assert list.pagination.countable

        assert Ash.Resource.Info.primary_action!(@loan, :read).name == :read
        assert Ash.Resource.Info.primary_action!(@book, :read).name == :read
        assert Ash.Resource.Info.primary_action!(@author, :read)

        # tenant is required, and scopes the rows
        assert {:error, _} = Ash.create(@loan, %{item: "x"}, action: :lend)

        for item <- ["c", "a", "b"],
            do: Ash.create!(@loan, %{item: item}, action: :lend, tenant: "acme")

        Ash.create!(@loan, %{item: "other-tenant"}, action: :lend, tenant: "globex")

        page = Ash.read!(@loan, action: :list_loans, tenant: "acme", page: [count: true])
        assert page.count == 3
        assert Enum.map(page.results, & &1.item) == ["a", "b"]
        assert Enum.all?(page.results, &(&1.org_id == "acme"))
      end)
    end

    test "FALSIFIER: dropping the multitenancy fact removes the strategy" do
      variant =
        String.replace(
          @ontology,
          ~r/aia:tenantLoan a aia:Multitenancy.*?aia:tenantAttribute "org_id" \./s,
          ""
        )

      refute variant =~ "tenantLoan"

      with_built(variant, fn _built ->
        assert Ash.Resource.Info.multitenancy_strategy(@loan) == nil
      end)
    end

    test "NEGATIVE: a tenant attribute that is not a declared attribute is refused" do
      variant =
        String.replace(
          @ontology,
          ~s|aia:tenantAttribute "org_id"|,
          ~s|aia:tenantAttribute "nope"|
        )

      assert {output, code, false} = sync_refused(variant)
      assert code != 0
      assert output =~ "DANGLING_TENANT_ATTRIBUTE"
    end
  end

  # ------------------------------------------------------------------ (7)

  describe "regeneration: edit in place" do
    test "a hand-added validate line survives; a changed accepts fact is reported as drift" do
      task = render_and_compile!(@ontology)

      try do
        applied = test_project(app_name: :shelf) |> run() |> apply_igniter!()
        path = Igniter.Project.Module.proper_location(applied, @book)
        original = content(applied, path)
        assert original =~ "accept([:title, :isbn, :pages])"

        hand = "validate(string_length(:title, min: 2))"

        hand_edited =
          String.replace(
            original,
            "accept([:title, :isbn, :pages])",
            "accept([:title, :isbn, :pages])\n      #{hand}"
          )

        assert hand_edited != original

        edited =
          Igniter.update_file(applied, path, fn source ->
            Rewrite.Source.update(source, :content, hand_edited)
          end)
          |> apply_igniter!()

        # unchanged ontology: re-run is inert and the hand line stays
        rerun = run(edited)
        assert_unchanged(rerun)
        assert content(rerun, path) =~ hand

        # changed `accepts` fact: re-render + re-run
        purge(task)
        changed = String.replace(@ontology, ~s|"title,isbn,pages"|, ~s|"title,isbn"|)
        task2 = render_and_compile!(changed)

        try do
          again = run(edited)
          after_content = content(again, path)
          # hand line byte-identical (an in-place line survives regeneration)
          assert after_content =~ hand
          # add_new_action skips existing names, so the accepts change did NOT propagate...
          assert after_content =~ "accept([:title, :isbn, :pages])"
          # ...and the divergence is a typed diagnostic, not silence
          assert Enum.any?(again.warnings, &(&1 =~ "ASH_API_ACCEPT_DRIFT"))
          assert Enum.any?(again.warnings, &(&1 =~ "Book.register"))
        after
          purge(task2)
        end
      after
        purge(task)
      end
    end
  end

  # ------------------------------------------------------------------ helpers

  # Renders + compiles the task, applies it to a fresh test project, compiles the resulting
  # domain/resource sources, runs `fun`, always purges.
  defp with_built(ontology, fun) do
    task_modules = render_and_compile!(ontology)

    try do
      igniter = test_project(app_name: :shelf) |> run() |> apply_igniter!()

      sources =
        for m <- [@domain | apply(@task, :resources, [])], into: %{} do
          {m, content(igniter, Igniter.Project.Module.proper_location(igniter, m))}
        end

      dir =
        PackCompile.tmp_project!(
          for {m, src} <- sources, into: %{}, do: {"#{inspect(m)}.ex", src}
        )

      try do
        modules = PackCompile.compile!(dir)

        try do
          fun.(%{sources: sources, igniter: igniter})
        after
          for m <- apply(@task, :resources, []), do: safe_stop(m)
          purge(modules)
        end
      after
        PackCompile.cleanup(dir)
      end
    after
      purge(task_modules)
    end
  end

  # PackCompile.purge/1 calls Code.del_path/1, which does not exist on this Elixir (it is
  # Code.delete_path/1); unload and drop the tmp ebin with the real API here.
  defp purge(modules) do
    ebins =
      for m <- modules,
          path = :code.which(m),
          is_list(path),
          dir = path |> List.to_string() |> Path.dirname(),
          String.contains?(dir, "pack_compile_ebin_"),
          uniq: true,
          do: dir

    for m <- modules do
      :code.purge(m)
      :code.delete(m)
      :code.purge(m)
    end

    for dir <- ebins do
      Code.delete_path(dir)
      File.rm_rf!(dir)
    end

    :ok
  end

  defp safe_stop(m) do
    Ash.DataLayer.Ets.stop(m)
  rescue
    _ -> :ok
  catch
    _, _ -> :ok
  end

  defp render_and_compile!(ontology) do
    dir = PackCompile.tmp_project!(%{"ontology.ttl" => ontology})
    on_exit(fn -> PackCompile.cleanup(dir) end)
    # ASH_API_PACK_DIR points at another pack tree (e.g. the pre-change pack extracted with
    # `git show`) to witness these tests RED against it; unset = the shipped pack.
    pack_opts =
      case System.get_env("ASH_API_PACK_DIR") do
        nil -> []
        pack_dir -> [pack_dir: pack_dir]
      end

    rendered =
      PackCompile.render!(
        "ash-igniter-api-pack",
        [ontology: Path.join(dir, "ontology.ttl")] ++ pack_opts
      )

    on_exit(fn -> PackCompile.cleanup(rendered.out_dir) end)
    PackCompile.compile!(Enum.filter(rendered.files, &String.ends_with?(&1, ".ex")))
  end

  # Real sync subprocess expected to REFUSE: returns {output, exit_code, out_file_exists?}.
  defp escape_ttl(value) do
    value
    |> String.replace("\\", "\\\\")
    |> String.replace("\"", "\\\"")
    |> String.replace("\n", "\\n")
  end

  defp sync_refused(ontology) do
    dir = PackCompile.tmp_project!(%{"ontology.ttl" => ontology})
    on_exit(fn -> PackCompile.cleanup(dir) end)
    out = Path.join(dir, "lib/task.ex")

    {output, code} =
      System.cmd(
        "mix",
        [
          "ggen_igniter.sync",
          "--pack",
          "ash-igniter-api-pack",
          "--engine",
          "sparql",
          "--ontology",
          Path.join(dir, "ontology.ttl"),
          "--out",
          out,
          "--manifest-dir",
          dir,
          "--verify-cwd",
          File.cwd!()
        ],
        cd: File.cwd!(),
        stderr_to_stdout: true
      )

    {output, code, File.exists?(out)}
  end

  defp run(igniter) do
    parent = self()

    capture_io(:stderr, fn ->
      capture_io(fn -> send(parent, {:igniter, Igniter.compose_task(igniter, @task, [])}) end)
    end)

    receive do
      {:igniter, result} -> result
    after
      5_000 -> raise "timed out waiting for compose_task"
    end
  end

  defp content(igniter, path) do
    igniter.rewrite |> Rewrite.source!(path) |> Rewrite.Source.get(:content)
  end
end
