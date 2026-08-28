defmodule GgenIgniter.Actuate do
  @moduledoc """
  Writes a rendered source string to a file, with write-safety guards modeled
  on the real Rust ggen's `ggen-engine/src/write.rs` decision table (idempotent
  no-op detection, `unless_exists`, `skip_if`).

  Three real actuation paths exist, all driven from `Mix.Tasks.GgenIgniter.Sync`:

    * `write_new_file!/2` -- unconditional create, used internally.
    * `write_file!/3` (`mode: file`, no `inject:`) -- guarded whole-file
      write/no-op/skip, the default for a `mode: file` template.
    * `inject_content!/5` (`mode: file`, frontmatter `inject: true`) -- guarded
      splice into an EXISTING file, anchored on the template's `before:`/
      `after:`/`at_line:` frontmatter field. `Mix.Tasks.GgenIgniter.Sync`
      resolves the frontmatter's `before`/`after`
      (`GgenIgniter.Frontmatter.MatchSpec.t()`) into this function's real
      `marker` arg (`String.t() | Regex.t() | nil`) -- see
      `Mix.Tasks.GgenIgniter.Sync`'s private `match_spec_to_marker!/2` for the
      literal-vs-structured `MatchRule` conversion, including which
      `matcher`/`scope`/`occurrence`/`trim` combinations are honored and which
      raise a named "not yet supported" error rather than being silently
      dropped.

  Igniter AST-patch actuation (a real `Sourceror`/`Igniter.Code`-based
  structural patch, as opposed to this module's line-anchored text splice) for
  incremental changes to an EXISTING file remains an explicit, disclosed
  follow-on -- not implemented this pass (see pack.toml).

  ## Atomic-write guarantee (`write_file!/3`'s `:written` outcome only)

  When `write_file!/3` actually writes (the `:written` outcome, real -- not
  `:dry_run`), it does so via a real write-to-temp-then-`File.rename!/2`
  sequence, not a direct `File.write!/2` to the final path:

    1. Render the content to a sibling temp file in the SAME directory as the
       final path (e.g. `path <> ".ggen_igniter.tmp.<unique_integer>"`) --
       same directory, so the subsequent rename is guaranteed to stay on the
       same filesystem/mount (a cross-filesystem rename is not atomic and, on
       most platforms, simply fails rather than silently copying).
    2. `File.write!/2` the full content to that temp file.
    3. Best-effort `fsync` the temp file's file descriptor via `:file.sync/1`
       (when the OS/filesystem honors fsync -- see caveats below) before the
       rename, so the temp file's bytes are durable before it becomes visible
       under the final name.
    4. `File.rename!/2` the temp file onto the final `path`.

  **What this actually guarantees, precisely:** on POSIX filesystems (Linux
  ext4/xfs, macOS APFS/HFS+) where `rename(2)` is atomic per the POSIX
  standard, an observer of `path` NEVER sees a partially-written file --
  `path` either still holds its old content (rename hasn't happened yet) or
  the new content (rename has happened), never a half-written intermediate
  state, even if this process is killed mid-write. This holds because the
  temp file is invisible under `path`'s name until the single atomic rename
  syscall completes.

  **What this does NOT guarantee, stated honestly rather than implied:**

    * **Windows**: `File.rename!/2` on Windows (`MoveFileEx`-backed) is not
      guaranteed atomic when the destination already exists on all Windows
      filesystem/OS version combinations the way POSIX `rename(2)` is --
      Erlang/OTP's underlying implementation has evolved across versions and
      is not something this module independently verifies here. Treat the
      atomicity guarantee above as POSIX-only.
    * **NFS and other network filesystems**: `rename(2)` atomicity is a
      LOCAL-filesystem POSIX guarantee. NFS (especially NFSv3) has documented
      non-atomic-rename edge cases under concurrent access from multiple
      clients. If `path` lives on an NFS mount, this guarantee weakens to
      "best effort," not "atomic."
    * **fsync durability**: step 3's `:file.sync/1` call is best-effort --
      it's issued when available, but this module does not verify the
      underlying storage/OS actually honors the fsync barrier (e.g. some
      virtualized/network storage acknowledges fsync without a real durable
      flush). Treat fsync here as "reduces the durability window," not as an
      unconditional crash-safety proof.
    * **Directory-entry durability**: this implementation does not fsync the
      containing DIRECTORY's file descriptor after the rename, which a
      maximally paranoid crash-safety design would also do (to guarantee the
      renamed directory entry itself survives a concurrent power loss, not
      just the file's data). That refinement is out of scope for this pass.
    * **Scope**: this guarantee applies ONLY to `write_file!/3`'s real
      `:written` outcome. `:dry_run` still performs zero I/O (unchanged).
      `:unchanged`/`:skipped_exists`/`:skipped_match` never write, so there is
      nothing to make atomic. `inject_content!/5` (existing-file splice) and
      `eval_code!/2` (in-memory eval, no disk write) are explicitly OUT OF
      SCOPE for this guarantee -- they still use a direct `File.write!/2` (or,
      for eval, no write at all).
  """

  @doc "Writes `content` to `path`, creating parent directories as needed."
  @spec write_new_file!(String.t(), String.t()) :: :ok
  def write_new_file!(path, content) do
    File.mkdir_p!(Path.dirname(path))
    File.write!(path, content)
  end

  @typedoc """
  Outcome of a guarded write:
  - `:written` -- the file did not exist (or existed with differing content
    and no skip guard matched), and was written.
  - `:unchanged` -- the file already existed with byte-identical content;
    write skipped (idempotent no-op, always checked, no opt-in flag).
  - `:skipped_exists` -- `unless_exists: true` and the target already existed
    (regardless of content).
  - `:skipped_match` -- `skip_if: pattern` and the existing file's content
    matched that substring/regex.
  """
  @type outcome :: :written | :unchanged | :skipped_exists | :skipped_match

  @doc """
  Writes `content` to `path`, creating parent directories as needed, applying
  write-safety guards in this decision order (first match wins), mirroring
  the real Rust ggen's `plan_write` in `ggen-engine/src/write.rs`:

    1. `unless_exists: true` && target exists -> `{:ok, :skipped_exists}`
    2. `skip_if: pattern` && target exists && content matches -> `{:ok, :skipped_match}`
    3. target exists && content byte-identical to `content` -> `{:ok, :unchanged}`
       (unconditional -- no opt-in flag, applies every call)
    4. otherwise -> file is written -> `{:ok, :written}`

  ## Options

    * `:unless_exists` (boolean, default `false`) -- skip unconditionally if
      the target already exists, regardless of its content.
    * `:skip_if` (`String.t()` or `Regex.t()`, default `nil`) -- skip if the
      target already exists AND its content contains this substring or
      matches this regex.
    * `:dry_run` (boolean, default `false`) -- compute and return the same
      `outcome()` that a real call would produce, but never touch the
      filesystem: no `File.mkdir_p!/1`, no `File.write!/2`. Used by
      `mix ggen_igniter.sync --dry-run` to preview the decision table above
      with zero actual writes.
  """
  @spec write_file!(String.t(), String.t(), keyword()) :: {:ok, outcome()}
  def write_file!(path, content, opts \\ []) do
    unless_exists = Keyword.get(opts, :unless_exists, false)
    skip_if = Keyword.get(opts, :skip_if)
    dry_run = Keyword.get(opts, :dry_run, false)

    exists = File.exists?(path)
    existing = if exists, do: File.read!(path), else: nil

    cond do
      unless_exists and exists ->
        {:ok, :skipped_exists}

      exists and skip_if != nil and matches?(existing, skip_if) ->
        {:ok, :skipped_match}

      exists and existing == content ->
        {:ok, :unchanged}

      dry_run ->
        {:ok, :written}

      true ->
        File.mkdir_p!(Path.dirname(path))
        atomic_write!(path, content)
        {:ok, :written}
    end
  end

  # Writes `content` to a sibling temp file in the SAME directory as `path`
  # (guaranteeing the subsequent rename stays on the same filesystem/mount),
  # best-effort fsyncs it, then atomically renames it onto `path`. See this
  # module's moduledoc "Atomic-write guarantee" section for exactly what this
  # does and does not guarantee (POSIX-only atomicity, Windows/NFS caveats,
  # best-effort fsync).
  defp atomic_write!(path, content) do
    tmp_path = path <> ".ggen_igniter.tmp.#{System.unique_integer([:positive])}"

    try do
      File.write!(tmp_path, content)
      fsync_best_effort(tmp_path)
      File.rename!(tmp_path, path)
    rescue
      e ->
        File.rm(tmp_path)
        reraise e, __STACKTRACE__
    end
  end

  # Best-effort fsync of the temp file's data before the rename that makes it
  # visible under the final name. `:file.open/2` + `:file.sync/1` is used
  # (rather than anything in `File`, which does not expose fsync) because the
  # low-level `:file` Erlang module is what actually wraps the POSIX fsync(2)
  # syscall on platforms/filesystems that honor it. Never raises -- a
  # filesystem that doesn't support fsync (or where opening a second handle
  # to the just-written temp file fails) does not block the write; it just
  # loses the extra durability margin, which the moduledoc discloses as
  # best-effort, not an unconditional guarantee.
  defp fsync_best_effort(path) do
    case :file.open(path, [:read, :binary]) do
      {:ok, fd} ->
        _ = :file.sync(fd)
        :file.close(fd)

      {:error, _reason} ->
        :ok
    end
  end

  defp matches?(content, %Regex{} = pattern), do: Regex.match?(pattern, content)
  defp matches?(content, needle) when is_binary(needle), do: String.contains?(content, needle)

  @typedoc """
  Outcome of a guarded injection into an EXISTING file:
  - `:injected` -- the target existed, the anchor matched exactly one line,
    and `content` was spliced in at the requested position.
  - `:unchanged` -- `content` was already present immediately at the target
    anchor position (idempotent no-op; safe to re-run).
  """
  @type inject_outcome :: :injected | :unchanged

  @doc """
  Injects `content` into the EXISTING file at `path`, anchored on `marker`
  (a literal `String.t()` or a `Regex.t()` matched against each line), modeled
  on the real Rust ggen's `inject_into`/marker-selection semantics in
  `ggen-engine/src/write.rs` (`FM-WRITE-003`/`FM-WRITE-004` fail-closed gates),
  scoped down to this module's needs: single literal-or-regex anchor, first
  (and only permitted) occurrence, no `backup`/`freeze`/checksum machinery.

  ## Modes (`insert_mode`)

    * `:before` -- insert `content` as new line(s) immediately before the
      matched line.
    * `:after` -- insert `content` as new line(s) immediately after the
      matched line.
    * `:at_line` -- insert `content` at a specific 1-based line number
      (`opts[:line]`, required for this mode). `marker` is ignored.

  ## Fail-closed gates (in order, mirroring `ggen-engine/src/write.rs`)

    1. Target file does not exist -> raise (`FM-WRITE-003` equivalent).
       Injection is not a substitute for creation; use `write_new_file!/2` or
       `write_file!/3` to create the file first.
    2. `:before`/`:after` marker matches zero lines, or matches more than one
       line (ambiguous) -> raise (`FM-WRITE-004` equivalent). A best-effort
       partial match is never taken.
    3. `:at_line` out of range (`< 1` or `> line_count + 1`) -> raise.

  ## Idempotency

  If `content` is already present immediately at the resolved insertion point
  (i.e. the lines that would be spliced in are already there, right where
  this call would put them), the write is skipped and `{:ok, :unchanged}` is
  returned -- re-running the same injection never duplicates the block.

  ## Options

    * `:line` (integer, required when `insert_mode: :at_line`) -- 1-based
      target line number.
    * `:dry_run` (boolean, default `false`) -- run every real fail-closed gate
      (target-exists check, anchor uniqueness, `:at_line` range) and the real
      idempotency check against the file's ACTUAL current content, computing
      the same `inject_outcome()` a real call would produce, but never call
      `File.write!/2`. Mirrors `write_file!/3`'s own `:dry_run` option so
      `mix ggen_igniter.sync --dry-run` can preview an injection honestly
      (a real anchor-resolution failure still raises under `:dry_run` -- a
      dry run previews a real decision, it does not suppress a real error).

  ## Examples

      # anchor on a literal marker line, insert after it
      Actuate.inject_content!(path, "# ggen:slot", "new_line()", :after)

      # anchor on a regex, insert before the unique match
      Actuate.inject_content!(path, ~r/^\\s*# GGEN:SLOT\\s*$/, "generated", :before)

      # insert at an explicit 1-based line number
      Actuate.inject_content!(path, nil, "zero", :at_line, line: 1)

      # preview only -- computes the real outcome, touches nothing
      Actuate.inject_content!(path, "# ggen:slot", "new_line()", :after, dry_run: true)
  """
  @spec inject_content!(
          String.t(),
          String.t() | Regex.t() | nil,
          String.t(),
          :before | :after | :at_line,
          keyword()
        ) ::
          {:ok, inject_outcome()}
  def inject_content!(path, marker, content, insert_mode, opts \\ [])
      when insert_mode in [:before, :after, :at_line] do
    dry_run = Keyword.get(opts, :dry_run, false)

    unless File.exists?(path) do
      raise ArgumentError,
            "inject_content!/5: target file #{inspect(path)} does not exist. " <>
              "Injection requires an existing file -- create it first with " <>
              "write_new_file!/2 or write_file!/3, then inject."
    end

    existing = File.read!(path)
    lines = String.split(existing, "\n")
    {lines, had_trailing_newline?} = drop_trailing_empty(lines)
    body_lines = String.split(content, "\n")

    insert_at =
      case insert_mode do
        :before -> unique_marker_line!(lines, marker, :before)
        :after -> unique_marker_line!(lines, marker, :after) + 1
        :at_line -> at_line_index!(lines, Keyword.fetch!(opts, :line))
      end

    cond do
      already_present_at?(lines, body_lines, insert_at, insert_mode) ->
        {:ok, :unchanged}

      dry_run ->
        {:ok, :injected}

      true ->
        new_lines = splice(lines, body_lines, insert_at)
        new_content = join_with_trailing(new_lines, had_trailing_newline?)
        File.write!(path, new_content)
        {:ok, :injected}
    end
  end

  # Drops a single trailing empty string produced by `String.split(content,
  # "\n")` on content ending in "\n", and reports whether it was present, so
  # the same trailing-newline convention can be restored on write.
  defp drop_trailing_empty(lines) do
    case List.last(lines) do
      "" -> {List.delete_at(lines, -1), true}
      _ -> {lines, false}
    end
  end

  defp splice(lines, body_lines, insert_at) do
    {before, rest} = Enum.split(lines, insert_at)
    before ++ body_lines ++ rest
  end

  defp join_with_trailing(lines, true), do: Enum.join(lines, "\n") <> "\n"
  defp join_with_trailing(lines, false), do: Enum.join(lines, "\n")

  # Finds the single 0-based line index matching `marker`, raising if zero or
  # more-than-one lines match (ambiguous-or-missing anchor is always an
  # error, never a best-effort pick) -- mirrors FM-WRITE-004.
  defp unique_marker_line!(lines, marker, use_) do
    matches =
      lines
      |> Enum.with_index()
      |> Enum.filter(fn {line, _idx} -> marker_matches?(line, marker) end)

    case matches do
      [{_line, idx}] ->
        idx

      [] ->
        raise ArgumentError,
              "inject_content!/5 (#{use_}): anchor marker #{inspect(marker)} matched no line " <>
                "in the target file. Remediation: fix the marker pattern or add the intended " <>
                "host slot -- injection never falls back to a best-effort partial match."

      many ->
        raise ArgumentError,
              "inject_content!/5 (#{use_}): anchor marker #{inspect(marker)} matched " <>
                "#{length(many)} lines (ambiguous); expected exactly one. " <>
                "Remediation: make the marker unique to a single line."
    end
  end

  @doc """
  Evaluates `code` (a rendered template body, real Elixir source) in-process
  via `Code.eval_string/2`, using `bindings` -- the exact same keyword list
  already built for `GgenIgniter.Render.render/2`'s EEx evaluation, so eval'd
  code can reference `module_name`/`package_name`/etc. exactly like an EEx
  template body can. Backs `mode: eval` templates (see
  `GgenIgniter.Frontmatter.split_template/1` and
  `Mix.Tasks.GgenIgniter.Sync`'s `## Execution mode` docs): the rendered
  content is never written to disk at all under this mode.

  This is a deliberate, disclosed arbitrary-code-execution capability --
  ontology/RDF-driven data becomes literally-executed Elixir code under
  `mode: eval`. That is the point of this actuation mode, not an oversight:
  templates are trusted input, the same trust boundary an EEx template body
  already is today (an EEx template can already run arbitrary Elixir inside
  `<%= %>` during rendering).

  Returns `{:ok, value}`, the real return value of the evaluated code (the
  same value `Code.eval_string/2` itself returns, unwrapped from its
  `{value, bindings}` pair -- the post-eval bindings are discarded since
  nothing downstream consumes them in this pass). Compile/syntax errors are
  caught and re-raised as a clear `RuntimeError` naming the real failure,
  never a raw `CompileError`/`SyntaxError`/`TokenMissingError` struct
  surfacing uncaught.

  ## Examples

      iex> GgenIgniter.Actuate.eval_code!("1 + 1", [])
      {:ok, 2}

      iex> GgenIgniter.Actuate.eval_code!("x + y", x: 1, y: 2)
      {:ok, 3}

  """
  @spec eval_code!(String.t(), keyword()) :: {:ok, term()}
  def eval_code!(code, bindings) when is_binary(code) and is_list(bindings) do
    {value, _bindings} = Code.eval_string(code, bindings)
    {:ok, value}
  rescue
    e in [CompileError, SyntaxError, TokenMissingError] ->
      reraise RuntimeError,
              "mode: eval template failed to compile: #{Exception.message(e)}",
              __STACKTRACE__
  end

  defp marker_matches?(line, %Regex{} = marker), do: Regex.match?(marker, line)

  defp marker_matches?(line, marker) when is_binary(marker),
    do: line == marker or String.contains?(line, marker)

  defp at_line_index!(lines, at) when is_integer(at) do
    line_count = length(lines)

    if at < 1 or at > line_count + 1 do
      raise ArgumentError,
            "inject_content!/5 (:at_line): line #{at} out of range (file has #{line_count} " <>
              "lines; valid range 1..#{line_count + 1})."
    end

    at - 1
  end

  # Idempotency check: are `body_lines` already present, in order, exactly
  # where a real re-run of this exact injection would place them?
  #
  # For `:after` and `:at_line`, `insert_at` is a fixed offset from the START
  # of the file (or, for `:after`, from a marker whose own line index is
  # unaffected by a prior insertion placed strictly after it) -- so checking
  # the slice starting AT `insert_at` is correct on every re-run.
  #
  # For `:before`, `insert_at` IS the marker's own line index, resolved fresh
  # on every call via `unique_marker_line!/3`. After a first real injection,
  # the previously-inserted `body_lines` sit immediately BEFORE the marker
  # line, which has shifted `length(body_lines)` positions later in the file
  # -- so `insert_at` on the second call points at the marker line itself,
  # not at the body. Checking the slice ending AT `insert_at` (i.e. starting
  # `length(body_lines)` positions earlier) is what actually re-detects
  # "already injected" for this mode; without this, a second identical
  # `:before` injection would splice a duplicate copy of `body_lines` instead
  # of returning `:unchanged`.
  defp already_present_at?(lines, body_lines, insert_at, :before) do
    lines
    |> Enum.slice(insert_at - length(body_lines), length(body_lines))
    |> Kernel.==(body_lines)
  end

  defp already_present_at?(lines, body_lines, insert_at, _mode) do
    lines
    |> Enum.slice(insert_at, length(body_lines))
    |> Kernel.==(body_lines)
  end
end
