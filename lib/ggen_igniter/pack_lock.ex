defmodule GgenIgniter.PackLock do
  @moduledoc """
  Pack lockfile: pins each pack to the sha256 of its on-disk content so a
  tampered or silently changed pack is detected instead of trusted.

  ## Digest

  `digest/1` is sha256 hex over a deterministic walk of the pack directory:
  files sorted by relative path (`/`-separated), each contributing
  `tag <> path <> <<0>> <> <byte length> <> <<0>> <> content` where `tag` is
  `"F"` for a regular file and `"L"` for a symlink (domain separation: a
  symlink and a regular file can never collide). `.git`, `_build` and
  `.DS_Store` are ignored. mtimes, permissions and directory-creation order
  never enter the digest.

  Symlinks are FOLLOWED, exactly as the pack loaders (`Path.wildcard`/`File.read`)
  follow them: a symlink to a regular file inside the pack contributes the
  RESOLVED content (tag `"L"`). A symlink whose resolved target lies outside
  the pack root, any directory symlink, and any symlink loop or dangling link
  is refused (`{:pack_symlink_escape, detail}`, `REFUSED:PACK_SYMLINK_ESCAPE`);
  an unreadable file is `{:pack_file_unreadable, detail}`
  (`REFUSED:PACK_FILE_UNREADABLE`). `digest_checked/1` returns these as
  `{:error, reason}`; `digest/1` raises `GgenIgniter.PackLock.Refusal`.

  ## Lockfile (`ggen_igniter.pack.lock`)

  JSON with sorted keys (deterministic bytes; precedent: this repo's other
  durable records under `.ggen_igniter/` are JSON):

      {"packs": {"<name>": {"locked_by": "<ggen_igniter version>",
                            "name": "<name>", "sha256": "<hex>",
                            "source": "<spec or path>", "version": "<v>|null"}},
       "schema_version": "1"}

  ## Seam (WA2 <-> WA3)

  `check/2` returns `:ok`, `{:error, {:pack_digest_mismatch, %{pack: name,
  expected: hex, actual: hex}}}`, `{:error, {:lock_missing, lock_path}}`
  (lock file absent, or present with no entry for the pack),
  `{:error, {:lock_invalid, lock_path}}` (lock file present but not a valid
  lock: never treated as missing), `{:error, {:pack_symlink_escape, detail}}`
  or `{:error, {:pack_file_unreadable, detail}}`. The pack name is
  `Path.basename(pack_dir)`.

  ## Concurrency

  `write/2` writes a temp file in the same directory and renames it (atomic
  replace: readers see the old or the new file, never a partial one).
  `update/3` serializes read-modify-write across processes AND OS processes via
  an atomic `File.mkdir` on `<lock>.lockdir` (`:global.trans` would not
  protect two concurrent `mix` invocations).
  """

  defmodule Refusal do
    @moduledoc "Typed pack-lock refusal raised by `GgenIgniter.PackLock.digest/1` and `entry/3`."
    defexception [:reason]

    @impl true
    def message(%{reason: reason}), do: GgenIgniter.PackLock.refusal_text(reason)
  end

  @schema_version "1"
  @ignored [".git", "_build", ".DS_Store"]

  @type entry :: %{required(String.t()) => String.t() | nil}
  @type lock :: %{required(String.t()) => term()}

  @doc "Default lockfile name."
  @spec default_lock_path() :: String.t()
  def default_lock_path, do: "ggen_igniter.pack.lock"

  @doc """
  sha256 hex over the deterministic content walk of `pack_dir`. Raises
  `GgenIgniter.PackLock.Refusal` on a symlink escape or unreadable file.
  """
  @spec digest(String.t()) :: String.t()
  def digest(pack_dir) do
    case digest_checked(pack_dir) do
      {:ok, hex} -> hex
      {:error, reason} -> raise Refusal, reason: reason
    end
  end

  @doc "Like `digest/1` but returns `{:error, {:pack_symlink_escape | :pack_file_unreadable, detail}}`."
  @spec digest_checked(String.t()) ::
          {:ok, String.t()}
          | {:error, {:pack_symlink_escape | :pack_file_unreadable, String.t()}}
  def digest_checked(pack_dir) do
    with {:ok, root} <- realpath(pack_dir),
         {:ok, records} <- walk(root, root, "") do
      Enum.reduce_while(Enum.sort(records), {:ok, :crypto.hash_init(:sha256)}, fn
        {rel, tag, path}, {:ok, acc} ->
          case File.read(path) do
            {:ok, content} ->
              {:cont,
               {:ok,
                :crypto.hash_update(acc, [
                  tag,
                  rel,
                  0,
                  Integer.to_string(byte_size(content)),
                  0,
                  content
                ])}}

            {:error, reason} ->
              {:halt, {:error, {:pack_file_unreadable, "#{rel}: #{:file.format_error(reason)}"}}}
          end
      end)
      |> case do
        {:ok, ctx} -> {:ok, ctx |> :crypto.hash_final() |> Base.encode16(case: :lower)}
        {:error, _} = err -> err
      end
    end
  end

  # Returns {:ok, [{rel, tag, abs_path_to_read}]} | {:error, reason}.
  defp walk(root, dir, rel) do
    case File.ls(dir) do
      {:error, reason} ->
        {:error, {:pack_file_unreadable, "#{display(rel)}: #{:file.format_error(reason)}"}}

      {:ok, names} ->
        names
        |> Enum.reject(&(&1 in @ignored))
        |> Enum.sort()
        |> Enum.reduce_while({:ok, []}, fn name, {:ok, acc} ->
          child = if rel == "", do: name, else: rel <> "/" <> name
          abs = Path.join(dir, name)

          case classify(root, abs, child) do
            {:file, tag, path} ->
              {:cont, {:ok, [{child, tag, path} | acc]}}

            :dir ->
              case walk(root, abs, child) do
                {:ok, more} -> {:cont, {:ok, more ++ acc}}
                {:error, _} = err -> {:halt, err}
              end

            {:error, _} = err ->
              {:halt, err}
          end
        end)
    end
  end

  defp display(""), do: "."
  defp display(rel), do: rel

  defp classify(root, abs, rel) do
    case File.lstat(abs) do
      {:ok, %File.Stat{type: :directory}} ->
        :dir

      {:ok, %File.Stat{type: :symlink}} ->
        classify_symlink(root, abs, rel)

      {:ok, _} ->
        {:file, "F", abs}

      {:error, reason} ->
        {:error, {:pack_file_unreadable, "#{rel}: #{:file.format_error(reason)}"}}
    end
  end

  defp classify_symlink(root, abs, rel) do
    case realpath(abs) do
      {:error, {:pack_symlink_escape, d}} ->
        {:error, {:pack_symlink_escape, "#{rel}: #{d}"}}

      {:ok, resolved} ->
        cond do
          not inside?(root, resolved) ->
            {:error, {:pack_symlink_escape, "#{rel} -> #{resolved} (outside pack root)"}}

          true ->
            case File.stat(resolved) do
              {:ok, %File.Stat{type: :directory}} ->
                {:error, {:pack_symlink_escape, "#{rel} -> #{resolved} (directory symlink)"}}

              {:ok, _} ->
                {:file, "L", resolved}

              {:error, reason} ->
                {:error, {:pack_file_unreadable, "#{rel}: #{:file.format_error(reason)}"}}
            end
        end
    end
  end

  defp inside?(root, path), do: path == root or String.starts_with?(path, root <> "/")

  # Resolves every symlink in `path` (component by component). Loops (more than
  # @max_links link expansions) are a typed refusal, never a hang.
  @max_links 40
  defp realpath(path) do
    [first | rest] = path |> Path.expand() |> Path.split()
    resolve(first, rest, 0)
  end

  defp resolve(acc, [], _n), do: {:ok, acc}
  defp resolve(acc, ["." | rest], n), do: resolve(acc, rest, n)
  defp resolve(acc, [".." | rest], n), do: resolve(Path.dirname(acc), rest, n)

  defp resolve(acc, [comp | rest], n) do
    cand = Path.join(acc, comp)

    case File.read_link(cand) do
      {:ok, _} when n >= @max_links ->
        {:error, {:pack_symlink_escape, "symlink loop at #{cand}"}}

      {:ok, target} ->
        [thead | ttail] = Path.split(target)

        if thead == "/",
          do: resolve("/", ttail ++ rest, n + 1),
          else: resolve(acc, [thead | ttail] ++ rest, n + 1)

      {:error, _} ->
        resolve(cand, rest, n)
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

  @doc """
  Writes `lock` as deterministic JSON (sorted keys, trailing newline),
  atomically: temp file in the same directory, then `File.rename!/2`.
  """
  @spec write(String.t(), lock()) :: :ok
  def write(lock_path, lock) do
    dir = Path.dirname(lock_path)
    File.mkdir_p!(dir)

    tmp =
      Path.join(
        dir,
        ".#{Path.basename(lock_path)}.tmp.#{System.pid()}.#{System.unique_integer([:positive])}"
      )

    try do
      File.write!(tmp, encode(lock))
      File.rename!(tmp, lock_path)
    after
      File.rm(tmp)
    end

    :ok
  end

  @doc "Puts (adds or replaces) `entry` under `name`."
  @spec put(lock(), String.t(), entry()) :: lock()
  def put(lock, name, entry) do
    lock
    |> Map.put_new("schema_version", @schema_version)
    |> Map.update("packs", %{name => entry}, &Map.put(&1, name, entry))
  end

  @lock_timeout_ms 30_000
  @stale_lock_s 120

  @doc """
  Serialized read-modify-write of the lockfile. `fun` receives the current lock
  (`empty/0` when the file is absent) and returns `{:ok, new_lock}` (written
  atomically) or `{:error, reason}` (nothing written). An existing but invalid
  lock is `{:error, {:lock_invalid, path}}` and is never overwritten unless
  `force: true` is given. Mutual exclusion is an atomic `File.mkdir` of
  `<lock>.lockdir` (works across OS processes; stale dirs older than
  #{@stale_lock_s}s are reclaimed).
  """
  @spec update(String.t(), keyword(), (lock() -> {:ok, lock()} | {:error, term()})) ::
          {:ok, lock()} | {:error, term()}
  def update(lock_path, opts \\ [], fun) do
    File.mkdir_p!(Path.dirname(lock_path))
    lockdir = lock_path <> ".lockdir"
    acquire(lockdir, System.monotonic_time(:millisecond) + @lock_timeout_ms)

    try do
      with {:ok, lock} <- load_for_update(lock_path, opts[:force] == true),
           {:ok, new} <- fun.(lock) do
        :ok = write(lock_path, new)
        {:ok, new}
      end
    after
      File.rmdir(lockdir)
    end
  end

  defp load_for_update(lock_path, force?) do
    case read(lock_path) do
      {:ok, l} -> {:ok, l}
      {:error, {:lock_missing, _}} -> {:ok, empty()}
      {:error, {:lock_invalid, _}} when force? -> {:ok, empty()}
      {:error, _} = err -> err
    end
  end

  defp acquire(lockdir, deadline) do
    case File.mkdir(lockdir) do
      :ok ->
        :ok

      {:error, :eexist} ->
        cond do
          stale?(lockdir) ->
            File.rmdir(lockdir)
            acquire(lockdir, deadline)

          System.monotonic_time(:millisecond) > deadline ->
            raise "pack lock busy: #{lockdir} held for over #{@lock_timeout_ms}ms"

          true ->
            Process.sleep(5)
            acquire(lockdir, deadline)
        end

      {:error, reason} ->
        raise "cannot create #{lockdir}: #{:file.format_error(reason)}"
    end
  end

  defp stale?(lockdir) do
    case File.stat(lockdir, time: :posix) do
      {:ok, %File.Stat{mtime: m}} -> System.os_time(:second) - m > @stale_lock_s
      _ -> false
    end
  end

  @doc """
  Runs `fun` with a fresh unique staging directory under the system tmp dir and
  removes it afterwards (success or raise). Returns `fun`'s value.
  """
  @spec with_staging((String.t() -> result)) :: result when result: term()
  def with_staging(fun) do
    staging =
      Path.join(
        System.tmp_dir!(),
        "ggen_igniter_pack_fetch_#{System.unique_integer([:positive])}"
      )

    File.mkdir_p!(staging)

    try do
      fun.(staging)
    after
      File.rm_rf(staging)
    end
  end

  @doc "Verifies the pack at `pack_dir` against its entry in `lock_path`."
  @spec check(String.t(), String.t()) ::
          :ok
          | {:error,
             {:pack_digest_mismatch,
              %{pack: String.t(), expected: String.t(), actual: String.t()}}}
          | {:error, {:lock_missing, String.t()}}
          | {:error, {:lock_invalid, String.t()}}
          | {:error, {:pack_symlink_escape | :pack_file_unreadable, String.t()}}
  def check(pack_dir, lock_path) do
    name = Path.basename(pack_dir)

    with {:ok, lock} <- read(lock_path),
         {:ok, %{"sha256" => expected}} <- Map.fetch(lock["packs"], name),
         {:ok, actual} <- digest_checked(pack_dir) do
      if actual == expected do
        :ok
      else
        {:error, {:pack_digest_mismatch, %{pack: name, expected: expected, actual: actual}}}
      end
    else
      {:error, _} = err -> err
      _ -> {:error, {:lock_missing, lock_path}}
    end
  end

  @doc "Refusal text form: `REFUSED:<CODE> <detail>`."
  @spec refusal_text(tuple()) :: String.t()
  def refusal_text({:pack_digest_mismatch, %{pack: p, expected: e, actual: a}}),
    do: "REFUSED:PACK_DIGEST_MISMATCH pack=#{p} expected=#{e} actual=#{a}"

  def refusal_text({:lock_missing, path}), do: "REFUSED:PACK_LOCK_MISSING #{path}"
  def refusal_text({:lock_invalid, path}), do: "REFUSED:PACK_LOCK_INVALID #{path}"
  def refusal_text({:pack_symlink_escape, d}), do: "REFUSED:PACK_SYMLINK_ESCAPE #{d}"
  def refusal_text({:pack_file_unreadable, d}), do: "REFUSED:PACK_FILE_UNREADABLE #{d}"

  defp encode(term), do: (term |> to_ordered() |> Jason.encode!(pretty: true)) <> "\n"

  defp to_ordered(map) when is_map(map) do
    map
    |> Enum.sort_by(fn {k, _} -> to_string(k) end)
    |> Enum.map(fn {k, v} -> {to_string(k), to_ordered(v)} end)
    |> Jason.OrderedObject.new()
  end

  defp to_ordered(other), do: other
end
