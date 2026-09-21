defmodule GgenIgniter.CrownDescriptorCourtTest do
  @moduledoc """
  Descriptor shape courts absorbed from PRs #19/#23 (wave-9 sole-source fold).

  PR #19 (head `0d87dfe`, `gall-semantic-work-pack`) and PR #23 (head
  `d92a230`, stacked on #19) fenced a fixture execution descriptor with:
  an exact output key set, exact base-SHA / sha256 graph-digest shapes,
  work-order/checkpoint identity distinctness, and a forbidden-runtime-keys
  fence. Their branch topology predates the `c81f8dc` NIF-cache CI fix, so
  that surface cannot carry the law forward; the law is re-manufactured HERE
  against the canonical, consumer-bound descriptor
  (`GgenIgniter.Crown.descriptor/3`, the exact contract consumed by
  `Xaas.Ultracode.SemanticWork.admit/1`). This is the ONE-CANONICAL fold:
  no second descriptor surface is admitted into this repository.

  Named divergence from #23's exclusion fence: #23 forbids `standing` and
  `receipt_iri`/`receipt_digest` outright. The canonical descriptor
  deliberately carries top-level `standing` (the consumer gates admission on
  observed standing) and receipt-bound DEPENDENCY entries (upstream ALIVE
  evidence), because its consumer is the real XaaS admission, not a
  consumer-less fixture. The lawful fence here forbids the runtime-AUTHORITY
  keys (`lease`, `lease_token`, `epoch`, `epoch_id`, `worker`, `worker_id`,
  `authority`) anywhere in the descriptor, and receipt keys everywhere
  OUTSIDE dependency entries.
  """

  use ExUnit.Case, async: true

  alias GgenIgniter.Crown

  # The canonical graph carries the crown section; strip it so every test
  # exercises a fresh append onto the pre-crown baseline (same fixture
  # discipline as GgenIgniter.CrownTest; duplicated here deliberately to keep
  # this file append-only/collision-free against concurrent crown-line work).
  @ontology_path "priv/ggen/semantic-jira-pack/ontology.ttl"
  @seed_sha "b40964e70a8f87296fe7d69bad999aad02e06f19"
  @graph_digest "sha256:" <> String.duplicate("b", 64)

  @sensing_doc %{
    "schemaVersion" => "xaas-sensing/1",
    "head" => @seed_sha,
    "profile" => "failing_tests",
    "items" => [
      %{
        "id" => "fail-test-normalize-label-collapses-inner-whitespace-abc123",
        "goal" =>
          "The test suite reports this failure when sensed:\n\n" <>
            "    tests/test_w6_crown_seed.py::test_normalize_label_collapses_inner_whitespace\n\n" <>
            "Make the failing test pass WITHOUT weakening, skipping, or deleting it.",
        "allowed_paths" => ["src/eds/crown.py", "tests/test_w6_crown_seed.py"],
        "source" => %{"file" => "suite-output", "line" => nil, "text" => "FAILED"}
      }
    ]
  }

  @attrs %{
    "repository" => "local/eds",
    "base_sha" => @seed_sha,
    "replay_tag" => "crown-descriptor-court:v1"
  }

  # The exact SemanticWork.admit contract key set: the 11 fields the crown
  # test pins PLUS event-sourced `standing`. Sorted, so the assertion is an
  # exact-set fence in both directions (no key lost, no key smuggled in).
  @contract_keys ~w(
    base_sha
    checkpoint_iri
    dependencies
    execution_policy
    execution_repo_alias
    goal
    graph_digest
    provider
    repository_identity
    standing
    verifier_suite
    work_order_iri
  )

  # Runtime-authority state: manufactured downstream by the XaaS runtime and
  # NEVER projected into a descriptor (an advisory projection carries zero
  # execution authority). #23's original fence; adapted (see moduledoc).
  @forbidden_runtime_keys ~w(
    authority
    epoch
    epoch_id
    lease
    lease_token
    worker
    worker_id
  )

  setup do
    {:ok, manufactured} = Crown.manufacture(@sensing_doc, @attrs)

    base =
      @ontology_path
      |> File.read!()
      |> String.split("# ── W6-A8 crown")
      |> List.first()

    path =
      Path.join(
        System.tmp_dir!(),
        "crown-descriptor-court-#{System.unique_integer([:positive])}.ttl"
      )

    File.write!(path, Crown.append_to_graph(base, Crown.render_turtle(manufactured)))
    on_exit(fn -> File.rm(path) end)

    {:ok, work_orders} = Crown.extract_work_orders(path)

    %{
      work_orders: work_orders,
      descriptor_attrs: %{
        "goal" => "Repair observed failing condition",
        "provider" => "zcode",
        "verifier_suite" => "eds-dod",
        "execution_repo_alias" => "eds"
      }
    }
  end

  test "descriptor output is exactly the SemanticWork.admit contract key set", %{
    work_orders: work_orders,
    descriptor_attrs: attrs
  } do
    {:ok, descriptor} = Crown.descriptor(work_orders["CROWN-001"], @graph_digest, attrs)

    assert descriptor |> Map.keys() |> Enum.sort() == Enum.sort(@contract_keys)
  end

  test "exact shapes: base SHA is 40-hex, graph digest is sha256/64-hex, checkpoint is derived and distinct",
       %{
         work_orders: work_orders,
         descriptor_attrs: attrs
       } do
    {:ok, descriptor} = Crown.descriptor(work_orders["CROWN-001"], @graph_digest, attrs)

    # Exact means exact (the #23 shape court, kept verbatim in law).
    assert descriptor["base_sha"] =~ ~r/\A[0-9a-f]{40}\z/
    assert descriptor["graph_digest"] =~ ~r/\Asha256:[0-9a-f]{64}\z/

    # Work-order and checkpoint identities are distinct graph identities,
    # and the checkpoint IRI is the kernel's deterministic derivation.
    refute descriptor["work_order_iri"] == descriptor["checkpoint_iri"]
    assert descriptor["checkpoint_iri"] == descriptor["work_order_iri"] <> "/checkpoint"
  end

  test "descriptor refuses a malformed graph digest (fail-closed)", %{
    work_orders: work_orders,
    descriptor_attrs: attrs
  } do
    assert {:error, {:refused_descriptor, {:invalid_digest, "sha256:short"}}} =
             Crown.descriptor(work_orders["CROWN-001"], "sha256:short", attrs)
  end

  test "runtime-authority keys never enter the descriptor; receipt keys bind only inside dependency entries",
       %{
         work_orders: work_orders,
         descriptor_attrs: attrs
       } do
    evidence = %{
      "CROWN-001" => %{
        "receipt_iri" => "urn:xaas:ultracode:receipt:descriptor-court",
        "receipt_digest" => "sha256:" <> String.duplicate("c", 64)
      }
    }

    {:ok, descriptor} =
      Crown.descriptor(
        work_orders["CROWN-002"],
        @graph_digest,
        Map.put(attrs, "dependency_evidence", evidence)
      )

    # No runtime-authority key anywhere at the top level...
    for forbidden <- @forbidden_runtime_keys do
      refute Map.has_key?(descriptor, forbidden), "smuggled top-level key: #{forbidden}"
    end

    # ...and receipt keys appear ONLY as upstream-ALIVE bindings inside
    # dependency entries (never as top-level lease/authority state).
    assert [
             %{
               "work_order_iri" => "CROWN-001",
               "required_standing" => "ALIVE",
               "observed_standing" => "ALIVE",
               "receipt_iri" => iri,
               "receipt_digest" => digest
             }
           ] =
             descriptor["dependencies"]

    assert iri == evidence["CROWN-001"]["receipt_iri"]
    assert digest == evidence["CROWN-001"]["receipt_digest"]

    for dep <- descriptor["dependencies"] do
      for forbidden <- @forbidden_runtime_keys do
        refute Map.has_key?(dep, forbidden), "smuggled dependency key: #{forbidden}"
      end
    end
  end

  test "no-dependency descriptor projects an explicitly empty dependencies list", %{
    work_orders: work_orders,
    descriptor_attrs: attrs
  } do
    # The #19/#23 no-dependency case: absence of evidence yields an explicit
    # [], never a dropped key or a nil.
    {:ok, descriptor} = Crown.descriptor(work_orders["CROWN-001"], @graph_digest, attrs)
    assert descriptor["dependencies"] == []
  end
end
