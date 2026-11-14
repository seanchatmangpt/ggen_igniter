defmodule GgenIgniter.PackFrontmatter.Receipt do
  @moduledoc """
  Receipt for a Tera frontmatter pack sync (`GgenIgniter.PackFrontmatter.Sync.run!/1`).

  Shape follows `~/.claude/dfcm/receipt.schema.json` (v2): identity, authority, consequence,
  replay, standing, plus the required provenance keys. Written to
  `<out>/.ggen-igniter/receipt-<identity16>.json`.

  Deterministic: no wall-clock fields; keys are emitted in sorted order; the file name and
  `provider_execution_id` derive from the identity digest
  (`sha256(pack_digest | ontology_digests | ggen_igniter version)`). The same pack, ontologies,
  version and output state therefore yield a byte-identical receipt (replayable).

  Identity: pack and ontology digests ride in `identity.subject_digest` /
  `provider_ext.ggen_igniter` (non-commit subjects; no git commit is claimed, `subject_sha` and
  `base_sha` are not asserted here). Standing: `ALIVE` when every file was written or
  unchanged, `PARTIAL_ALIVE` when any was `:skipped_exists`.
  """

  alias Jason.OrderedObject

  @dir ".ggen-igniter"

  @doc "Directory (under the out dir) that holds receipts."
  def dir, do: @dir

  @doc """
  Builds the receipt map. `result` is `Sync.run!/1`'s return; `opts` are the same options
  (`:pack_dir`, `:ontologies`, `:out_dir`).
  """
  @spec build(map(), keyword()) :: map()
  def build(result, opts) do
    pack_dir = opts |> Keyword.fetch!(:pack_dir) |> Path.expand()
    ontologies = opts |> Keyword.fetch!(:ontologies) |> Enum.map(&Path.expand/1)
    out_dir = opts |> Keyword.get(:out_dir, File.cwd!()) |> Path.expand()

    pack_digest = digest_tree(pack_dir)
    ontology_digests = Enum.map(ontologies, &digest_file/1)
    version = version()

    identity_digest =
      sha256(Enum.join([pack_digest | ontology_digests] ++ [version], "|"))

    files =
      result.files
      |> Enum.map(fn %{path: p, outcome: o} ->
        %{
          "path" => Path.relative_to(p, out_dir),
          "outcome" => Atom.to_string(o),
          "sha256" => if(File.regular?(p), do: digest_file(p), else: "absent")
        }
      end)
      |> Enum.sort_by(& &1["path"])

    partial? = Enum.any?(result.files, &(&1.outcome == :skipped_exists))

    replay_cmd =
      Enum.join(
        ["mix ggen_igniter.sync", "--pack-dir", pack_dir] ++
          Enum.flat_map(ontologies, &["--ontology", &1]) ++ ["--out", out_dir],
        " "
      )

    %{
      "work_order_id" => "pack-sync:" <> Path.basename(pack_dir),
      "origin_authority" => %{
        "ceiling" => "CONSTRUCT",
        "grant" => "NONE",
        "actor" => "mix ggen_igniter.sync"
      },
      "provider" => %{
        "name" => "ggen_igniter.pack_frontmatter",
        "transport" => "in-process",
        "authority_ceiling" => "CONSTRUCT"
      },
      "provider_execution_id" => "sha256:" <> identity_digest,
      "identity" => %{
        "subject" => Path.basename(pack_dir),
        "repo" => "ggen_igniter",
        "subject_digest" => %{"algorithm" => "sha256", "value" => pack_digest}
      },
      "authority" => %{
        "ceiling" => "CONSTRUCT",
        "grant" => "NONE",
        "actor" => "mix ggen_igniter.sync"
      },
      "consequence" => %{
        "commits" => [],
        "files_changed" =>
          files |> Enum.filter(&(&1["outcome"] == "written")) |> Enum.map(& &1["path"]),
        "remote_effects" => []
      },
      "replay" => %{
        "commands" => [%{"cmd" => replay_cmd, "cwd" => ".", "exit" => 0}],
        "durable_location" => Path.join(@dir, receipt_name(identity_digest))
      },
      "standing" => %{
        "value" => if(partial?, do: "PARTIAL_ALIVE", else: "ALIVE"),
        "derived_from" => "replay command: files written/unchanged per consequence ledger"
      },
      "provider_ext" => %{
        "ggen_igniter" => %{
          "version" => version,
          "pack_digest" => "sha256:" <> pack_digest,
          "ontology_digests" => Enum.map(ontology_digests, &("sha256:" <> &1)),
          "gates" => Enum.sort(result.gates),
          "files" => files
        }
      }
    }
  end

  @doc "Builds and writes the receipt under `<out_dir>/.ggen-igniter/`; returns its path."
  @spec write!(map(), keyword()) :: String.t()
  def write!(result, opts) do
    out_dir = opts |> Keyword.get(:out_dir, File.cwd!()) |> Path.expand()
    receipt = build(result, opts)
    "sha256:" <> id = receipt["provider_execution_id"]
    path = Path.join([out_dir, @dir, receipt_name(id)])
    File.mkdir_p!(Path.dirname(path))
    body = Jason.encode!(ordered(receipt), pretty: true) <> "\n"

    unless File.exists?(path) and File.read!(path) == body, do: File.write!(path, body)
    path
  end

  defp receipt_name(identity_digest),
    do: "receipt-" <> binary_part(identity_digest, 0, 16) <> ".json"

  defp ordered(map) when is_map(map),
    do:
      map
      |> Enum.sort_by(&elem(&1, 0))
      |> Enum.map(fn {k, v} -> {k, ordered(v)} end)
      |> OrderedObject.new()

  defp ordered(list) when is_list(list), do: Enum.map(list, &ordered/1)
  defp ordered(other), do: other

  defp version, do: :ggen_igniter |> Application.spec(:vsn) |> to_string()

  defp digest_file(path), do: path |> File.read!() |> sha256()

  # Deterministic tree digest: sorted relative paths + content hashes.
  defp digest_tree(dir) do
    dir
    |> Path.join("**/*")
    |> Path.wildcard()
    |> Enum.filter(&File.regular?/1)
    |> Enum.sort()
    |> Enum.map_join("\n", fn f -> Path.relative_to(f, dir) <> ":" <> digest_file(f) end)
    |> sha256()
  end

  defp sha256(bin), do: :crypto.hash(:sha256, bin) |> Base.encode16(case: :lower)
end
