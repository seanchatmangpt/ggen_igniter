defmodule Mix.Tasks.GgenIgniter.Epoch.Explain do
  @shortdoc "Explains one file's epoch provenance chain and what would make it ALIVE"

  @moduledoc """
  The epoch microscope: one file's full provenance chain — attribution
  evidence, closest pre-epoch match with similarity, informing git
  authorship, verdict, and the specific condition that would make it
  ALIVE.

      mix ggen_igniter.epoch.explain --epoch v26.10.1 --file lib/foo.ex \\
        [--base-dir DIR]

  Read-only by design: this task ALWAYS exits 0 on a judged file, even
  when the verdict inside is a REFUSED_* atom. `ggen_igniter.epoch.check`
  is the gate whose exit code decides; this is the explanation of why.
  Exit `0` judged (verdict inside the JSON), `1` could not judge, `2` bad
  invocation.
  """

  use Mix.Task

  alias GgenIgniter.EpochFreshness

  @impl Mix.Task
  def run(argv) do
    {opts, _positional, invalid} =
      OptionParser.parse(argv,
        strict: [epoch: :string, file: :string, base_dir: :string],
        aliases: [e: :epoch, f: :file, d: :base_dir]
      )

    unless invalid == [] and is_binary(opts[:epoch]) and is_binary(opts[:file]) do
      usage()
      System.halt(2)
    end

    base_dir = Keyword.get(opts, :base_dir, File.cwd!())

    case EpochFreshness.explain(base_dir, opts[:epoch], opts[:file], []) do
      {:ok, explanation} ->
        Mix.shell().info(Jason.encode!(explanation, pretty: true))

      {:error, {:refused_epoch_check, %{code: code, detail: detail}}} ->
        Mix.shell().error(
          Jason.encode!(%{
            "refused" => "EPOCH_EXPLAIN",
            "code" => to_string(code),
            "detail" => detail
          })
        )

        System.halt(1)
    end
  end

  defp usage do
    Mix.shell().error("""
    usage: mix ggen_igniter.epoch.explain --epoch LABEL --file PATH [--base-dir DIR]
    """)
  end
end
