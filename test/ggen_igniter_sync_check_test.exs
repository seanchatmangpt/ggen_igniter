defmodule GgenIgniter.SyncCheckTest do
  @moduledoc """
  Chicago-style: every case runs the real `mix ggen_igniter.sync` as a subprocess against a
  real tmp project directory (real ontology copy, real generated file, real manifest) and
  asserts on final state -- exit code, output text, and a before/after directory hash. No
  doubles. `--verify-cwd` points the pipeline's real `:verify` compile at this checkout.
  """
  use ExUnit.Case, async: false

  @moduletag :integration
  @moduletag timeout: 600_000

  @ontology_src "test/fixtures/audit_trail_ontology.ttl"

  setup do
    root =
      Path.join(System.tmp_dir!(), "ggen_sync_check_#{System.unique_integer([:positive])}")

    File.rm_rf!(root)
    File.mkdir_p!(Path.join(root, "out"))
    on_exit(fn -> File.rm_rf!(root) end)

    ontology = Path.join(root, "ontology.ttl")
    File.cp!(@ontology_src, ontology)
    out = Path.join([root, "out", "resource.ex"])
    {:ok, root: root, ontology: ontology, out: out}
  end

  defp args(ctx, extra) do
    [
      "ggen_igniter.sync",
      "--ontology",
      ctx.ontology,
      "--query",
      "spec=test/fixtures/spec.rq",
      "--query",
      "sections=test/fixtures/sections.rq",
      "--query",
      "entities=test/fixtures/entities.rq",
      "--query",
      "fields=test/fixtures/fields.rq",
      "--template",
      "test/fixtures/extension.ex.eex",
      "--out",
      ctx.out,
      "--manifest-dir",
      ctx.root,
      "--verify-cwd",
      File.cwd!()
    ] ++ extra
  end

  defp sync(ctx, extra),
    do: System.cmd("mix", args(ctx, extra), cd: File.cwd!(), stderr_to_stdout: true)

  # Sorted {relative path, sha256} of every regular file under `dir`, ignoring the
  # ontology source (which the test itself mutates on purpose).
  defp tree_hash(dir) do
    dir
    |> Path.join("**")
    |> Path.wildcard(match_dot: true)
    |> Enum.filter(&File.regular?/1)
    |> Enum.map(fn f ->
      {Path.relative_to(f, dir), :crypto.hash(:sha256, File.read!(f)) |> Base.encode16()}
    end)
    |> Enum.sort()
  end

  defp mutate_ontology!(ctx) do
    src = File.read!(ctx.ontology)
    assert src =~ ~s(aex:packageName "audit_trail")

    File.write!(
      ctx.ontology,
      String.replace(
        src,
        ~s(aex:packageName "audit_trail"),
        ~s(aex:packageName "audit_trail_drifted")
      )
    )

    src
  end

  test "clean -> 0, drift -> 4 with the drifted path and zero writes, revert -> 0", ctx do
    # Real sync first so the generated file + manifest exist and match the ontology.
    {out, 0} = sync(ctx, [])
    assert File.exists?(ctx.out), out

    {out, code} = sync(ctx, ["--check"])
    assert code == 0, out
    assert out =~ "clean"

    original = mutate_ontology!(ctx)

    before =
      tree_hash(Path.join(ctx.root, "out")) ++ tree_hash(Path.join(ctx.root, ".ggen_igniter"))

    {out, code} = sync(ctx, ["--check"])
    assert code == 4, out
    assert out =~ "DRIFT"
    assert out =~ ctx.out

    after_hash =
      tree_hash(Path.join(ctx.root, "out")) ++ tree_hash(Path.join(ctx.root, ".ggen_igniter"))

    assert after_hash == before, "--check wrote to the project tree"

    File.write!(ctx.ontology, original)
    {out, code} = sync(ctx, ["--check"])
    assert code == 0, out
  end

  test "a missing generated file is drift too (exit 4)", ctx do
    {out, code} = sync(ctx, ["--check"])
    assert code == 4, out
    assert out =~ ctx.out
    refute File.exists?(ctx.out)
  end

  test "--check --json emits a valid envelope for clean and drift", ctx do
    {out, 0} = sync(ctx, [])
    assert File.exists?(ctx.out), out

    {out, code} = sync(ctx, ["--check", "--json"])
    assert code == 0, out
    env = decode_envelope(out)
    assert %{"schema_version" => 1, "task" => "sync", "ok" => true, "exit_code" => 0} = env
    assert env["refusal"] == nil
    assert env["data"]["drifted"] == []

    mutate_ontology!(ctx)
    {out, code} = sync(ctx, ["--check", "--json"])
    assert code == 4, out
    env = decode_envelope(out)
    assert %{"ok" => false, "exit_code" => 4, "standing" => "BLOCKED"} = env
    assert [%{"operation" => "write", "path" => path}] = env["data"]["drifted"]
    assert path == ctx.out
    assert env["data"]["drifted_count"] == 1
  end

  test "bad invocation exits 2 and --check with --dry-run is refused as invocation", ctx do
    {out, code} = sync(ctx, ["--check", "--dry-run"])
    assert code == 2, out
    assert out =~ "mutually exclusive"

    {out, code} = sync(ctx, ["--check", "--json", "--dry-run"])
    assert code == 2, out
    env = decode_envelope(out)
    assert env["exit_code"] == 2
    assert env["refusal"]["code"] == "INVOCATION"
  end

  test "--lock without a pack is an invocation error (exit 2)", ctx do
    {out, code} = sync(ctx, ["--check", "--lock", Path.join(ctx.root, "pack.lock")])
    assert code == 2, out
    assert out =~ "--lock PATH requires --pack"
  end

  @pack_lock_available? Code.ensure_loaded?(GgenIgniter.PackLock)

  @tag skip:
         if(@pack_lock_available?,
           do: false,
           else:
             "GgenIgniter.PackLock (lane WA3) not present; coordinator runs this integration test after WA3 lands"
         )
  test "--lock with a mismatching digest refuses PACK_DIGEST_MISMATCH (exit 1)", ctx do
    pack = Path.join(ctx.root, "pack")
    File.mkdir_p!(Path.join(pack, "gates"))
    File.cp!(ctx.ontology, Path.join(pack, "ontology.ttl"))
    lock = Path.join(ctx.root, "pack.lock")
    File.write!(lock, ~s({"pack":"pack","digest":"deadbeef"}))

    {out, code} = sync(ctx, ["--check", "--pack-dir", pack, "--lock", lock])
    assert code == 1, out
    assert out =~ "REFUSED:"
  end

  defp decode_envelope(out) do
    json = out |> String.split("\n") |> Enum.find(&String.starts_with?(&1, "{"))
    assert json, "no JSON envelope line in output:\n#{out}"
    Jason.decode!(json)
  end
end
