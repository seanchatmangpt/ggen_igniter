defmodule GgenIgniter.SemanticWorkOrderTest do
  @moduledoc "Chicago tests over real Turtle files and exact package bytes."
  use ExUnit.Case, async: true

  alias GgenIgniter.{Digest, SemanticWorkOrder}

  setup do
    dir =
      Path.join(
        System.tmp_dir!(),
        "semantic_work_order_#{System.unique_integer([:positive, :monotonic])}"
      )

    File.mkdir_p!(dir)
    on_exit(fn -> File.rm_rf!(dir) end)
    %{dir: dir}
  end

  defp write_work_order!(dir, name \\ "GALL-002") do
    ttl =
      "@prefix schema: <https://schema.org/> .\n<urn:gall:002> a schema:Action ; schema:name \"#{name}\" .\n"

    File.write!(Path.join(dir, SemanticWorkOrder.default_path()), ttl)
    ttl
  end

  test "execution package is deterministic across artifact enumeration order", %{dir: dir} do
    ttl = write_work_order!(dir)
    a = %{id: "a", digest: Digest.sha256("A"), kind: "source"}
    b = %{id: "b", digest: Digest.sha256("B"), kind: "generated"}

    first = SemanticWorkOrder.execution_package(dir, [b, a])
    second = SemanticWorkOrder.execution_package(dir, [a, b])

    assert first.package_digest == second.package_digest
    assert first.work_order.source_digest == Digest.sha256(ttl)
    assert :ok = SemanticWorkOrder.verify_execution_package(dir, first)
  end

  test "work-order mutation invalidates a previously manufactured package", %{dir: dir} do
    write_work_order!(dir)

    package =
      SemanticWorkOrder.execution_package(dir, [
        %{id: "artifact", digest: Digest.sha256("bytes"), kind: "generated"}
      ])

    write_work_order!(dir, "GALL-002 changed")

    assert {:error, :work_order_drift} =
             SemanticWorkOrder.verify_execution_package(dir, package)
  end

  test "malformed Turtle is refused before package identity is minted", %{dir: dir} do
    File.write!(Path.join(dir, SemanticWorkOrder.default_path()), "this is not turtle {{{")

    assert_raise RuntimeError, fn ->
      SemanticWorkOrder.execution_package(dir, [])
    end
  end
end
