defmodule BookLibrary.Circulation.LoanTest do
  @moduledoc """
  Runtime behaviour of the manufactured `BookLibrary.Circulation.Loan`
  resource: its `belongs_to :book` relationship and its `Ash.Type.Enum`-typed
  `status` attribute, against the real `loans` table.

  `lib/book_library/circulation/loan.ex`, `lib/book_library/circulation/
  loan_status.ex` and the `loans` table's real `loans_book_id_fkey` foreign key
  in `priv/repo/migrations/20260908183145_book_library_manufacture.exs` are all
  produced by the manufacture path.

  ## Disclosed deviation 1: no domain code interface exists

  Ash's usage rules prescribe exercising a resource through its domain CODE
  INTERFACE rather than through `Ash.create!/1`. `lib/book_library/
  circulation.ex` contains no `define` calls, and no capability in
  `test/fixtures/ash_manufacture_pack/ontology.ttl` emits one
  (`grep -ci code_interface ontology.ttl` returns 0), so the manufacture path
  cannot lawfully produce one and `AGENTS.md` forbids hand-writing it. These
  tests call `Ash.create!/1`, `Ash.create/1` and `Ash.get!/3` directly. That is
  a real generator gap, recorded here rather than hidden.

  ## Disclosed deviation 2: the book must be attached by forcing book_id

  The manufactured `:create` action accepts
  `[:borrower_name, :due_on, :returned_at, :status]` and nothing else, and the
  resource declares no `manage_relationship` argument for `:book`. The
  `belongs_to :book` is nonetheless `allow_nil? false`, so a loan cannot be
  created through the public action surface at all. These tests use
  `Ash.Changeset.force_change_attribute/3` on the `:book_id` source attribute,
  which is the documented escape hatch ("Changes an attribute even if it isn't
  writable"). That is a second real gap in the manufactured surface -- a
  relationship that is required but unsettable -- not a convenience taken here.

  ## Why the helpers are local rather than shared

  `bin/day_zero.sh` deletes `test/support` wholesale on every replay, so a
  hand-written shared fixture module there would not survive a qualification
  run. Construction helpers therefore live in each test file, duplicated on
  purpose.
  """

  use BookLibrary.DataCase

  alias BookLibrary.Catalog.Book
  alias BookLibrary.Circulation.Loan
  alias BookLibrary.Circulation.LoanStatus

  describe "the manufactured belongs_to :book relationship" do
    test "persists the book_id source attribute to the real foreign key column" do
      book = create_book()

      loan = create_loan(book)

      assert loan.book_id == book.id

      # Read the foreign key straight out of Postgres: "loans", "book_id" and
      # "id" are upstream CONTRACT names fixed by the manufactured migration.
      assert %{num_rows: 1, rows: [[book_id]]} =
               Repo.query!("SELECT book_id FROM loans WHERE id = $1", [
                 Ecto.UUID.dump!(loan.id)
               ])

      assert Ecto.UUID.load!(book_id) == book.id
    end

    test "loads back the real related Book row" do
      book = create_book()
      loan = create_loan(book)

      loaded = Ash.get!(Loan, loan.id, load: [:book])

      assert %Book{} = loaded.book
      assert loaded.book.id == book.id
      assert loaded.book.title == book.title
      assert loaded.book.isbn == book.isbn
      assert loaded.book.copies_total == book.copies_total
    end

    test "rejects a loan with no book, since the relationship is allow_nil? false" do
      case Loan |> Ash.Changeset.for_create(:create, loan_input()) |> Ash.create() do
        {:error, %Ash.Error.Invalid{errors: errors}} ->
          assert Enum.any?(errors, &book_required_error?/1),
                 "expected a real Ash validation error naming the book relationship, " <>
                   "got: " <> inspect(errors)

        other ->
          flunk("a loan with no book was accepted: #{inspect(other)}")
      end
    end
  end

  describe "the manufactured Ash.Type.Enum status attribute" do
    test "accepts every value LoanStatus declares and stores it as text" do
      book = create_book()
      declared = LoanStatus.values()

      # An empty declaration list would make the loop below vacuously true.
      # Counted rather than compared against `[]` because `LoanStatus.values/0`
      # is a compile-time literal, and the type checker folds the comparison.
      assert Enum.count(declared) > 0

      for status <- declared do
        loan = create_loan(book, %{status: status})

        assert loan.status == status
        assert Ash.get!(Loan, loan.id).status == status

        # `Ash.Type.Enum`'s storage_type is `:string` and the manufactured
        # migration declares `status` as `:text`, so the stored form must be the
        # atom's string. Read raw so an Ash-side cast cannot mask a storage
        # mismatch.
        assert %{rows: [[stored]]} =
                 Repo.query!("SELECT status FROM loans WHERE id = $1", [
                   Ecto.UUID.dump!(loan.id)
                 ])

        assert stored == Atom.to_string(status)
      end
    end

    test "rejects a value LoanStatus does not declare" do
      book = create_book()
      undeclared = undeclared_status()

      refute undeclared in LoanStatus.values()

      changeset =
        Loan
        |> Ash.Changeset.for_create(:create, loan_input(%{status: undeclared}))
        |> Ash.Changeset.force_change_attribute(:book_id, book.id)

      case Ash.create(changeset) do
        {:error, %Ash.Error.Invalid{errors: errors}} ->
          assert Enum.any?(
                   errors,
                   &match?(%Ash.Error.Changes.InvalidAttribute{field: :status}, &1)
                 ),
                 "expected a real Ash cast error on :status, got: " <> inspect(errors)

        other ->
          flunk("an undeclared status #{inspect(undeclared)} was accepted: #{inspect(other)}")
      end
    end
  end

  describe "the manufactured :create action" do
    test "round-trips every accepted attribute through Postgres" do
      book = create_book()
      input = loan_input()

      created =
        Loan
        |> Ash.Changeset.for_create(:create, input)
        |> Ash.Changeset.force_change_attribute(:book_id, book.id)
        |> Ash.create!()

      reread = Ash.get!(Loan, created.id)

      for field <- accepted_create_fields() do
        # Compared against the CREATED record, not against the raw input: the
        # manufactured `returned_at` is `:utc_datetime` (second precision) while
        # Ash's generator emits `DateTime.utc_now/0` with microseconds, so the
        # cast is lossy by design and only the post-cast value is the thing
        # Postgres is supposed to preserve.
        assert Map.fetch!(reread, field) == Map.fetch!(created, field),
               "#{field} did not round-trip through Postgres"
      end

      assert %DateTime{} = reread.inserted_at
      assert %DateTime{} = reread.updated_at
    end

    test "rejects input missing any attribute the resource marks allow_nil? false" do
      book = create_book()
      required = required_create_fields()

      assert Enum.count(required) > 0

      for field <- required do
        input = Map.delete(loan_input(), field)

        changeset =
          Loan
          |> Ash.Changeset.for_create(:create, input)
          |> Ash.Changeset.force_change_attribute(:book_id, book.id)

        case Ash.create(changeset) do
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
  end

  # --- construction -------------------------------------------------------

  defp create_loan(book, overrides \\ %{}) do
    Loan
    |> Ash.Changeset.for_create(:create, loan_input(overrides))
    |> Ash.Changeset.force_change_attribute(:book_id, book.id)
    |> Ash.create!()
  end

  # Every attribute except `borrower_name` is generated by `Ash.Generator` from
  # the manufactured resource's own attribute types -- including `status`, whose
  # generator is `Ash.Type.Enum`'s own `StreamData.member_of/1` over the
  # declared values.
  defp loan_input(overrides \\ %{}) do
    generators = Map.merge(%{borrower_name: unique_borrower_name()}, overrides)

    Loan
    |> Ash.Generator.action_input(:create, generators)
    |> Enum.at(0)
  end

  defp create_book do
    Book
    |> Ash.Changeset.for_create(:create, book_input())
    |> Ash.create!()
  end

  defp book_input do
    Book
    |> Ash.Generator.action_input(:create, %{isbn: unique_isbn()})
    |> Enum.at(0)
  end

  # `borrower_name` and `isbn` are the identity-shaped attributes of their
  # resources. Neither resource declares an `identities` block today, so nothing
  # in Postgres would reject a duplicate -- but a suite that leans on that
  # absence is one ontology change away from being order-dependent, so
  # uniqueness is designed in. `System.unique_integer/1` is unique for the
  # lifetime of the VM, which is strictly stronger than a per-process
  # `Ash.Generator.sequence/2` counter would be.
  defp unique_borrower_name do
    StreamData.repeatedly(fn ->
      "borrower-" <> Integer.to_string(System.unique_integer([:positive]))
    end)
  end

  defp unique_isbn do
    StreamData.repeatedly(fn ->
      # "978" is the real ISBN-13 GS1 prefix -- an upstream shape CONTRACT.
      # Everything after it is generated.
      unique = Integer.to_string(System.unique_integer([:positive]))
      "978" <> String.pad_leading(unique, 10, "0")
    end)
  end

  # Derived, never hardcoded: any atom outside `LoanStatus.values/0` will do,
  # and `System.unique_integer/1` guarantees this one was never declared.
  defp undeclared_status do
    :"undeclared_status_#{System.unique_integer([:positive])}"
  end

  # --- derived expectations ------------------------------------------------

  defp accepted_create_fields do
    Ash.Resource.Info.action(Loan, :create).accept
  end

  defp required_create_fields do
    accept = accepted_create_fields()

    Loan
    |> Ash.Resource.Info.attributes()
    |> Enum.filter(&(&1.name in accept and not &1.allow_nil? and is_nil(&1.default)))
    |> Enum.map(& &1.name)
  end

  defp required_error_for?(%Ash.Error.Changes.Required{field: field}, field), do: true
  defp required_error_for?(%Ash.Error.Changes.InvalidAttribute{field: field}, field), do: true
  defp required_error_for?(_error, _field), do: false

  # The manufactured create action neither accepts `:book_id` nor declares a
  # `manage_relationship` argument for `:book`, so Ash reports the missing
  # required belongs_to on the source attribute. Accepting either name keeps
  # this an assertion about the relationship being required rather than about
  # which of the two Ash happens to name.
  defp book_required_error?(%Ash.Error.Changes.Required{field: field}),
    do: field in [:book, :book_id]

  defp book_required_error?(_error), do: false
end
