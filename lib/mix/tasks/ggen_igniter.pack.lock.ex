defmodule Mix.Tasks.GgenIgniter.Pack.Lock do
  @shortdoc "Writes or verifies the pack lockfile (sha256 per pack) ggen_igniter.pack.lock"

  @moduledoc """
  Pins packs to the sha256 of their content, or verifies them against the pin.

      mix ggen_igniter.pack.lock [--path DIR] [--pack NAME...] [--lock PATH] [--check] [--json]

  `--path DIR` is the pack root (default `priv/ggen`): each subdirectory is a
  pack. If `DIR` itself holds `pack.toml` or `ontology.ttl` it is treated as a
  single pack. `--pack NAME` (repeatable) restricts to named packs.
  `--lock PATH` defaults to `ggen_igniter.pack.lock`.

  Without `--check` the lockfile is written/updated. With `--check` nothing is
  written; exit `0` all packs match, `1` refusal
  (`REFUSED:PACK_DIGEST_MISMATCH` / `REFUSED:PACK_LOCK_MISSING`), `2` invalid
  invocation. See `docs/reference/cli/pack-lock.md`.
  """

  use Mix.Task

  alias GgenIgniter.PackLock

  @impl Mix.Task
  def run(argv) do
    GgenIgniter.TaskShell.run_with_help(
      argv,
      fn ->
        IO.puts("""
        mix ggen_igniter.pack.lock -- pin packs to a content sha256 (or verify with --check)

        USAGE
            mix ggen_igniter.pack.lock [--path DIR] [--pack NAME...] [--lock PATH] [--check] [--json]

        EXIT CODES
            0 ok   1 REFUSED:PACK_DIGEST_MISMATCH | REFUSED:PACK_LOCK_MISSING   2 invalid invocation
        """)

        System.halt(0)
      end,
      fn -> do_run(argv) end,
      ["--help", "-h"]
    )
  end

  defp do_run(argv) do
    {opts, _pos, invalid} =
      OptionParser.parse(argv,
        strict: [path: :string, pack: :keep, lock: :string, check: :boolean, json: :boolean]
      )

    json? = Keyword.get(opts, :json, false)
    if invalid != [], do: bad(json?, "unrecognized flag(s): #{inspect(invalid)}")

    root = Keyword.get(opts, :path, "priv/ggen")
    lock_path = Keyword.get(opts, :lock, PackLock.default_lock_path())
    names = Keyword.get_values(opts, :pack)

    unless File.dir?(root), do: bad(json?, "pack root #{root} is not a directory")

    dirs = discover(root, names)
    if dirs == [], do: bad(json?, "no packs found under #{root}")

    if opts[:check], do: check(dirs, lock_path, json?), else: write(dirs, lock_path, json?)
  end

  defp discover(root, names) do
    if single_pack?(root) do
      if names == [] or Path.basename(root) in names, do: [root], else: []
    else
      root
      |> File.ls!()
      |> Enum.sort()
      |> Enum.filter(&File.dir?(Path.join(root, &1)))
      |> Enum.filter(&(names == [] or &1 in names))
      |> Enum.map(&Path.join(root, &1))
    end
  end

  defp single_pack?(dir),
    do: File.exists?(Path.join(dir, "pack.toml")) or File.exists?(Path.join(dir, "ontology.ttl"))

  defp write(dirs, lock_path, json?) do
    lock =
      case PackLock.read(lock_path) do
        {:ok, l} -> l
        _ -> PackLock.empty()
      end

    {lock, entries} =
      Enum.reduce(dirs, {lock, []}, fn dir, {l, acc} ->
        e = PackLock.entry(dir, dir)
        {PackLock.put(l, e["name"], e), [e | acc]}
      end)

    PackLock.write(lock_path, lock)

    if json? do
      Mix.shell().info(Jason.encode!(%{"lock" => lock_path, "packs" => Enum.reverse(entries)}))
    else
      Enum.each(
        Enum.reverse(entries),
        &Mix.shell().info("locked #{&1["name"]} sha256=#{&1["sha256"]}")
      )

      Mix.shell().info("wrote #{lock_path}")
    end

    System.halt(0)
  end

  defp check(dirs, lock_path, json?) do
    refusals =
      dirs
      |> Enum.map(&{&1, PackLock.check(&1, lock_path)})
      |> Enum.flat_map(fn
        {_, :ok} -> []
        {_, {:error, reason}} -> [reason]
      end)

    if refusals == [] do
      if json?,
        do: Mix.shell().info(Jason.encode!(%{"ok" => true, "checked" => length(dirs)})),
        else: Mix.shell().info("pack lock ok (#{length(dirs)} packs)")

      System.halt(0)
    else
      texts = Enum.map(refusals, &PackLock.refusal_text/1)
      Enum.each(texts, fn text -> Mix.shell().error(text) end)
      if json?, do: Mix.shell().info(Jason.encode!(%{"ok" => false, "refused" => texts}))
      System.halt(1)
    end
  end

  defp bad(json?, message) do
    Mix.shell().error("ggen_igniter.pack.lock: #{message}")
    if json?, do: Mix.shell().info(Jason.encode!(%{"error" => message}))
    System.halt(2)
  end
end
