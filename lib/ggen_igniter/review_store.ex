defmodule GgenIgniter.ReviewStore do
  @moduledoc """
  The per-sha review round store: exclusive-append `rounds.jsonl`,
  per-round diff snapshots, and a terminal `summary.json`, all under
  `<base_dir>/.ggen_igniter/reviews/<sha>/`.

  Append semantics mirror `GgenIgniter.Receipt.append!/2`
  (`lib/ggen_igniter/receipt.ex`): one JSON line per round, `File.write!/3`
  with `[:append]` only, under this store's own real `GgenIgniter.Lock` on
  the reviews directory — never truncate, never rewrite a prior line. Every
  line carries a `line_hash` (`GgenIgniter.Digest.sha256/1` over the
  canonical line JSON without the hash itself) so a torn or doctored line
  is detectable on read.

  Reads are partial-line tolerant: a trailing torn line (real crash
  mid-append) is skipped, never a crash, matching the recover-by-discard
  law documented on `GgenIgniter.Receipt.append!/2`.

  NOTE: this is the review-round store for the convergence loop
  (`GgenIgniter.Convergence`) and is deliberately DISTINCT from lane L2's
  `lib/ggen_igniter/review/store.ex`.
  """

  alias GgenIgniter.Digest

  @reviews_reldir Path.join(".ggen_igniter", "reviews")

  @typedoc "One decoded round record line."
  @type round_line :: map()

  @doc "The reviews directory for `base_dir`: `<base_dir>/.ggen_igniter/reviews`."
  @spec dir(String.t()) :: String.t()
  def dir(base_dir), do: Path.join(base_dir, @reviews_reldir)

  @doc "The per-sha store directory: `<base_dir>/.ggen_igniter/reviews/<sha>`."
  @spec sha_dir(String.t(), String.t()) :: String.t()
  def sha_dir(base_dir, sha), do: Path.join([dir(base_dir), to_string(sha)])

  @doc "The rounds log path: `<sha_dir>/rounds.jsonl`."
  @spec rounds_path(String.t(), String.t()) :: String.t()
  def rounds_path(base_dir, sha), do: Path.join(sha_dir(base_dir, sha), "rounds.jsonl")

  @doc "The per-round diff snapshot path: `<sha_dir>/diff/<round>.patch`."
  @spec diff_path(String.t(), String.t(), pos_integer()) :: String.t()
  def diff_path(base_dir, sha, round),
    do: Path.join([sha_dir(base_dir, sha), "diff", "#{round}.patch"])

  @doc "The terminal summary path: `<sha_dir>/summary.json`."
  @spec summary_path(String.t(), String.t()) :: String.t()
  def summary_path(base_dir, sha), do: Path.join(sha_dir(base_dir, sha), "summary.json")

  @doc "Struct-opts constructor matching the loop's `ReviewStore.new(base_dir:, sha:)` call shape."
  @spec new(keyword()) :: %{base_dir: String.t(), sha: String.t()}
  def new(opts) when is_list(opts) do
    %{base_dir: Keyword.fetch!(opts, :base_dir), sha: to_string(Keyword.fetch!(opts, :sha))}
  end

  @doc """
  Builds a round record from `GgenIgniter.Convergence.decide/3`'s map,
  stamps `line_hash` (`Digest.sha256` over the line JSON without the hash),
  appends it as one exclusive JSON line to `rounds.jsonl` under this
  store's own `GgenIgniter.Lock`, and returns the stamped map.
  """
  @spec append_round!(String.t(), String.t(), map()) :: map()
  def append_round!(base_dir, sha, record) when is_map(record) do
    path = rounds_path(base_dir, sha)
    File.mkdir_p!(Path.dirname(path))

    line =
      record
      |> normalize_record()
      |> Map.put("ts", Map.get(normalize_record(record), "ts") ||
        DateTime.utc_now() |> DateTime.to_iso8601())
      |> stamp_line_hash()

    json = json_encode(line)

    {:ok, lock} = GgenIgniter.Lock.acquire(Path.dirname(path))

    try do
      # Line-separator repair: a torn prior append leaves the file with no
      # trailing newline; writing the new line directly would fuse it into
      # the torn bytes. A leading "\n" keeps every completed line decodable.
      prefix = if last_byte(path) == "\n", do: "", else: "\n"
      File.write!(path, prefix <> json <> "\n", [:append])
    after
      GgenIgniter.Lock.release(lock)
    end

    line
  end

  @doc """
  Writes `diff_text` as the round's snapshot `diff/<round>.patch` (a real
  file on disk, re-readable for later rounds' hunk-id comparison).
  """
  @spec snapshot_diff!(String.t(), String.t(), pos_integer(), String.t()) :: String.t()
  def snapshot_diff!(base_dir, sha, round, diff_text) when is_binary(diff_text) do
    path = diff_path(base_dir, sha, round)
    File.mkdir_p!(Path.dirname(path))
    File.write!(path, diff_text)
    path
  end

  @doc """
  Writes the terminal `summary.json` (atomic: temp file + rename, since a
  summary is a single point-in-time snapshot, NOT an append log — see
  `GgenIgniter.Receipt.append!/2`'s moduledoc for the split).
  """
  @spec write_summary!(String.t(), String.t(), map()) :: String.t()
  def write_summary!(base_dir, sha, summary) when is_map(summary) do
    path = summary_path(base_dir, sha)
    File.mkdir_p!(Path.dirname(path))
    tmp = path <> ".tmp"
    File.write!(tmp, Jason.encode!(summary, pretty: true))
    File.rename!(tmp, path)
    path
  end

  @doc "Reads the terminal `summary.json` back, or `nil` when no terminal state was reached yet."
  @spec read_summary(String.t(), String.t()) :: map() | nil
  def read_summary(base_dir, sha) do
    case File.read(summary_path(base_dir, sha)) do
      {:ok, json} -> Jason.decode!(json)
      {:error, _} -> nil
    end
  end

  @doc """
  Reads every round line back from `rounds.jsonl` in append order.
  Partial-line tolerant: a trailing line that fails `Jason.decode/1` (torn
  write) is DISCARDED, never a crash; each surviving line's `line_hash` is
  verified and a mismatch marks the line `"line_hash_valid" => false`
  rather than dropping it (a doctored line is evidence, not silence).
  """
  @spec read_rounds(String.t(), String.t()) :: [round_line()]
  def read_rounds(base_dir, sha) do
    case File.read(rounds_path(base_dir, sha)) do
      {:ok, content} ->
        content
        |> String.split("\n", trim: true)
        |> Enum.flat_map(fn line ->
          case Jason.decode(line) do
            {:ok, map} -> [verify_line(map)]
            {:error, _} -> []
          end
        end)

      {:error, _} ->
        []
    end
  end

  defp verify_line(%{"line_hash" => hash} = map) do
    expected = Digest.sha256(line_json_for_hash(map))

    Map.put(map, "line_hash_valid", expected == hash)
  end

  defp verify_line(map), do: map

  # -- private --

  defp normalize_record(record) do
    record
    |> Enum.map(fn {k, v} -> {Atom.to_string(k), jsonable(v)} end)
    |> Enum.into(%{})
  end

  defp jsonable(%DateTime{} = dt), do: DateTime.to_iso8601(dt)

  defp jsonable(v) when is_list(v), do: Enum.map(v, &jsonable/1)
  defp jsonable(v) when is_map(v), do: Map.new(v, fn {k, x} -> {to_string(k), jsonable(x)} end)
  defp jsonable(nil), do: nil
  defp jsonable(v) when is_atom(v) and not is_boolean(v), do: Atom.to_string(v)
  defp jsonable(v), do: v

  defp stamp_line_hash(record_map) do
    Map.put(record_map, "line_hash", Digest.sha256(line_json_for_hash(record_map)))
  end

  # The exact JSON a line's hash covers: the line map WITHOUT "line_hash"
  # (and without a prior "line_hash_valid" marker), key-sorted, so hash
  # verification is deterministic across encode/decode round-trips.
  defp line_json_for_hash(map) do
    map
    |> Map.drop(["line_hash", "line_hash_valid"])
    |> Enum.sort_by(fn {k, _} -> k end)
    |> Enum.into(%{})
    |> Jason.encode!()
  end

  defp last_byte(path) do
    case File.open(path, [:read, :binary]) do
      {:ok, fd} ->
        {:ok, size} = :file.position(fd, :eof)
        bin = if size == 0, do: <<>>, else: elem(:file.pread(fd, size - 1, 1), 1)
        :file.close(fd)
        bin

      {:error, _} ->
        nil
    end
  end

  defp json_encode(line_map) do
    line_map
    |> Enum.sort_by(fn {k, _} -> k end)
    |> Enum.into(%{})
    |> Jason.encode!()
  end
end
