# Chicago-Style Pack Testing

How to test a community-avatar pack with `GgenIgniter.Test.PackCompile` and
`GgenIgniter.Test.PostgresCase` (both in `test/support/`, compiled in `:test`).
Audience: pack authors. Rules: `test/CLAUDE.md` (no doubles; real subprocess, real compiler).

## Worked example

```elixir
defmodule MyPackTest do
  @moduledoc "Chicago-style: real sync subprocess + real compiler; state assertions only."
  use ExUnit.Case, async: false
  alias GgenIgniter.Test.PackCompile

  @moduletag :integration

  test "pack renders, compiles, and behaves" do
    PackCompile.with_compiled("my-pack:module", [ontology: "test/fixtures/my.ttl"], fn mods, r ->
      assert MyApp.Generated in mods
      assert Enum.any?(r.files, &String.ends_with?(&1, "generated.ex"))
      assert MyApp.Generated.answer() == 42
    end)
  end

  test "FALSIFIER: corrupted output is caught" do
    r = PackCompile.render!("my-pack:module", ontology: "test/fixtures/my.ttl")
    on_exit(fn -> PackCompile.cleanup(r.out_dir) end)
    [file | _] = r.files
    File.write!(file, File.read!(file) <> "\ndef broken( do\n")
    assert {:error, [%{file: _, line: _} | _]} = PackCompile.compile([file])
  end

  test "a refused pack raises" do
    # assert the SPECIFIC refusal, not merely "something failed"
    assert {:error, %{exit_status: 2, output: out}} =
             PackCompile.render("my-pack", pack_dir: "test/fixtures/broken-pack")

    assert out =~ "pack.toml"
  end
end
```

## API

- `render!/2`, `render/2`: real `mix ggen_igniter.sync --pack SPEC --engine sparql`. Options:
  `:ontology`, `:out` (relative to the tmp dir), `:extra_args`, `:env`, `:pack_dir`, `:timeout`.
  Returns `%{out_dir, files, output}`; a non-zero exit raises `RenderError` (or `{:error, ...}`).
  On `:timeout` the real `mix` OS process tree is killed and the result is exit status 124
  with `output` ending in `timed out`; assert on exit status AND output text so a timeout
  or crash is never mistaken for a refusal.
- `compile/2`, `compile!/2`: real compile to a tmp ebin; verifier refusals (Spark `DslError`)
  arrive as diagnostics `%{severity, file, line, message}`.
- `purge/1`, `with_compiled/3` (always purges), `tmp_project!/1`, `cleanup/1`.
- `PostgresCase.available?/0`, `connect_opts/0`, `create_database!/1`, `drop_database!/1`,
  `setup_database/1` (use in `setup`; drops on exit). `available?/0` runs its probe in an unlinked
  monitored process: an unreachable server returns `false` and never exits the caller. Env: `QUALIFY_PGHOST`/`PORT`/`USER`/
  `PASSWORD`/`DATABASE`, same defaults as `qualify.sh`.

## Tags

- `:integration`: real subprocess or compile; excluded from a plain `mix test`.
- `:postgres`: needs a reachable Postgres; excluded by `test_helper.exs` when it is not.

## Caveats

Compiled modules live in the global code server. Two tests generating a module with the same
name cannot coexist; use `async: false` or unique module names. The sync subprocess runs from
the ggen_igniter project root (where the mix task exists); the tmp dir is its manifest/out root.

## Commands

```bash
MIX_BUILD_ROOT=_build-w0 mix test --include integration test/ggen_igniter_pack_compile_test.exs
MIX_BUILD_ROOT=_build-w0 mix test --include integration --include postgres \
  test/ggen_igniter_postgres_case_test.exs
```

## See Also

- `test/CLAUDE.md`: required moduledoc and the mock-grep check.
- `test/ggen_igniter_receipted_extension_pack_test.exs`: the original ad hoc pattern.
