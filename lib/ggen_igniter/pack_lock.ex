defmodule GgenIgniter.PackLock do
  @moduledoc """
  Pack lockfile: pins each pack to the sha256 of its on-disk content so a
  tampered or silently changed pack is detected instead of trusted.

  ## Digest

  `digest/1` is sha256 hex over a deterministic walk of the pack directory:
  files sorted by relative path (`/`-separated), each contributing
  `path <> <<0>> <> <byte length> <> <<0>> <> content`. `.git`, `_build` and
  `.DS_Store` are ignored. mtimes, permissions and directory-creation order
  never enter the digest. A symlink contributes its link target text.

  ## Lockfile (`ggen_igniter.pack.lock`)

  JSON with sorted keys (deterministic bytes; precedent: this repo's other
  durable records under `.ggen_igniter/` are JSON):

      {"packs": {"<name>": {"locked_by": "<ggen_igniter version>",
                            "name": "<name>", "sha256": "<hex>",
                            "source": "<spec or path>", "version": "<v>|null"}},
       "schema_version": "1"}

  ## Seam (WA2 <-> WA3)

  `check/2` returns `:ok`, `{:error, {:pack_digest_mismatch, %{pack: name,
  expected: hex, actual: hex}}}`, or `{:error, {:lock_missing, lock_path}}`
  (lock file absent, or present with no entry for the pack). The pack name is
  `Path.basename(pack_dir)`.
  """

  @schema_version "1"
  @ignored [".git", "_build", ".DS_Store"]

  @type entry :: %{required(String.t()) => String.t() | nil}
  @type lock :: %{required(String.t()) => term()}

  @doc "Default lockfile name."
  @spec default_lock_path() :: String.t()
  def default_lock_path, do: "ggen_igniter.pack.lock"

  @doc "sha256 hex over the deterministic content walk of `pack_dir`."
  @spec digest(String.t()) :: String.t()
  def digest(pack_dir) do
    pack_dir
    |> walk("")
    |> Enum.sort()
    |> Enum.reduce(:crypto.hash_init(:sha256), fn rel, acc ->
      content = read_content(Path.join(pack_dir, rel))
      :crypto.hash_update(acc, [rel, 0, Integer.to_string(byte_size(content)), 0, content])
    end)
    |> :crypto.hash_final()
    |> Base.encode16(case: :lower)
  end

  defp walk(root, rel) do
    dir = if rel == "", do: root, else: Path.join(root, rel)

    dir
    |> File.ls!()
    |> Enum.reject(&(&1 in @ignored))
    |> Enum.flat_map(fn name ->
      child = if rel == "", do: name, else: rel <> "/" <> name

      case File.lstat!(Path.join(root, child)) do
        %File.Stat{type: :directory} -> walk(root, child)
        _ -> [child]
      end
    end)
  end

  defp read_content(path) do
    case File.read_link(path) do
      {:ok, target} -> "symlink:" <> target
      {:error, _} -> File.read!(path)
    end
  end

  @doc "Builds a lock entry for the pack at `pack_dir`."
  @spec entry(String.t(), String.t(), String.t() | nil) :: entry()
  def entry(pack_dir, source, version \\ nil) do
    name = Path.basename(pack_dir)

    %{
      "name" => name,
      "source" => source,
      "version" => version || manifest_version(pack_dir),
      "sha256" => digest(pack_dir),
      "locked_by" => locked_by()
    }
  end

  defp manifest_version(pack_dir) do
    with {:ok, toml} <- File.read(Path.join(pack_dir, "pack.toml")),
         [_, v] <- Regex.run(~r/^\s*version\s*=\s*"([^"]+)"/m, toml) do
      v
    else
      _ -> nil
    end
  end

  defp locked_by do
    case Application.spec(:ggen_igniter, :vsn) do
      nil -> "unknown"
      vsn -> to_string(vsn)
    end
  end

  @doc "An empty lock."
  @spec empty() :: lock()
  def empty, do: %{"schema_version" => @schema_version, "packs" => %{}}

  @doc "Reads the lockfile. `{:error, {:lock_missing, path}}` when absent."
  @spec read(String.t()) ::
          {:ok, lock()} | {:error, {:lock_missing, String.t()} | {:lock_invalid, String.t()}}
  def read(lock_path) do
    case File.read(lock_path) do
      {:ok, bin} ->
        case Jason.decode(bin) do
          {:ok, %{"packs" => packs} = lock} when is_map(packs) -> {:ok, lock}
          _ -> {:error, {:lock_invalid, lock_path}}
        end

      {:error, _} ->
        {:error, {:lock_missing, lock_path}}
    end
  end

  @doc "Writes `lock` as deterministic JSON (sorted keys, trailing newline)."
  @spec write(String.t(), lock()) :: :ok
  def write(lock_path, lock) do
    File.mkdir_p!(Path.dirname(lock_path))
    File.write!(lock_path, encode(lock))
  end

  @doc "Puts (adds or replaces) `entry` under `name`."
  @spec put(lock(), String.t(), entry()) :: lock()
  def put(lock, name, entry) do
    lock
    |> Map.put_new("schema_version", @schema_version)
    |> Map.update("packs", %{name => entry}, &Map.put(&1, name, entry))
  end

  @doc "Verifies the pack at `pack_dir` against its entry in `lock_path`."
  @spec check(String.t(), String.t()) ::
          :ok
          | {:error,
             {:pack_digest_mismatch,
              %{pack: String.t(), expected: String.t(), actual: String.t()}}}
          | {:error, {:lock_missing, String.t()}}
  def check(pack_dir, lock_path) do
    name = Path.basename(pack_dir)

    with {:ok, lock} <- read(lock_path),
         {:ok, %{"sha256" => expected}} <- Map.fetch(lock["packs"], name) do
      case digest(pack_dir) do
        ^expected ->
          :ok

        actual ->
          {:error, {:pack_digest_mismatch, %{pack: name, expected: expected, actual: actual}}}
      end
    else
      {:error, {:lock_invalid, _}} -> {:error, {:lock_missing, lock_path}}
      {:error, _} = err -> err
      _ -> {:error, {:lock_missing, lock_path}}
    end
  end

  @doc "Refusal text form: `REFUSED:<CODE> <detail>`."
  @spec refusal_text({:pack_digest_mismatch, map()} | {:lock_missing, String.t()}) :: String.t()
  def refusal_text({:pack_digest_mismatch, %{pack: p, expected: e, actual: a}}),
    do: "REFUSED:PACK_DIGEST_MISMATCH pack=#{p} expected=#{e} actual=#{a}"

  def refusal_text({:lock_missing, path}), do: "REFUSED:PACK_LOCK_MISSING #{path}"

  defp encode(term), do: (term |> to_ordered() |> Jason.encode!(pretty: true)) <> "\n"

  defp to_ordered(map) when is_map(map) do
    map
    |> Enum.sort_by(fn {k, _} -> to_string(k) end)
    |> Enum.map(fn {k, v} -> {to_string(k), to_ordered(v)} end)
    |> Jason.OrderedObject.new()
  end

  defp to_ordered(other), do: other
end
