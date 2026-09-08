defmodule BookLibrary.Catalog.BookTest do
  @moduledoc """
  Runtime behaviour of the manufactured `BookLibrary.Catalog.Book` resource.

  Nothing exercised here was hand-written. `lib/book_library/catalog/book.ex`
  is produced by the real upstream Ash generators composed by
  `mix book_library.manufacture`, and the `books` table it writes to comes from
  `priv/repo/migrations/20260908183145_book_library_manufacture.exs`. Before
  this file existed, every standing about that resource rested on compilation
  plus file-tree identity: no test had ever executed a manufactured action, so
  no row was ever written and there was no database state to be idempotent
  about.

  ## Disclosed deviation from the Ash usage rules

  Ash's usage rules prescribe exercising a resource through its domain CODE
  INTERFACE -- a `define :create_book, action: :create` entry inside the domain
  -- rather than through `Ash.create!/1` directly. This fixture's domains
  contain no `define` calls: `lib/book_library/catalog.ex` holds a bare
  `resource` entry and nothing else.

  That is a consequence of a real generator gap, not a shortcut taken here.
  `test/fixtures/ash_manufacture_pack/ontology.ttl` declares 21
  `amp:GeneratorCapability` rows and none of them emits a code interface
  (`grep -ci code_interface ontology.ttl` returns 0), so the manufacture path
  has no lawful way to produce one, and hand-writing a domain `define` into
  this fixture is exactly what `AGENTS.md` forbids. These tests therefore call
  `Ash.create!/1`, `Ash.create/1`, `Ash.read!/1` and `Ash.get!/3` directly.
  When the pack gains a code-interface capability they should move onto it.

  ## Why the helpers are local rather than shared

  `bin/day_zero.sh` deletes `test/support` wholesale on every replay and only
  `mix ash_postgres.install` puts anything back there, so a hand-written shared
  fixture module under `test/support` would not survive a qualification run.
  The construction helpers therefore live in each test file.
  """

  use BookLibrary.DataCase

  alias BookLibrary.Catalog.Book

  describe "the manufactured :create action" do
    test "writes a real row to Postgres and returns it with a generated uuid id" do
      input = create_input()

      book = Book |> Ash.Changeset.for_create(:create, input) |> Ash.create!()

      assert %Book{} = book
      assert is_binary(book.id)
      assert {:ok, _raw} = Ecto.UUID.dump(book.id)

      # Read back through the raw connection rather than through Ash, so a data
      # layer that never issued an INSERT cannot satisfy this assertion.
      # "books", "title", "isbn" and "copies_total" are upstream CONTRACT names
      # fixed by the manufactured migration, not test data.
      assert %{num_rows: 1, rows: [[title, isbn, copies_total]]} =
               Repo.query!(
                 "SELECT title, isbn, copies_total FROM books WHERE id = $1",
                 [Ecto.UUID.dump!(book.id)]
               )

      assert title == input.title
      assert isbn == input.isbn
      assert copies_total == input.copies_total
    end

    test "sets both manufactured timestamps" do
      book = create_book()

      assert %DateTime{} = book.inserted_at
      assert %DateTime{} = book.updated_at
    end

    test "rejects input missing any attribute the resource marks allow_nil? false" do
      required = required_create_fields()

      # An empty list here would make the loop below vacuously true, which is
      # the failure mode this assertion exists to catch.
      assert Enum.count(required) > 0

      for field <- required do
        input = Map.delete(create_input(), field)

        case Book |> Ash.Changeset.for_create(:create, input) |> Ash.create() do
          {:error, %Ash.Error.Invalid{errors: errors}} ->
            assert Enum.any?(errors, &required_error_for?(&1, field)),
                   "expected a real Ash validation error naming #{inspect(field)}, got: " <>
                     inspect(errors)

          other ->
            flunk(
              "dropping #{inspect(field)} was accepted by the manufactured :create " <>
                "action, so it is not validating: #{inspect(other)}"
            )
        end
      end
    end

    test "two books created in one test both persist, with distinct ids and isbns" do
      first = create_book()
      second = create_book()

      refute first.id == second.id
      refute first.isbn == second.isbn

      assert %{num_rows: 2} =
               Repo.query!("SELECT id FROM books WHERE id IN ($1, $2)", [
                 Ecto.UUID.dump!(first.id),
                 Ecto.UUID.dump!(second.id)
               ])
    end
  end

  describe "the manufactured :read action" do
    test "round-trips every accepted attribute through Postgres" do
      input = create_input()
      created = Book |> Ash.Changeset.for_create(:create, input) |> Ash.create!()

      reread = Ash.get!(Book, created.id)

      for field <- accepted_create_fields() do
        # `Map.get/2` rather than `Map.fetch!/2` on the right-hand side: Ash's
        # generator omits nilable attributes from the input map entirely, and
        # "omitted" must round-trip to a stored NULL just as an explicit value
        # must round-trip to itself.
        assert Map.fetch!(reread, field) == Map.get(input, field),
               "#{field} did not round-trip through Postgres"
      end
    end

    test "returns the persisted record from a bare read of the resource" do
      book = create_book()

      found = Enum.find(Ash.read!(Book), &(&1.id == book.id))

      assert %Book{} = found
      assert found.title == book.title
      assert found.isbn == book.isbn
      assert found.copies_total == book.copies_total
    end
  end

  # --- construction -------------------------------------------------------

  defp create_book do
    Book |> Ash.Changeset.for_create(:create, create_input()) |> Ash.create!()
  end

  # Every attribute except `isbn` is generated by `Ash.Generator` from the
  # manufactured resource's own attribute types, so the manufactured types are
  # themselves under test rather than restated as literals here.
  defp create_input do
    Book
    |> Ash.Generator.action_input(:create, %{isbn: unique_isbn()})
    |> Enum.at(0)
  end

  # `isbn` is this resource's identity-shaped attribute. The manufactured
  # resource declares no `identities` block, so nothing in Postgres would
  # currently reject a duplicate -- but a suite that leans on that absence is
  # one ontology change away from being order-dependent, so uniqueness is
  # designed in rather than assumed. `System.unique_integer/1` is unique for
  # the lifetime of the VM, which is strictly stronger than a per-process
  # `Ash.Generator.sequence/2` counter would be.
  defp unique_isbn do
    StreamData.repeatedly(fn ->
      # "978" is the real ISBN-13 GS1 prefix -- an upstream shape CONTRACT.
      # Everything after it is generated.
      unique = Integer.to_string(System.unique_integer([:positive]))
      "978" <> String.pad_leading(unique, 10, "0")
    end)
  end

  # --- derived expectations ------------------------------------------------

  # Derived from the manufactured resource rather than restated, so an ontology
  # change that narrows the accept list cannot silently narrow this test too.
  defp accepted_create_fields do
    Ash.Resource.Info.action(Book, :create).accept
  end

  defp required_create_fields do
    accept = accepted_create_fields()

    Book
    |> Ash.Resource.Info.attributes()
    |> Enum.filter(&(&1.name in accept and not &1.allow_nil? and is_nil(&1.default)))
    |> Enum.map(& &1.name)
  end

  # `Required` is what Ash raises for an omitted `allow_nil? false` attribute;
  # `InvalidAttribute` is what it raises when a value is present but uncastable.
  # Accepting either keeps the assertion about "a real validation error naming
  # this field" rather than about one particular error struct.
  defp required_error_for?(%Ash.Error.Changes.Required{field: field}, field), do: true
  defp required_error_for?(%Ash.Error.Changes.InvalidAttribute{field: field}, field), do: true
  defp required_error_for?(_error, _field), do: false
end
