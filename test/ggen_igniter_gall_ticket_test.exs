defmodule GgenIgniter.GallTicketTest do
  @moduledoc """
  Rendering-path proof for `GgenIgniter.GallTicket` (v26.9.18 PRD §43.4 + §42
  + §53) over the real `test/fixtures/gall_work/checkpoint-001.ttl` document:

    * the checkpoint resolves by IRI and renders through the real pack
      template (real Turtle parsing, real SPARQL, real EEx -- no mocks);
    * the provenance footer carries the real sha256 of the canonical input
      TTL bytes plus the pack identity, and the no-hand-edit marker is
      present;
    * determinism: rendering the same checkpoint twice is byte-identical
      (`Render(TTL)_1 = Render(TTL)_2`), including stable list ordering;
    * malformed documents produce TYPED `{:refused, reason}` tuples --
      missing standing, doubled standing, ambiguous single-valued slot,
      unknown checkpoint IRI, unsafe IRI, unreadable source -- never a
      silently defaulted ticket.
  """

  use ExUnit.Case, async: true

  @fixture_dir Path.join([__DIR__, "fixtures", "gall_work"])
  @fixture Path.join(@fixture_dir, "checkpoint-001.ttl")
  @checkpoint_iri "urn:gall:checkpoint:ggen_igniter:ticket-001"

  describe "rendering the complete fixture checkpoint" do
    setup do
      [rendered: render!(@fixture, @checkpoint_iri)]
    end

    test "renders every required ticket section", %{rendered: rendered} do
      for section <- [
            "# Work ticket:",
            "## Identity",
            "## Repository + base SHA",
            "## Goal",
            "## Dependencies",
            "## Allowed paths",
            "## Requires / forbids capabilities",
            "## Acceptance criteria",
            "## Falsifiers",
            "## Verifier",
            "## Standing",
            "## Provenance"
          ] do
        assert rendered =~ section, "rendered ticket missing #{inspect(section)}"
      end
    end

    test "carries the fixture's real identity, repository, base SHA and standing", %{
      rendered: rendered
    } do
      assert rendered =~ "`#{@checkpoint_iri}`"
      assert rendered =~ "Type: CodingCheckpoint"
      assert rendered =~ "<urn:repo:seanchatmangpt:ggen_igniter>"
      assert rendered =~ "`d018ed4b407b6e3d0ed747e7076fe55f0c254804`"
      assert rendered =~ "UNKNOWN"
    end

    test "renders capabilities, verifier, dependencies and multi-valued slots", %{
      rendered: rendered
    } do
      assert rendered =~ "- Read"
      assert rendered =~ "- Edit"
      assert rendered =~ "- Commit"
      assert rendered =~ "- Push"
      assert rendered =~ "- Publish"

      # requires/forbids are distinct sections' content: Push/Publish are
      # forbidden, never required.
      refute section_between(rendered, "Requires:", "Forbids:") =~ "- Push"
      assert section_between(rendered, "Forbids:", "## Acceptance") =~ "- Push"

      assert rendered =~ "`mix test test/ggen_igniter_gall_work_pack_test.exs"
      assert rendered =~ "Chicago court"

      assert rendered =~
               "`urn:gall:checkpoint:ggen_igniter:ontology-001` — gall checkpoint vocabulary admitted"

      assert rendered =~ "priv/ggen/gall_work/**"
      assert rendered =~ "byte differing between the two renders falsifies the determinism claim"
      assert rendered =~ "embeds the source graph digest and pack identity"
    end

    test "capability lines are lexicographically sorted (deterministic output)" do
      rendered = render!(@fixture, @checkpoint_iri)

      requires_section = section_between(rendered, "Requires:", "Forbids:")

      assert section_lines(requires_section) == ["- Commit", "- Edit", "- Read"]
    end

    test "embeds the provenance footer: real source digest + pack identity", %{rendered: rendered} do
      expected_digest = GgenIgniter.Digest.sha256(File.read!(@fixture))

      assert rendered =~ "Source graph digest: `#{expected_digest}`"
      assert rendered =~ "Pack: `gall_work`"
      assert rendered =~ "https://semantic-a2a.dev/gall#"

      # The digest is the real sha256 of the canonical input TTL bytes.
      assert String.starts_with?(expected_digest, "sha256:")
    end

    test "carries the generated-file / no-hand-edit marker", %{rendered: rendered} do
      assert rendered =~ "GENERATED FILE"
      assert rendered =~ "edit the ontology"
      assert rendered =~ "not this file"
    end
  end

  describe "determinism (PRD §53): Render(TTL)_1 = Render(TTL)_2" do
    test "rendering the same checkpoint twice is byte-identical" do
      first = render!(@fixture, @checkpoint_iri)
      second = render!(@fixture, @checkpoint_iri)

      assert first == second
      assert byte_size(first) == byte_size(second)
    end

    test "the embedded provenance digest is stable across renders" do
      first = render!(@fixture, @checkpoint_iri)
      second = render!(@fixture, @checkpoint_iri)

      assert extract_digest(first) == extract_digest(second)
      assert extract_digest(first) == GgenIgniter.Digest.sha256(File.read!(@fixture))
    end
  end

  describe "typed refusals for malformed input" do
    test "a checkpoint with no gall:standing is refused as {:missing_standing, iri}" do
      path = Path.join(@fixture_dir, "checkpoint-missing-standing.ttl")

      assert {:refused, {:missing_standing, @checkpoint_iri}} =
               GgenIgniter.GallTicket.render_ticket(path, @checkpoint_iri)
    end

    test "a checkpoint with two standings is refused as {:ambiguous_standing, iri, standings}" do
      path = Path.join(@fixture_dir, "checkpoint-ambiguous-standing.ttl")

      assert {:refused, {:ambiguous_standing, @checkpoint_iri, standings}} =
               GgenIgniter.GallTicket.render_ticket(path, @checkpoint_iri)

      assert Enum.sort(standings) == [
               "https://semantic-a2a.dev/gall#ALIVE",
               "https://semantic-a2a.dev/gall#UNKNOWN"
             ]
    end

    test "a doubled single-valued slot is refused, never silently pruned" do
      path = Path.join(@fixture_dir, "checkpoint-ambiguous-goal.ttl")

      assert {:refused, {:ambiguous_slot, :goal, @checkpoint_iri, values}} =
               GgenIgniter.GallTicket.render_ticket(path, @checkpoint_iri)

      assert Enum.sort(values) == ["First goal.", "Second goal."]
    end

    test "an IRI absent from the graph is refused as {:unknown_checkpoint, iri}" do
      assert {:refused, {:unknown_checkpoint, "urn:gall:checkpoint:nowhere"}} =
               GgenIgniter.GallTicket.render_ticket(@fixture, "urn:gall:checkpoint:nowhere")
    end

    test "an IRI with a '>' cannot smuggle into the SPARQL and is refused" do
      assert {:refused, {:invalid_iri, "urn:evil> ?v ?w . <urn:x"}} =
               GgenIgniter.GallTicket.render_ticket(@fixture, "urn:evil> ?v ?w . <urn:x")
    end

    test "an unreadable source document is refused with the path and reason" do
      assert {:refused, {:source_unreadable, path, :enoent}} =
               GgenIgniter.GallTicket.render_ticket(
                 Path.join(@fixture_dir, "no-such-document.ttl"),
                 @checkpoint_iri
               )

      assert path =~ "no-such-document.ttl"
    end

    test "a subject that exists but is not a checkpoint is refused with its types" do
      assert {:refused, {:not_a_checkpoint, "https://semantic-a2a.dev/gall#ChicagoCourt", types}} =
               GgenIgniter.GallTicket.render_ticket(
                 @fixture,
                 "https://semantic-a2a.dev/gall#ChicagoCourt"
               )

      assert types == ["https://semantic-a2a.dev/gall#Verifier"]
    end
  end

  # ── helpers ────────────────────────────────────────────────────────────────

  defp render!(path, iri) do
    assert {:ok, rendered} = GgenIgniter.GallTicket.render_ticket(path, iri)
    rendered
  end

  defp extract_digest(rendered) do
    case Regex.run(~r/Source graph digest: `([^`]+)`/, rendered) do
      [_, digest] -> digest
      nil -> flunk("no provenance digest in rendered ticket")
    end
  end

  defp section_between(rendered, from, to) do
    rendered
    |> String.split(from, parts: 2)
    |> List.last()
    |> String.split(to, parts: 2)
    |> List.first()
  end

  defp section_lines(section) do
    section
    |> String.split("\n")
    |> Enum.filter(&String.starts_with?(&1, "- "))
  end
end
