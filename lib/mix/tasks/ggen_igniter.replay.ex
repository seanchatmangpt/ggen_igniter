defmodule Mix.Tasks.GgenIgniter.Replay do
  @moduledoc """
  Diagnostic task: `mix ggen_igniter.replay <receipt_file> [--verify-only] [--json] [--manifest-dir DIR]`.

  Loads ONE real `GgenIgniter.Receipt` (see that module's moduledoc for the
  on-disk format) and recomputes real, CURRENT hashes of the same inputs the
  receipt recorded, to answer: "has anything this receipt depended on
  drifted since it was written?"

  `receipt_file` accepts either on-disk shape a receipt genuinely exists in:

    * A date-partitioned `.jsonl` partition (`<base_dir>/.ggen_igniter/receipts/<yyyy-mm-dd>.jsonl`,
      `GgenIgniter.Receipt.path/2`'s real format) -- the LAST line (most
      recent attempt in that partition) is replayed.
    * A single JSON object file -- one receipt's `GgenIgniter.Receipt.to_json_map/1`
      shape, decoded directly via `Jason.decode!/1` (no receipt-specific
      wrapper). This is the shape a caller gets by extracting one line out of
      a `.jsonl` partition into its own file.

  Exits 2 (invalid invocation) if the file does not exist or does not parse
  as either shape -- never guesses at a receipt's content.

  ## What real drift this can and cannot detect

  `GgenIgniter.Receipt`'s on-disk schema (see that module's moduledoc)
  records, per attempt: `recipe_key` (`"<template_path>=><out_template>"`),
  `files` (the real output paths this attempt touched),
  `pre_run_hash`/`post_run_hash` (real content digests over exactly those
  `files`, via `GgenIgniter.Receipt.hash_files/1`), and a free-form
  `metadata` map -- on an `:alive` receipt written by
  `GgenIgniter.Reactors.ReconcileReactor`, `metadata["graph_hash"]` is a real
  `"sha256:" <> hex` digest of the ontology file that produced this run (see
  that module's `finalize_evidence/1`).

  This task recomputes and compares exactly what the schema makes
  recomputable, and reports each as its own category rather than a single
  pass/fail:

    * **"output state changed"** -- `GgenIgniter.Receipt.hash_files/1` is
      re-run over the receipt's own `files` list, RIGHT NOW, and compared to
      the receipt's recorded `post_run_hash`. A mismatch means at least one
      output this recipe wrote has been edited (or deleted) since this
      receipt was recorded.
    * **"ontology changed"** -- only checked when the receipt's `recipe_key`
      resolves to a `GgenIgniter.Manifest` entry recording a `pack_dir`
      (`--manifest-dir`'s manifest, default `File.cwd!()`) AND the receipt's
      `metadata["graph_hash"]` is present. `<pack_dir>/ontology.ttl` (the
      `--pack` convention's fixed subpath -- see `priv/ggen/CLAUDE.md`) is
      re-read and re-hashed with the SAME `"sha256:" <> hex` algorithm the
      reactor used, and compared to `graph_hash`.

  `GgenIgniter.Receipt`'s schema does NOT record a standalone baseline hash
  of the template file, the gate query, the pack directory as a whole, the
  query engine's version string, or arbitrary run config -- there is no
  recorded value for this task to compare a recomputed hash AGAINST for
  those categories, so this task never fabricates a comparison for them.
  When the receipt's `recipe_key` names a template path, its CURRENT hash is
  still reported (`--json`'s `"template_path"`/`"template_current_hash"`
  fields, or the human line `template: <path> (no baseline recorded --
  informational only)`) so a human has the value on hand, but it is never
  counted as drift. If `GgenIgniter.Receipt`'s schema grows recorded
  baselines for these categories, extend `detect_drift/2` to compare them for
  real rather than widen this task's guesses.

  ## Exit codes

    * `0` -- receipt loaded and compared; no real drift detected.
    * `1` -- receipt loaded and compared; at least one real drift category found.
    * `2` -- invalid invocation (missing/unreadable/unparsable receipt file,
      or a bad flag).

  `--verify-only` performs only this read-only comparison (the only mode
  implemented so far; reserved for a future re-actuation mode, never implied
  as already present). `--json` prints the machine-readable report
  (`%{"drift" => [...], "categories" => %{...}, "receipt" => %{...}}`)
  instead of the human-readable lines.

  ## Examples

      mix ggen_igniter.replay .ggen_igniter/receipts/2026-08-27.jsonl

      mix ggen_igniter.replay tmp/one_receipt.json --json --manifest-dir priv/ggen/audit-trail-pack
  """
  use Mix.Task

  alias GgenIgniter.{Manifest, Receipt}

  @shortdoc "Replays a receipt and reports real drift since it was recorded"

  @impl Mix.Task
  def run(argv) do
    {opts, positional, invalid} =
      OptionParser.parse(argv,
        strict: [
          verify_only: :boolean,
          json: :boolean,
          manifest_dir: :string,
          help: :boolean,
          version: :boolean
        ],
        aliases: [h: :help, v: :version]
      )

    json? = Keyword.get(opts, :json, false)

    cond do
      opts[:help] ->
        print_help_and_halt()

      opts[:version] ->
        print_version_and_halt()

      invalid != [] ->
        invalid_invocation("unrecognized flag(s): #{inspect(invalid)}", json?)

      positional == [] ->
        invalid_invocation(
          "usage: mix ggen_igniter.replay <receipt_file> [--verify-only] [--json] [--manifest-dir DIR]",
          json?
        )

      true ->
        [receipt_file | _rest] = positional
        manifest_dir = Keyword.get(opts, :manifest_dir, File.cwd!())

        case load_receipt(receipt_file) do
          {:ok, receipt} ->
            report = build_report(receipt, manifest_dir)
            print_report(report, json?)
            halt(if report.categories == [], do: 0, else: 1)

          {:error, reason} ->
            invalid_invocation(reason, json?)
        end
    end
  end

  # `--json` mode must emit ONLY valid JSON to stdout on every real code
  # path this task can take -- including invalid-invocation (missing/bad
  # receipt file, unrecognized flag, no positional arg). Before this fix,
  # every one of those cases went to `Mix.shell().error/1` (stderr) with
  # NOTHING printed to stdout, so a `--json` caller piping stdout into a
  # JSON parser got empty input instead of a parseable error object -- the
  # same real defect class the success path had (see `print_report/2`'s
  # JSON branch, which this mirrors), just on the invalid-invocation path
  # instead of the drift-report path. The human-readable message still also
  # goes to stderr (diagnostics/warnings belong on stderr, not stdout) so a
  # human running this without `--json` sees the same message as before.
  defp invalid_invocation(message, json?) do
    Mix.shell().error("ggen_igniter.replay: #{message}")

    if json? do
      Mix.shell().info(Jason.encode!(%{"error" => message}, pretty: true))
    end

    halt(2)
  end

  defp print_help_and_halt do
    IO.puts("""
    mix ggen_igniter.replay -- replays a receipt and reports real drift since it was recorded

    USAGE
        mix ggen_igniter.replay <receipt_file> [--verify-only] [--json]
                                 [--manifest-dir DIR] [--help] [--version]

    FLAGS
        <receipt_file>      A .jsonl receipt partition (last line replayed) or a single
                             JSON receipt object file. Required.
        --verify-only        Read-only comparison (the only mode implemented today).
        --json                Emit the machine-readable report instead of human lines.
        --manifest-dir DIR    Directory holding .ggen_igniter/manifest.json. Default: cwd.
        --help, -h            Print this help and exit 0.
        --version, -v         Print ggen_igniter's version and exit 0.

    EXAMPLES
        mix ggen_igniter.replay .ggen_igniter/receipts/2026-08-27.jsonl

        mix ggen_igniter.replay tmp/one_receipt.json --json --manifest-dir priv/ggen/audit-trail-pack

    EXIT CODES
        0  receipt loaded and compared; no real drift detected
        1  receipt loaded and compared; at least one real drift category found
        2  invalid invocation (missing/unreadable/unparsable receipt file, or a bad flag)
    """)

    halt(0)
  end

  defp print_version_and_halt do
    version = Application.spec(:ggen_igniter, :vsn) |> to_string()
    IO.puts("ggen_igniter #{version}")
    halt(0)
  rescue
    _ ->
      IO.puts("ggen_igniter unknown")
      halt(0)
  end

  # `System.halt/1` is real here (not `Mix.raise/1`) because this task's
  # whole contract is a real, distinguishable 0/1/2 process exit code a CI
  # step or another tool can branch on -- `Mix.raise/1` always exits 1,
  # which would collapse "invalid invocation" and "real drift found" into
  # the same code.
  defp halt(code), do: System.halt(code)

  @doc false
  @spec load_receipt(String.t()) :: {:ok, map()} | {:error, String.t()}
  def load_receipt(path) do
    case File.read(path) do
      {:ok, content} ->
        decode_receipt(path, content)

      {:error, reason} ->
        {:error, "could not read receipt file #{path}: #{inspect(reason)}"}
    end
  end

  defp decode_receipt(path, content) do
    if String.ends_with?(path, ".jsonl") do
      case content |> String.split("\n", trim: true) |> List.last() do
        nil -> {:error, "receipt file #{path} is a .jsonl partition with no lines"}
        last_line -> jason_decode(path, last_line)
      end
    else
      jason_decode(path, content)
    end
  end

  defp jason_decode(path, json_text) do
    case Jason.decode(json_text) do
      {:ok, %{"standing" => _} = receipt} ->
        {:ok, receipt}

      {:ok, other} ->
        {:error, "receipt file #{path} did not decode to a receipt object: #{inspect(other)}"}

      {:error, reason} ->
        {:error, "receipt file #{path} is not valid JSON: #{inspect(reason)}"}
    end
  end

  @doc false
  @spec build_report(map(), String.t()) :: map()
  def build_report(receipt, manifest_dir) do
    recipe_key = receipt["recipe_key"]
    files = receipt["files"] || []
    template_path = template_path_from_recipe_key(recipe_key)

    output_drift = detect_output_drift(files, receipt["post_run_hash"])
    ontology_drift = detect_ontology_drift(receipt, recipe_key, manifest_dir)

    categories =
      [output_drift, ontology_drift]
      |> Enum.filter(& &1)

    %{
      receipt_id: receipt["id"],
      recipe_key: recipe_key,
      template_path: template_path,
      template_current_hash: template_current_hash(template_path),
      categories: categories
    }
  end

  defp template_path_from_recipe_key(nil), do: nil

  defp template_path_from_recipe_key(recipe_key) when is_binary(recipe_key) do
    case String.split(recipe_key, "=>", parts: 2) do
      [template_path, _out_template] -> template_path
      _other -> nil
    end
  end

  defp template_current_hash(nil), do: nil

  defp template_current_hash(template_path) do
    case File.read(template_path) do
      {:ok, content} -> Manifest.hash_content(content)
      {:error, _reason} -> nil
    end
  end

  defp detect_output_drift(_files, nil), do: nil

  defp detect_output_drift(files, recorded_post_run_hash) do
    current_hash = Receipt.hash_files(files)

    if current_hash == recorded_post_run_hash do
      nil
    else
      %{
        category: "output state changed",
        recorded: recorded_post_run_hash,
        current: current_hash,
        files: files
      }
    end
  end

  defp detect_ontology_drift(receipt, recipe_key, manifest_dir) do
    with recorded_graph_hash when is_binary(recorded_graph_hash) <-
           get_in(receipt, ["metadata", "graph_hash"]),
         key when is_binary(key) <- recipe_key,
         %{"pack_dir" => pack_dir} when is_binary(pack_dir) <-
           Manifest.get_entry(Manifest.load(manifest_dir), key),
         ontology_path = Path.join(pack_dir, "ontology.ttl"),
         {:ok, content} <- File.read(ontology_path) do
      current_hash = "sha256:" <> (:crypto.hash(:sha256, content) |> Base.encode16(case: :lower))

      if current_hash == recorded_graph_hash do
        nil
      else
        %{
          category: "ontology changed",
          recorded: recorded_graph_hash,
          current: current_hash,
          ontology_path: ontology_path
        }
      end
    else
      _not_checkable -> nil
    end
  end

  defp print_report(report, true = _json?) do
    payload = %{
      "receipt_id" => report.receipt_id,
      "recipe_key" => report.recipe_key,
      "template_path" => report.template_path,
      "template_current_hash" => report.template_current_hash,
      "drift" => report.categories != [],
      "categories" => report.categories
    }

    Mix.shell().info(Jason.encode!(payload, pretty: true))
  end

  defp print_report(report, false = _json?) do
    Mix.shell().info("ggen_igniter.replay: receipt #{report.receipt_id} (#{report.recipe_key})")

    if report.template_path do
      Mix.shell().info(
        "template: #{report.template_path} (no baseline recorded -- informational only, current hash: #{report.template_current_hash})"
      )
    end

    case report.categories do
      [] ->
        Mix.shell().info("no drift detected")

      categories ->
        Enum.each(categories, fn drift ->
          Mix.shell().info(
            "#{drift.category}: recorded=#{drift.recorded} current=#{drift.current}"
          )
        end)
    end
  end
end
