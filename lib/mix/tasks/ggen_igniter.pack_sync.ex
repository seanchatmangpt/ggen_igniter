defmodule Mix.Tasks.GgenIgniter.PackSync do
  use Mix.Task

  @shortdoc "Render a ggen frontmatter (Tera) pack from Turtle, byte-identical to `ggen sync run`"

  @moduledoc """
  Renders a ggen frontmatter pack (templates with `to`/`force`/`for_each`/`sparql:` headers
  and Tera bodies) through the ggen_igniter engine. Gap G1 of v26.11.13.

      mix ggen_igniter.pack_sync --pack-dir PACK --ontology app.ttl [--ontology more.ttl]
                                 [--out DIR] [--dry-run] [--check]
                                 [--lock PATH] [--relock]

  Flags:

    * `--pack-dir DIR`   the pack (ontology.ttl, ontology.d/*.ttl, gates/*.rq, templates/*.tmpl)
    * `--ontology PATH`  consumer ontology (repeatable, required)
    * `--out DIR`        project root outputs are written under (default: cwd)
    * `--dry-run`        decide and print, write nothing
    * `--check`          dry run; exit 4 listing files that would change (drift gate)
    * `--lock PATH`      pin the pack digest (`GgenIgniter.PackLock`, default
                         `<out>/ggen_igniter.pack.lock` when `--relock` is given); a digest
                         mismatch refuses the run
    * `--relock`         rewrite the lock entry for this pack from its current content (G3):
                         the igniter equivalent of the `rm ggen.lock` workaround

  Exit codes: 0 ok, 1 refusal (`REFUSED:...` on stderr), 2 invocation error, 4 drift (`--check`).
  See `GgenIgniter.PackFrontmatter.Sync` for the pipeline and the loud-refusal list.
  """

  alias GgenIgniter.PackFrontmatter.Sync
  alias GgenIgniter.PackLock

  @switches [
    pack_dir: :string,
    ontology: [:string, :keep],
    out: :string,
    dry_run: :boolean,
    check: :boolean,
    lock: :string,
    relock: :boolean
  ]

  @impl Mix.Task
  def run(argv) do
    {opts, _rest, invalid} = OptionParser.parse(argv, strict: @switches)

    cond do
      invalid != [] -> halt_with(2, "invalid option(s): #{inspect(invalid)}")
      opts[:pack_dir] in [nil, ""] -> halt_with(2, "--pack-dir DIR is required")
      Keyword.get_values(opts, :ontology) == [] -> halt_with(2, "--ontology PATH is required")
      true -> do_run(opts)
    end
  end

  defp do_run(opts) do
    {:ok, _} = Application.ensure_all_started(:ggen_igniter)
    pack_dir = opts[:pack_dir]
    out_dir = opts[:out] || File.cwd!()
    check? = opts[:check] == true
    dry_run? = opts[:dry_run] == true or check?

    try do
      lock_gate!(opts, pack_dir, out_dir)

      result =
        Sync.run!(
          pack_dir: pack_dir,
          ontologies: Keyword.get_values(opts, :ontology),
          out_dir: out_dir,
          dry_run: dry_run?
        )

      report(result, dry_run?)

      drifted = Enum.filter(result.files, &(&1.outcome == :written))

      if check? and drifted != [] do
        IO.puts(
          :stderr,
          "ggen_igniter.pack_sync --check: DRIFT -- #{length(drifted)} file(s) differ"
        )

        System.halt(4)
      end
    rescue
      e in ArgumentError ->
        msg = Exception.message(e)
        halt_with(if(msg =~ "REFUSED:", do: 1, else: 2), msg)

      e in [PackLock.Refusal, RuntimeError] ->
        halt_with(1, Exception.message(e))
    end
  end

  # `--relock` rewrites this pack's entry first; otherwise an existing/explicit `--lock`
  # must match the pack's current digest.
  defp lock_gate!(opts, pack_dir, out_dir) do
    lock_path =
      opts[:lock] || if(opts[:relock], do: Path.join(out_dir, PackLock.default_lock_path()))

    name = Path.basename(Path.expand(pack_dir))

    cond do
      lock_path == nil ->
        :ok

      opts[:relock] == true ->
        entry = PackLock.entry(pack_dir, "path:" <> Path.expand(pack_dir))

        {:ok, _} =
          PackLock.update(lock_path, [], fn lock -> {:ok, PackLock.put(lock, name, entry)} end)
          |> ok_tuple()

        IO.puts("relocked #{name} -> #{lock_path}")

      true ->
        case PackLock.check(pack_dir, lock_path) do
          :ok ->
            :ok

          {:error, reason} ->
            raise ArgumentError, PackLock.refusal_text(reason) <> " (pass --relock to re-pin)"
        end
    end
  end

  defp ok_tuple({:ok, _} = ok), do: ok
  defp ok_tuple(:ok), do: {:ok, :updated}
  defp ok_tuple(other), do: raise(RuntimeError, "pack lock update failed: #{inspect(other)}")

  defp report(result, dry_run?) do
    Enum.each(result.files, fn %{path: p, outcome: o} ->
      verb =
        case {o, dry_run?} do
          {:written, true} -> "planned: write"
          {:written, false} -> "wrote"
          {:unchanged, _} -> "unchanged"
          {other, _} -> to_string(other)
        end

      IO.puts("#{verb} #{p}")
    end)

    IO.puts("gates passed: #{length(result.gates)}")
  end

  defp halt_with(code, msg) do
    IO.puts(:stderr, msg)
    System.halt(code)
  end
end
