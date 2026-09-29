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

  test "unsupported construct is reported; exit 1 only with --fail-on-unsupported", %{dir: d} do
    args = ["--data", p(d, "good.ttl"), "--shapes", p(d, "shapes_unsupported.ttl")]

    {out, code} = shacl(args)
    assert out =~ "UNSUPPORTED"
    assert code == 0

    {out2, code2} = shacl(args ++ ["--fail-on-unsupported"])
    assert out2 =~ "UNSUPPORTED"
    assert code2 == 1
  end

  test "missing input exits 2", %{dir: d} do
    {_out, code} = shacl(["--data", p(d, "nope.ttl"), "--shapes", p(d, "shapes.ttl")])
    assert code == 2
  end
end
