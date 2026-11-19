defmodule GgenIgniter.SemanticJira.WorkOrderShape.Parse do
  @moduledoc false

  @doc false
  def property_pattern!(source, predicate, shape_basename) do
    re =
      Regex.compile!(
        "sh:path\\s+#{Regex.escape(predicate)}\\s*;[^\\]]*sh:pattern\\s+\"((?:\\\\.|[^\"\\\\])*)\"",
        "s"
      )

    case Regex.run(re, source, capture: :all_but_first) do
      [raw] ->
        unescape_turtle(raw)

      nil ->
        raise CompileError,
          description: "WorkOrderShape: no sh:pattern for #{predicate} in #{shape_basename}"
    end
  end

  @doc false
  def unescape_turtle(raw) do
    raw
    |> String.replace("\\\\", "\x00")
    |> String.replace("\\n", "\n")
    |> String.replace("\\t", "\t")
    |> String.replace("\\\"", "\"")
    |> String.replace("\x00", "\\")
  end

  @doc false
  def derive_base_standings!(pattern, frozen) do
    alts =
      case Regex.run(~r/\A\^\((.+)\)\$\z/s, pattern, capture: :all_but_first) do
        [inner] ->
          String.split(inner, "|")

        nil ->
          raise CompileError,
            description:
              "WorkOrderShape: sj:standing pattern is not a ^(...)$ alternation: #{inspect(pattern)}"
      end

    standings =
      alts
      |> Enum.reject(&String.starts_with?(&1, "REFUSED"))
      |> Enum.map(&String.trim/1)

    unless standings == frozen do
      raise CompileError,
        description:
          "WorkOrderShape: sj:standing parse drifted from frozen kernel list " <>
            "(got #{inspect(standings)}, expected #{inspect(frozen)}). " <>
            "STOP — do not remint digests; document the SHACL change first."
    end

    unless Enum.any?(alts, &String.starts_with?(&1, "REFUSED")) do
      raise CompileError,
        description:
          "WorkOrderShape: sj:standing pattern lost REFUSED(...) arm; " <>
            "kernel keeps that as a separate clause and the shape must still carry it."
    end

    standings
  end

  @doc false
  def elixir_anchored!(shacl_pattern) do
    body =
      shacl_pattern
      |> String.replace_prefix("^", "")
      |> String.replace_suffix("$", "")

    case Regex.compile("\\A#{body}\\z") do
      {:ok, re} ->
        re

      {:error, reason} ->
        raise CompileError,
          description:
            "WorkOrderShape: cannot compile SHACL pattern #{inspect(shacl_pattern)}: #{inspect(reason)}"
    end
  end
end

defmodule GgenIgniter.SemanticJira.WorkOrderShape do
  @moduledoc """
  Compile-time witness of `work-order.shacl.ttl` patterns for the kernel.

  Digests stay untouched: this module derives base standings and scalar
  regexes only. It never invents `@definition_fields` / `@required`
  membership from `sh:minCount` (Phase 2 annotation gate; not here).

  Pattern of `GgenIgniter.Refusals`: `@external_resource` on the shape
  file so editing SHACL recompiles this module. `REFUSED(...)` stays a
  separate admission clause in `GgenIgniter.SemanticJira` (today's split);
  only the closed base atoms are derived from the `sj:standing` alternation.
  """

  alias GgenIgniter.SemanticJira.WorkOrderShape.Parse

  @shape_path Path.expand(
                "../../../priv/ggen/semantic-jira-pack/shapes/work-order.shacl.ttl",
                __DIR__
              )
  @external_resource @shape_path

  @shape_source File.read!(@shape_path)
  @shape_basename Path.basename(@shape_path)

  # Frozen kernel list (pre-Phase-1 hand SoT). Parse drift raises CompileError
  # rather than silently reminting admission behaviour.
  @frozen_standings ~w(UNKNOWN PARTIAL_ALIVE ALIVE BLOCKED BUILD_BROKEN UNSUPPORTED)

  @standing_pattern Parse.property_pattern!(@shape_source, "sj:standing", @shape_basename)
  @standings Parse.derive_base_standings!(@standing_pattern, @frozen_standings)

  @sha_source Parse.property_pattern!(@shape_source, "sj:baseSha", @shape_basename)
  @repo_source Parse.property_pattern!(@shape_source, "sj:repository", @shape_basename)
  @pack_source Parse.property_pattern!(@shape_source, "sj:targetPack", @shape_basename)
  @digest_source Parse.property_pattern!(@shape_source, "sj:admissionDigest", @shape_basename)

  @sha Parse.elixir_anchored!(@sha_source)
  @repo Parse.elixir_anchored!(@repo_source)
  @pack_name Parse.elixir_anchored!(@pack_source)
  @digest Parse.elixir_anchored!(@digest_source)

  @doc "Absolute path of the work-order SHACL shape this module witnesses."
  @spec shape_path() :: String.t()
  def shape_path, do: @shape_path

  @doc """
  Closed base standing atoms derived from the `sj:standing` SHACL alternation,
  excluding the `REFUSED(...)` arm (kept as a separate kernel clause).
  """
  @spec standings() :: [String.t()]
  def standings, do: @standings

  @doc "Frozen expectation the derived standings must equal (digest-blind pin)."
  @spec frozen_standings() :: [String.t()]
  def frozen_standings, do: @frozen_standings

  @doc "Compiled SHA-1 hex pattern from `sj:baseSha` (Elixir `\\A`/`\\z` anchors)."
  @spec sha_pattern() :: Regex.t()
  def sha_pattern, do: @sha

  @doc "Compiled `owner/name` repository pattern from `sj:repository`."
  @spec repo_pattern() :: Regex.t()
  def repo_pattern, do: @repo

  @doc "Compiled pack-name FORMAT pattern from `sj:targetPack`."
  @spec pack_name_pattern() :: Regex.t()
  def pack_name_pattern, do: @pack_name

  @doc "Compiled `sha256:<64 hex>` digest pattern from `sj:admissionDigest`."
  @spec digest_pattern() :: Regex.t()
  def digest_pattern, do: @digest

  @doc "Raw SHACL `sh:pattern` string for `sj:standing` (anchors included)."
  @spec standing_shacl_pattern() :: String.t()
  def standing_shacl_pattern, do: @standing_pattern
end
