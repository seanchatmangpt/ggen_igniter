defmodule GgenIgniter.SemanticJira.PackHealthTest do
  @moduledoc """
  Chicago-style proofs for `GgenIgniter.SemanticJira.PackHealth` -- the engine
  behind `mix ggen_igniter.doctor`'s always-run `semantic_jira_pack` check.

  The happy path runs against the REAL shipped pack (`priv/ggen/semantic-
  jira-pack/`): every gate query genuinely executes through the default
  engine and every template genuinely renders once per driver row.

  Every forced-failure proof copies the real pack into a fresh per-test
  scratch dir (realpath'd, uniquely named, `on_exit`-cleaned -- the same
  convention the semantic-jira pack suite uses) and breaks exactly ONE real
  component, so the fail-closed contract (`check/1` returns an honest
  `{:error, detail}` naming the component, never raises) is exercised against
  genuine breakage, not mocks.
  """

  use ExUnit.Case, async: false

  @pack_dir "priv/ggen/semantic-jira-pack"

  defp pack_copy!(tag) do
    root =
      Path.join(
        System.tmp_dir!(),
        "ggen_semantic_jira_pack_health_#{tag}_#{System.unique_integer([:positive])}"
      )

    File.rm_rf!(root)
    File.mkdir_p!(root)
    File.cp_r!(@pack_dir, Path.join(root, "semantic-jira-pack"))

    # The SUT stores/reads real paths; System.tmp_dir!() hands out /var/...
    # on macOS while the real path is /private/var/... -- canonicalize the
    # same way the pack suite's scratch_dir!/1 does.
    root = RealDir.real_dir!(root)

    on_exit(fn -> File.rm_rf!(root) end)

    Path.join(root, "semantic-jira-pack")
  end

  test "the real shipped pack is healthy: every gate executes and every template renders" do
    assert {:ok, summary} = GgenIgniter.SemanticJira.PackHealth.check(@pack_dir)
    assert summary =~ ~r/\d+ gate quer(y|ies) executed clean/
    assert summary =~ "engine oxigraph"
    assert summary =~ ~r/\d+ templates? rendered/
    # The sampling bound is DISCLOSED in the summary, never silent.
    assert summary =~ "first+last driver row sampled"
    assert summary =~ ~r/\d+ driver rows? total/

    # All three shipped templates are individually named with their
    # sampled/total row counts (siblings may add more templates -- never
    # hard-code the count).
    assert summary =~ "jira.md.eex 2/"
    assert summary =~ "prd.md.eex 2/"
    assert summary =~ "projection.md.eex 2/"
  end

  test "fail-closed: a gate that does not execute is an honest error naming the gate" do
    pack_dir = pack_copy!("broken_gate")
    broken_gate = Path.join(pack_dir, "gates/020_work_orders.rq")
    File.write!(broken_gate, "THIS IS NOT SPARQL")

    assert {:error, detail} = GgenIgniter.SemanticJira.PackHealth.check(pack_dir)
    assert detail =~ "gate work_orders ("
    assert detail =~ "failed to execute against the packaged ontology"
  end

  test "fail-closed: a template with an undefined binding is an honest error naming the template" do
    pack_dir = pack_copy!("broken_template")
    template = Path.join(pack_dir, "templates/jira.md.eex")
    File.write!(template, File.read!(template) <> "\n<%= undefined_health_probe_binding %>\n")

    assert {:error, detail} = GgenIgniter.SemanticJira.PackHealth.check(pack_dir)
    assert detail =~ "template jira.md.eex failed to render"
  end

  test "fail-closed: a missing ontology is an honest error" do
    pack_dir = pack_copy!("missing_ontology")
    File.rm!(Path.join(pack_dir, "ontology.ttl"))

    assert {:error, detail} = GgenIgniter.SemanticJira.PackHealth.check(pack_dir)
    assert detail =~ "ontology.ttl missing at #{pack_dir}"
  end

  test "fail-closed: a Turtle syntax error is an honest error, not a crash" do
    pack_dir = pack_copy!("malformed_ontology")
    File.write!(Path.join(pack_dir, "ontology.ttl"), "@prefix broken unclosed")

    assert {:error, detail} = GgenIgniter.SemanticJira.PackHealth.check(pack_dir)
    assert detail =~ "semantic-jira-pack:"
  end

  test "fail-closed: a driver query resolving to zero rows is an honest error" do
    pack_dir = pack_copy!("empty_driver")

    File.write!(
      Path.join(pack_dir, "gates/020_work_orders.rq"),
      ~s(PREFIX sj: <https://ggen-igniter.dev/ontology/semantic-jira#>\nSELECT ?id WHERE { ?id a sj:DoesNotExist }\n)
    )

    assert {:error, detail} = GgenIgniter.SemanticJira.PackHealth.check(pack_dir)
    # Whichever template sorts first is the one that reports the emptied
    # driver; the property is the honest zero-row refusal, not the name.
    assert detail =~ " failed to render"
    assert detail =~ ~s(--for-each "work_orders" driver query resolved to 0 rows)
  end

  test "fail-closed: a pack without templates is an honest error" do
    pack_dir = pack_copy!("no_templates")
    File.rm_rf!(Path.join(pack_dir, "templates"))

    assert {:error, detail} = GgenIgniter.SemanticJira.PackHealth.check(pack_dir)
    assert detail =~ "no *.eex/*.tmpl templates found in #{Path.join(pack_dir, "templates")}"
  end

  test "fail-closed: a pack without gates is an honest error" do
    pack_dir = pack_copy!("no_gates")
    File.rm_rf!(Path.join(pack_dir, "gates"))

    assert {:error, detail} = GgenIgniter.SemanticJira.PackHealth.check(pack_dir)
    assert detail =~ "no *.rq gate queries found in #{Path.join(pack_dir, "gates")}"
  end
end
