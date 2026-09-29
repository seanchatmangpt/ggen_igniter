defmodule GgenIgniter.AshAggregatesInterfacesTest do
  @moduledoc """
  Chicago-style: renders `priv/ggen/ash-igniter-api-pack` from a consumer ontology carrying
  `aia:Aggregate` and `aia:CodeInterface` facts with a REAL `mix ggen_igniter.sync` subprocess,
  runs the rendered task against a real `Igniter.Test.test_project/1`, compiles the resulting
  domain/resource sources with the real compiler and asserts on real Ash state on the ETS data
  layer: `Ash.load!/2` returns count/sum/first/list (with filter) over two seeded children
  (`Ash.Seed.seed!/2`), and `Domain.register_book!/1` is callable and returns the struct.

  There is no aggregate helper in `Ash.Resource.Igniter`, so the template adds the `aggregates`
  block through `Ash.Resource.Igniter.add_block/4` behind a name guard; the second run of the task
  is asserted inert (`assert_unchanged`).

  Falsifiers: pointing an aggregate at a different (real, empty) relationship changes the loaded
  value; removing the code-interface fact makes the function raise `UndefinedFunctionError`;
  an aggregate over an undeclared relationship is REFUSED (typed, non-zero exit, no file).
  No doubles, no mocks.
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

              aia:extBook a aia:Extension ; aia:resourceOf aia:resBook ; aia:extensionName "ets" ; aia:order 1 .
              aia:extAuthor a aia:Extension ; aia:resourceOf aia:resAuthor ; aia:extensionName "ets" ; aia:order 1 .

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


              aia:relAuthor a aia:Relationship ; aia:resourceOf aia:resBook ; aia:relationshipKind "belongs_to" ;
                  aia:relationshipName "author" ; aia:destination "Shelf.Library.Author" ;
                  aia:isPublic true ; aia:isRequired false ; aia:order 1 .
              aia:idIsbn a aia:Identity ; aia:resourceOf aia:resBook ; aia:identityName "unique_isbn" ;
                  aia:identityKeys "isbn" ; aia:order 1 .

              aia:ciRegister a aia:CodeInterface ; aia:resourceOf aia:resBook ; aia:interfaceName "register_book" ;
                  aia:interfaceAction "register" ; aia:order 1 .

              aia:ciRegister a aia:CodeInterface ; aia:resourceOf aia:resBook ; aia:interfaceName "register_book" ;
                  aia:interfaceAction "register" ; aia:order 1 .

              # ---- Author ----
              aia:attrAuthorName a aia:Attribute ; aia:resourceOf aia:resAuthor ; aia:attributeName "name" ;
                  aia:attributeType "string" ; aia:isPublic true ; aia:isRequired true ; aia:order 1 .
              aia:actEnroll a aia:Action ; aia:resourceOf aia:resAuthor ; aia:actionName "enroll" ;
                  aia:actionType "create" ; aia:accepts "name" ; aia:order 1 .
              aia:ensureAuthorRead a aia:EnsurePrimary ; aia:resourceOf aia:resAuthor ; aia:actionType "read" .
              aia:relBooks a aia:Relationship ; aia:resourceOf aia:resAuthor ; aia:relationshipKind "has_many" ;
                  aia:relationshipName "books" ; aia:destination "Shelf.Library.Book" ;
                  aia:isPublic true ; aia:isRequired false ; aia:order 1 .

              aia:aggCount a aia:Aggregate ; aia:resourceOf aia:resAuthor ; aia:aggregateKind "count" ;
                  aia:aggregateName "book_count" ; aia:aggregateRelationship "books" ; aia:aggregateField "" ;
                  aia:aggregateFilter "" ; aia:aggregateSort "" ; aia:order 1 .
              aia:aggSum a aia:Aggregate ; aia:resourceOf aia:resAuthor ; aia:aggregateKind "sum" ;
                  aia:aggregateName "pages_total" ; aia:aggregateRelationship "books" ; aia:aggregateField "pages" ;
                  aia:aggregateFilter "" ; aia:aggregateSort "" ; aia:order 2 .
              aia:aggFirst a aia:Aggregate ; aia:resourceOf aia:resAuthor ; aia:aggregateKind "first" ;
                  aia:aggregateName "first_title" ; aia:aggregateRelationship "books" ; aia:aggregateField "title" ;
                  aia:aggregateFilter "" ; aia:aggregateSort "title:asc" ; aia:order 3 .
              aia:aggList a aia:Aggregate ; aia:resourceOf aia:resAuthor ; aia:aggregateKind "list" ;
                  aia:aggregateName "titles" ; aia:aggregateRelationship "books" ; aia:aggregateField "title" ;
                  aia:aggregateFilter "" ; aia:aggregateSort "title:asc" ; aia:order 4 .
              aia:aggLong a aia:Aggregate ; aia:resourceOf aia:resAuthor ; aia:aggregateKind "count" ;
                  aia:aggregateName "long_book_count" ; aia:aggregateRelationship "books" ; aia:aggregateField "" ;
                  aia:aggregateFilter "pages > 100" ; aia:aggregateSort "" ; aia:order 5 .

              """

  setup do
    on_exit(fn ->
      for m <- [@book, @author] do
        if Code.ensure_loaded?(m) and function_exported?(m, :spark_dsl_config, 0),
          do: Ash.DataLayer.Ets.stop(m)
      end
    end)

    :ok
  end

  # ------------------------------------------------------------------ (2)

  describe "aggregates" do
    test "count/sum/first/list (with filter) load the right values from two seeded children" do
      with_built(@ontology, fn _built ->
        author = Ash.Seed.seed!(@author, %{name: "A"})
        Ash.Seed.seed!(@book, %{title: "B-short", pages: 50, author_id: author.id})
        Ash.Seed.seed!(@book, %{title: "A-long", pages: 150, author_id: author.id})

        loaded =
          Ash.load!(author, [:book_count, :pages_total, :first_title, :titles, :long_book_count])

        assert loaded.book_count == 2
        assert loaded.pages_total == 200
        assert loaded.first_title == "A-long"
        assert loaded.titles == ["A-long", "B-short"]
        assert loaded.long_book_count == 1
      end)
    end

    test "FALSIFIER: pointing the aggregate at a wrong (real, empty) relationship changes the value" do
      # Author also has_many Aliases (a real relationship holding zero rows)
      variant =
        String.replace(
          @ontology,
          ~s|aia:aggregateName "book_count" ; aia:aggregateRelationship "books"|,
          ~s|aia:aggregateName "book_count" ; aia:aggregateRelationship "aliases"|
        ) <>
          """
          aia:resAlias a aia:Resource ; aia:resourceModule "Shelf.Library.Alias" ; aia:domainModule "Shelf.Library" ; aia:order 4 .
          aia:extAlias a aia:Extension ; aia:resourceOf aia:resAlias ; aia:extensionName "ets" ; aia:order 1 .
          aia:attrAliasAuthor a aia:Attribute ; aia:resourceOf aia:resAlias ; aia:attributeName "author_id" ;
              aia:attributeType "uuid" ; aia:isPublic true ; aia:isRequired false ; aia:order 1 .
          aia:actAliasRead a aia:Action ; aia:resourceOf aia:resAlias ; aia:actionName "read" ;
              aia:actionType "read" ; aia:accepts "" ; aia:order 1 .
          aia:primAliasRead a aia:PrimaryAction ; aia:actionOf aia:actAliasRead .
          aia:relAliases a aia:Relationship ; aia:resourceOf aia:resAuthor ; aia:relationshipKind "has_many" ;
              aia:relationshipName "aliases" ; aia:destination "Shelf.Library.Alias" ;
              aia:isPublic true ; aia:isRequired false ; aia:order 2 .
          """

      with_built(variant, fn _built ->
        author = Ash.Seed.seed!(@author, %{name: "A"})
        Ash.Seed.seed!(@book, %{title: "x", pages: 50, author_id: author.id})
        Ash.Seed.seed!(@book, %{title: "y", pages: 150, author_id: author.id})
        assert Ash.load!(author, :book_count).book_count == 0
        # the un-mutated relationship still sees both rows
        assert Ash.load!(author, :titles).titles == ["x", "y"]
      end)
    end

    test "NEGATIVE: an aggregate over an undeclared relationship is refused, nothing written" do
      variant =
        String.replace(
          @ontology,
          ~s|aia:aggregateName "book_count" ; aia:aggregateRelationship "books"|,
          ~s|aia:aggregateName "book_count" ; aia:aggregateRelationship "ghosts"|
        )

      assert {output, code, false} = sync_refused(variant)
      assert code != 0
      assert output =~ "DANGLING_AGGREGATE_RELATIONSHIP"
    end

    test "NEGATIVE: injected aggregate filter, sort and field are refused, nothing written" do
      for {from, to, code_name} <- [
            {~s|aia:aggregateFilter "pages > 100"|,
             ~s|aia:aggregateFilter "pages > 100) and System.halt() or (1"|,
             "MALFORMED_AGGREGATE_FILTER"},
            {~s|aia:aggregateSort "title:asc" ; aia:order 3|,
             ~s|aia:aggregateSort "title:asc, x: System.halt()" ; aia:order 3|,
             "MALFORMED_AGGREGATE_SORT"},
            {~s|aia:aggregateField "pages"|, ~s|aia:aggregateField "pages, System.halt()"|,
             "MALFORMED_AGGREGATE_FIELD"}
          ] do
        variant = String.replace(@ontology, from, to)
        refute variant == @ontology, code_name
        assert {output, code, false} = sync_refused(variant), code_name
        assert code != 0, code_name
        assert output =~ "REFUSED_ASH_API_SURFACE", code_name
        assert output =~ code_name
      end
    end

    test "idempotent: a second run of the aggregate-bearing task changes nothing" do
      task = render_and_compile!(@ontology)

      try do
        applied = test_project(app_name: :shelf) |> run() |> apply_igniter!()
        second = run(applied)
        assert_unchanged(second)
        assert second.issues == []
        assert second.warnings == [], "warnings: #{inspect(second.warnings)}"
      after
        purge(task)
      end
    end
  end

  # ------------------------------------------------------------------ (3)

  describe "code interfaces on the domain" do
    test "Domain.register_book!/1 is callable and returns the struct" do
      with_built(@ontology, fn built ->
        assert built.sources[@domain] =~ "define(:register_book, action: :register)"
        book = @domain.register_book!(%{title: "Via", isbn: "1234567890", pages: 9})
        assert %{__struct__: @book, title: "Via"} = book
      end)
    end

    test "FALSIFIER: removing the code-interface fact leaves the function undefined" do
      variant =
        String.replace(@ontology, ~r/aia:ciRegister a aia:CodeInterface.*?aia:order 1 \./s, "")

      refute variant =~ "ciRegister"

      with_built(variant, fn _built ->
        assert_raise UndefinedFunctionError, fn ->
          apply(@domain, :register_book!, [%{title: "x", isbn: "1234567890", pages: 1}])
        end
      end)
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
