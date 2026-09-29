defmodule GgenIgniter.ShaclTaskTest do
  @moduledoc """
  Chicago-style, no-mocks proof of `mix ggen_igniter.shacl` on a tiny non-sj
  ontology: real Turtle files in a tmp dir, real `mix` subprocess, assertions on
  stdout/JSON content and exit codes (conforming, violating, unsupported).
  """
  use ExUnit.Case, async: false

  @moduletag :integration

  @shapes """
  @prefix sh: <http://www.w3.org/ns/shacl#> .
  @prefix ex: <http://example.org/> .
  ex:PersonShape a sh:NodeShape ;
    sh:targetClass ex:Person ;
    sh:property [ sh:path ex:name ; sh:minCount 1 ] .
  """

  @shapes_unsupported """
  @prefix sh: <http://www.w3.org/ns/shacl#> .
  @prefix ex: <http://example.org/> .
  ex:ColorShape a sh:NodeShape ;
    sh:targetClass ex:Thing ;
    sh:property [ sh:path ex:color ; sh:in ( "red" "blue" ) ] .
  """

  setup do
    dir = Path.join(System.tmp_dir!(), "shacl_task_#{System.unique_integer([:positive])}")
    File.mkdir_p!(dir)
    on_exit(fn -> File.rm_rf!(dir) end)

    File.write!(Path.join(dir, "shapes.ttl"), @shapes)
    File.write!(Path.join(dir, "shapes_unsupported.ttl"), @shapes_unsupported)

    File.write!(Path.join(dir, "good.ttl"), """
    @prefix ex: <http://example.org/> .
    ex:alice a ex:Person ; ex:name "Alice" .
    ex:box a ex:Thing ; ex:color "red" .
    """)

    File.write!(Path.join(dir, "bad.ttl"), """
    @prefix ex: <http://example.org/> .
    ex:bob a ex:Person .
    """)

    {:ok, dir: dir}
  end

  defp shacl(args), do: System.cmd("mix", ["ggen_igniter.shacl" | args], stderr_to_stdout: false)
  defp shacl2(args), do: System.cmd("mix", ["ggen_igniter.shacl" | args], stderr_to_stdout: true)

  defp json_doc(out) do
    out
    |> String.split("\n", trim: true)
    |> Enum.filter(&String.starts_with?(&1, "{"))
    |> List.last()
    |> Jason.decode!()
  end

  defp p(dir, f), do: Path.join(dir, f)

  test "conforming data exits 0", %{dir: d} do
    {out, code} = shacl(["--data", p(d, "good.ttl"), "--shapes", p(d, "shapes.ttl")])
    assert code == 0
    assert out =~ "CONFORMS"
  end

  test "violating instance exits 1 naming shape and focus node", %{dir: d} do
    {out, code} = shacl(["--data", p(d, "bad.ttl"), "--shapes", p(d, "shapes.ttl")])
    assert code == 1
    assert out =~ "person_shape"
    assert out =~ "http://example.org/bob"

    {json, 1} = shacl(["--data", p(d, "bad.ttl"), "--shapes", p(d, "shapes.ttl"), "--json"])
    doc = json |> String.split("\n", trim: true) |> List.last() |> Jason.decode!()
    assert doc["conforms"] == false

    assert [%{"focus_node" => "http://example.org/bob", "shape" => "person_shape"}] =
             doc["violations"]
  end

  test "unsupported construct fails closed by default; --allow-unsupported restores exit 0", %{
    dir: d
  } do
    args = ["--data", p(d, "good.ttl"), "--shapes", p(d, "shapes_unsupported.ttl")]

    {out, code} = shacl2(args)
    assert out =~ "UNSUPPORTED"
    assert out =~ "failing closed"
    assert code == 1

    {out2, code2} = shacl2(args ++ ["--allow-unsupported"])
    assert out2 =~ "UNSUPPORTED"
    assert code2 == 0

    {out3, code3} = shacl2(args ++ ["--fail-on-unsupported"])
    assert code3 == 1
    assert out3 =~ "deprecated"
  end

  test "JSON exit_code always equals the process exit code", %{dir: d} do
    args = ["--data", p(d, "good.ttl"), "--shapes", p(d, "shapes_unsupported.ttl"), "--json"]
    {out, code} = shacl2(args)
    assert code == 1
    assert json_doc(out)["exit_code"] == 1
    {out2, code2} = shacl2(args ++ ["--allow-unsupported"])
    assert code2 == 0
    assert json_doc(out2)["exit_code"] == 0
  end

  test "S1: empty shapes file is refused (exit 2), human and json", %{dir: d} do
    File.write!(p(d, "empty.ttl"), "")
    args = ["--data", p(d, "good.ttl"), "--shapes", p(d, "empty.ttl")]
    {out, code} = shacl2(args)
    assert code == 2
    assert out =~ "no SHACL shapes found in #{p(d, "empty.ttl")}"
    refute out =~ "CONFORMS"

    {jout, jcode} = shacl2(args ++ ["--json"])
    assert jcode == 2
    doc = json_doc(jout)
    assert doc["error"] =~ "no SHACL shapes found"
    assert doc["exit_code"] == 2
  end

  test "S1: swapped --data/--shapes is refused", %{dir: d} do
    {out, code} = shacl2(["--data", p(d, "shapes.ttl"), "--shapes", p(d, "good.ttl")])
    assert code == 2
    assert out =~ "no SHACL shapes found"
  end

  test "S1: zero focus nodes warns on stderr but exits 0", %{dir: d} do
    File.write!(p(d, "other.ttl"), "@prefix ex: <http://example.org/> .\nex:z a ex:Other .\n")
    {out, code} = shacl2(["--data", p(d, "other.ttl"), "--shapes", p(d, "shapes.ttl")])
    assert code == 0
    assert out =~ "0 focus nodes validated"
  end

  test "S2: unknown extension is refused with the supported list", %{dir: d} do
    File.cp!(p(d, "good.ttl"), p(d, "good.xyz"))
    {out, code} = shacl2(["--data", p(d, "good.xyz"), "--shapes", p(d, "shapes.ttl")])
    assert code == 2
    assert out =~ ".xyz"
    assert out =~ ".ttl"
    assert out =~ ".nt"
    assert out =~ ".nq"
  end

  test ".nq dataset input is validated (no FunctionClauseError)", %{dir: d} do
    File.write!(
      p(d, "bad.nq"),
      "<http://example.org/bob> <http://www.w3.org/1999/02/22-rdf-syntax-ns#type> <http://example.org/Person> <http://example.org/g> .\n"
    )

    {out, code} = shacl2(["--data", p(d, "bad.nq"), "--shapes", p(d, "shapes.ttl")])
    refute out =~ "FunctionClauseError"
    assert code == 1
    assert out =~ "http://example.org/bob"
  end

  test "missing input exits 2", %{dir: d} do
    {_out, code} = shacl(["--data", p(d, "nope.ttl"), "--shapes", p(d, "shapes.ttl")])
    assert code == 2
  end
end
