defmodule GgenIgniter.SyncFrontmatterTest do
  @moduledoc """
  Chicago-style, real subprocess, no mocks: proves the actual hygen/ggen 80/20
  parity claim -- a template with its own `---\\n...\\n---\\n` header (`to:`,
  `sparql:`, `skip_if:`) drives the whole `mix ggen_igniter.sync` run with
  NO `--out`, `--query`, or `--skip-if` flags at all, exactly like `hygen
  generate <name>` needs no routing flags on the CLI. Before this test (and
  the `sync.ex`/`frontmatter.ex` wiring it exercises), `GgenIgniter.Frontmatter`
  was a fully-typed but completely unused shape module -- this is the real,
  behavioral fix, not just a parser existing in isolation.
  """
  use ExUnit.Case, async: false

  @moduletag :integration

  @out_path "tmp_out/frontmatter/AuditTrail.Resource.ex"

  setup do
    File.rm(@out_path)
    on_exit(fn -> File.rm(@out_path) end)
    :ok
  end

  test "template frontmatter's to:/sparql:/skip_if: drive the run with zero --out/--query/--skip-if flags" do
    args = [
      "ggen_igniter.sync",
      # Pinned to sparql: this test asserts a specific written path and
      # rendered content built from module_name -- oxigraph (the default
      # since v26.8.27) returns raw, quoted N-Triples-style term strings
      # instead of sparql's unwrapped native values, which is a real,
      # disclosed shape difference (see the sync task's own moduledoc), not
      # something this general frontmatter-mechanics test is about.
      "--engine",
      "sparql",
      "--ontology",
      "test/fixtures/audit_trail_ontology.ttl",
      "--template",
      "test/fixtures/self_contained_module.ex.eex"
    ]

    {output, exit_code} = System.cmd("mix", args, cd: File.cwd!(), stderr_to_stdout: true)

    assert exit_code == 0, "mix ggen_igniter.sync failed:\n#{output}"
    assert output =~ "ggen_igniter: wrote #{@out_path}"

    assert File.exists?(@out_path)
    content = File.read!(@out_path)

    assert {:defmodule, _, _} = Code.string_to_quoted!(content)
    assert content =~ "def package_name, do: \"audit_trail\""
    assert content =~ "def extension_target, do: \"resource\""
  end

  test "an explicit --out overrides the frontmatter's to:, and an explicit --query overrides its inline sparql:" do
    explicit_out =
      Path.join(System.tmp_dir!(), "explicit_out_#{System.unique_integer([:positive])}.ex")

    File.rm(explicit_out)
    on_exit(fn -> File.rm(explicit_out) end)

    args = [
      "ggen_igniter.sync",
      "--ontology",
      "test/fixtures/audit_trail_ontology.ttl",
      "--template",
      "test/fixtures/self_contained_module.ex.eex",
      "--out",
      explicit_out,
      "--query",
      "spec=test/fixtures/spec.rq"
    ]

    {output, exit_code} = System.cmd("mix", args, cd: File.cwd!(), stderr_to_stdout: true)

    assert exit_code == 0, "mix ggen_igniter.sync failed:\n#{output}"
    assert output =~ "ggen_igniter: wrote #{explicit_out}"
    assert File.exists?(explicit_out)
    refute File.exists?(@out_path)

    File.rm(explicit_out)
  end

  test "a template with no --- header behaves exactly as before: missing --out is a real, clear error" do
    args = [
      "ggen_igniter.sync",
      "--ontology",
      "test/fixtures/audit_trail_ontology.ttl",
      "--query",
      "spec=test/fixtures/spec.rq",
      "--template",
      "test/fixtures/extension.ex.eex"
    ]

    {output, exit_code} = System.cmd("mix", args, cd: File.cwd!(), stderr_to_stdout: true)

    assert exit_code != 0
    assert output =~ "--out is required"
  end
end
