defmodule GgenIgniter.SemanticJiraDescriptorShapeTest do
  @moduledoc """
  Chicago-style: real work orders, real frontier/admission via
  `Descriptor.build/4`, and the real `Shacl` loader parsing the real shape file
  from the pack. No doubles.
  """
  use ExUnit.Case, async: true

  alias GgenIgniter.{Ontology, SemanticA2A}
  alias GgenIgniter.SemanticJira.{Descriptor, Shacl}

  @sha String.duplicate("a", 40)
  @origin_authority "https://ggen-igniter.dev/ontology/semantic-jira#objective-code-work-authority"
  @attrs %{
    "graph_digest" => "sha256:" <> String.duplicate("b", 64),
    "source_digest" => "sha256:" <> String.duplicate("c", 64),
    "worker_identity" => "zcode-1",
    "verifier_identity" => "court-1"
  }

  defp wo(id) do
    %{
      "identity" => id,
      "title" => id,
      "description" => "d",
      "subject" => "subj-#{id}",
      "repository" => "o/r",
      "base_sha" => @sha,
      "standing" => "UNKNOWN",
      "evidence_ceiling" => "observed",
      "promotion_rule" => "all_courts",
      "replay_identity" => "rid-#{id}",
      "required_courts" => ["ci"],
      "required_evidence" => ["exec"],
      "acceptance" => ["a1"],
      "falsifiers" => ["f1"],
      "projections" => ["jira"],
      "origin_authority" => @origin_authority,
      "dependencies" => []
    }
  end

  @shape_path Path.join([
                "priv",
                "ggen",
                "semantic-jira-pack",
                "shapes",
                "execution-descriptor.shacl.ttl"
              ])

  describe "build/4 (worker/verifier identity)" do
    test "valid identities pass and are carried verbatim" do
      assert {:ok, d} = Descriptor.build([wo("A")], "A", @attrs)
      assert d["worker_identity"] == "zcode-1"
      assert d["verifier_identity"] == "court-1"
    end

    test "worker identity with a space is refused" do
      attrs = Map.put(@attrs, "worker_identity", "bad worker")

      assert {:error, {:refused_descriptor, {:invalid_option, :worker_identity}}} =
               Descriptor.build([wo("A")], "A", attrs)
    end

    test "verifier identity longer than 128 bytes is refused" do
      attrs = Map.put(@attrs, "verifier_identity", String.duplicate("v", 129))

      assert {:error, {:refused_descriptor, {:invalid_option, :verifier_identity}}} =
               Descriptor.build([wo("A")], "A", attrs)
    end

    test "128-byte identity passes; missing or non-string identity is refused" do
      attrs = Map.put(@attrs, "worker_identity", String.duplicate("w", 128))
      assert {:ok, _} = Descriptor.build([wo("A")], "A", attrs)

      assert {:error, {:refused_descriptor, {:invalid_option, :worker_identity}}} =
               Descriptor.build([wo("A")], "A", Map.delete(@attrs, "worker_identity"))

      assert {:error, {:refused_descriptor, {:invalid_option, :verifier_identity}}} =
               Descriptor.build([wo("A")], "A", Map.put(@attrs, "verifier_identity", 7))
    end
  end

  describe "execution-descriptor.shacl.ttl (real loader)" do
    test "shape file parses and declares the descriptor node shape" do
      shapes =
        Ontology.load!(Path.join(SemanticA2A.pack_dir(), "shapes/execution-descriptor.shacl.ttl"))

      report = Shacl.validate(RDF.Graph.new(), shapes)

      assert report.conforms
      assert Enum.any?(report.shapes_checked, &(to_string(&1) == "execution_descriptor_shape"))
    end

    test "shape rejects a descriptor node whose worker identity has a space" do
      sj = "https://ggen-igniter.dev/ontology/semantic-jira#"
      node = RDF.iri("urn:test:descriptor")

      graph =
        RDF.Graph.new([
          {node, RDF.type(), RDF.iri(sj <> "ExecutionDescriptor")},
          {node, RDF.iri(sj <> "workerIdentity"), RDF.literal("bad worker")}
        ])

      report = Shacl.validate_file(graph, Path.join(File.cwd!(), @shape_path))

      refute report.conforms
    end
  end
end
