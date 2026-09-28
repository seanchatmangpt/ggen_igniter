defmodule GgenIgniterPackageAshFreeTest do
  @moduledoc """
  Chicago-style: builds the REAL hex package with a real `mix hex.build --unpack`
  subprocess into a unique tmp dir, then asserts on the real unpacked tree and
  the real `hex_metadata.config` (parsed with `:file.consult/1`). No doubles.

  Operator directive (2026-09-28): Ash must not ship with the hex package.
  Pinned here as state, not description:

    1. `hex_metadata.config` requirements contain no `ash*` package.
    2. No shipped file or directory is named for Ash (the `ash-*` packs are
       excluded by `shipped_packs/0` in `mix.exs`).
    3. No shipped `lib/` module `use`s an Ash surface (`use Ash.*`, `use AshPostgres.*`,
       `use AshA2A.*`), decided on the parsed AST so heredoc text does not count.
    Shipped files may still MENTION Ash as text (the install task and the
    semantic-jira A2A template write Ash code into a consumer project); that is
    consumer-side manufacture input, not an Ash dependency or module.

  `async: false`: one real `mix` subprocess builds from the shared checkout.
  Tagged `:package` (the build takes a few seconds).
  """
  use ExUnit.Case, async: false

  @moduletag :package

  setup_all do
    out =
      Path.join(System.tmp_dir!(), "pkg_ash_free_#{System.unique_integer([:positive])}")

    File.rm_rf!(out)
    on_exit(fn -> File.rm_rf!(out) end)

    {log, code} =
      System.cmd("mix", ["hex.build", "--unpack", "-o", out],
        cd: File.cwd!(),
        stderr_to_stdout: true
      )

    %{out: out, log: log, code: code}
  end

  defp files(out) do
    out
    |> Path.join("**")
    |> Path.wildcard(match_dot: true)
    |> Enum.filter(&File.regular?/1)
    |> Enum.map(&Path.relative_to(&1, out))
    |> Enum.sort()
  end

  test "the package builds and unpacks", %{out: out, log: log, code: code} do
    assert code == 0, log
    assert File.regular?(Path.join(out, "hex_metadata.config"))
    assert File.regular?(Path.join(out, "mix.exs"))
  end

  test "hex_metadata requirements name no ash package", %{out: out, code: 0} do
    {:ok, meta} = :file.consult(String.to_charlist(Path.join(out, "hex_metadata.config")))
    meta = Map.new(meta)
    names = for req <- meta["requirements"], {"name", n} <- req, do: n

    assert "igniter" in names, "sanity: requirements were parsed, got #{inspect(names)}"
    assert Enum.filter(names, &String.starts_with?(&1, "ash")) == []
  end

  test "no shipped path is named for Ash", %{out: out, code: 0} do
    ash_paths =
      out
      |> files()
      |> Enum.filter(fn p ->
        p |> Path.split() |> Enum.any?(&(&1 =~ ~r/(^|[-_.])ash([-_.]|$)/i))
      end)

    assert ash_paths == []
    assert "priv/ggen/semantic-jira-pack/ontology.ttl" in files(out), "sanity: packs ship"
  end

  test "no shipped lib/ module `use`s an Ash surface (AST check, heredoc text excluded)",
       %{out: out, code: 0} do
    lib_files = Enum.filter(files(out), &(String.starts_with?(&1, "lib/") and &1 =~ ~r/\.exs?$/))
    assert lib_files != [], "sanity: lib/ shipped"

    definers =
      for p <- lib_files, uses_ash?(File.read!(Path.join(out, p))), do: p

    assert definers == []
  end

  test "the AST check itself detects a real Ash surface (falsifier for the check)" do
    assert uses_ash?("defmodule X do\n  use Ash.Resource, domain: D\nend")
    assert uses_ash?("defmodule X do\n  use AshPostgres.Repo, otp_app: :x\nend")
    refute uses_ash?(~s|defmodule X do\n  @t """\n  use Ash.Domain\n  """\nend|)
  end

  defp uses_ash?(src) do
    {:ok, ast} = Code.string_to_quoted(src)

    {_, found} =
      Macro.prewalk(ast, false, fn
        {:use, _, [{:__aliases__, _, [root | _]} | _]} = node, _acc
        when root in [:Ash, :AshPostgres, :AshA2A] ->
          {node, true}

        node, acc ->
          {node, acc}
      end)

    found
  end
end
