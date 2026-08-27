defmodule GgenIgniter.Manifest do
  @moduledoc """
  The RECONCILIATION MANIFEST: turns `mix ggen_igniter.sync` from a stateless
  generator into a stateful reconciler that knows what it previously wrote,
  so a rename/removal in the ontology produces a mechanically DETECTABLE
  stale output instead of a silently orphaned file on disk.

  Written to `<base_dir>/.ggen_igniter/manifest.json` -- `base_dir` is the
  CONSUMER project's own directory (whatever directory `mix ggen_igniter.sync`
  is actually invoked from, i.e. `File.cwd!()` by default, overridable via
  `--manifest-dir` -- see `Mix.Tasks.GgenIgniter.Sync`), never this
  (`ggen_igniter`) repo's own tree.

  ## Why this gap is real (grounded in the actual code, not invented)

  Before this module, nothing in `lib/mix/tasks/ggen_igniter.sync.ex` or
  `lib/ggen_igniter/actuate.ex` ever recorded what a PRIOR sync run wrote:
  `Actuate.write_file!/3`/`inject_content!/5`/`eval_code!/2` only ever look at
  the ONE path a CURRENT run's `--out`/`to:`/`--for-each` resolves to. A
  resource rename (`ontology_v9_rename_resource.ttl`'s `Ticket` -> `Case`) or
  removal (`ontology_v10_remove_resource.ttl`) produces a clean NEW/updated
  file but leaves the OLD file (`ticket.ex`) sitting on disk untouched --
  reproduced directly by
  `test/ggen_igniter_destructive_change_agent3_test.exs`'s cases 7/8 and
  documented as a real, disclosed gap in `.ggen_igniter_factory/ADVERSARIAL.md`
  ("MUST FIX #3: Destructive ontology evolution: no orphan-file reconciliation
  on rename or removal").

  ## The manifest's key: (template, out_template) -- a "recipe" identity, NOT
  ontology/pack/timestamp

  Each manifest entry is keyed by `recipe_key/2`: the RESOLVED `--template`
  path plus the RAW (unrendered) `--out`/`to:` string, e.g.
  `"test/fixtures/ash-lifecycle-pack/templates/resource.ex.eex=>lib/support_desk/support/<%= String.downcase(resource_name) %>.ex"`.

  This is deliberately NOT keyed by ontology path, pack name alone, or a
  per-run timestamp:

    * **Not ontology path** -- a real developer re-syncs the SAME
      `--ontology ontology.ttl` repeatedly as they edit its CONTENT in place;
      the ontology PATH stays constant across a rename. (The fixture pack's
      own `ontology_v9_rename_resource.ttl`/`ontology.ttl` pair are two
      DIFFERENT files only because this is a test fixture simulating
      "before" and "after" states without mutating one file in place --real
      usage has one evolving `ontology.ttl`.) Keying by ontology path would
      make the SAME recipe (same template, same `--out`) against the SAME
      evolving ontology register as a brand-new, unrelated key on every
      content edit, defeating reconciliation entirely.
    * **Not pack name alone** -- a plain `--ontology`/`--template`/`--out`
      invocation (no `--pack`/`--pack-dir` at all) is fully supported by this
      whole pipeline (see `Mix.Tasks.GgenIgniter.Sync`'s own moduledoc
      examples) and has no pack name to key by. `(template, out_template)` is
      the one identity present in EVERY invocation shape (pack-based or not).
    * **The (template, out_template) pair IS the stable "recipe"** across a
      rename/removal: `--for-each`'s per-row `out_template` string
      (`"lib/support_desk/support/<%= String.downcase(resource_name) %>.ex"`)
      does not itself change when a row's `resource_name` value changes --
      only the RENDERED path per row changes, which is exactly the thing
      reconciliation needs to diff old-vs-new.

  `pack_dir` (when resolvable) is recorded in each entry as informational
  metadata only -- never part of the key -- so a human reading the manifest
  can see which pack produced it without it affecting reconciliation
  identity.

  ## What is (and is NOT) tracked

  Only `mode: file` outputs actuated via `Actuate.write_file!/3` (full
  ownership: this pack creates AND can safely recreate/delete the file) are
  ever recorded here. Deliberately excluded:

    * `mode: eval` -- nothing is ever written to disk under this mode
      (`Actuate.eval_code!/2`), so there is nothing to reconcile.
    * `inject: true` targets -- `Actuate.inject_content!/5` requires (and
      NEVER creates) a pre-existing file this pack does not own; it only
      splices a fragment into someone else's file. Treating an inject target
      as "manufactured by this pack" would let `--on-stale prune` delete a
      file this pack never created in the first place -- a real destructive-
      action risk this module refuses to take on. `Mix.Tasks.GgenIgniter.Sync`
      gates reconciliation to `inject_spec == nil` for exactly this reason.

  ## Format

      {
        "version": 1,
        "entries": {
          "<template_path>=><out_template>": {
            "template": "test/fixtures/ash-lifecycle-pack/templates/resource.ex.eex",
            "out_template": "lib/support_desk/support/<%= String.downcase(resource_name) %>.ex",
            "pack_dir": "test/fixtures/ash-lifecycle-pack",
            "updated_at": "2026-08-27T12:34:56.789012Z",
            "outputs": {
              "lib/support_desk/support/ticket.ex": "sha256:<hex>",
              "lib/support_desk/support/customer.ex": "sha256:<hex>"
            }
          }
        }
      }

  `outputs` maps every real path this recipe wrote on its MOST RECENT
  successful run to a `"sha256:" <> hex` digest of the real content
  `Actuate.write_file!/3` wrote there (computed by re-reading the file back
  off disk after the write, not derived from the in-memory rendered string --
  a real content hash of what is actually on disk).
  """

  @manifest_relpath ".ggen_igniter/manifest.json"

  @typedoc "One recipe's manifest entry, JSON-decoded (string keys, matching Jason's default map shape)."
  @type entry :: %{
          optional(String.t()) => term(),
          required(String.t()) => term()
        }

  @typedoc "The whole manifest file, JSON-decoded."
  @type t :: %{String.t() => term()}

  @doc "The manifest's on-disk path for a given consumer-project `base_dir`: `<base_dir>/.ggen_igniter/manifest.json`."
  @spec path(String.t()) :: String.t()
  def path(base_dir), do: Path.join(base_dir, @manifest_relpath)

  @doc """
  Loads the manifest at `path(base_dir)`.

  Returns a fresh `%{"version" => 1, "entries" => %{}}` when no manifest file
  exists yet (the real, honest "first run" state -- not an error). Raises a
  clear `ArgumentError` if the file exists but is not valid JSON, or is valid
  JSON with an unexpected shape (missing/non-map `"entries"`) -- a corrupt
  manifest is a real data-integrity problem this module refuses to silently
  paper over by pretending there is no prior state (that would silently
  defeat reconciliation for exactly the runs that need it most).
  """
  @spec load(String.t()) :: t()
  def load(base_dir) do
    manifest_path = path(base_dir)

    case File.read(manifest_path) do
      {:ok, content} ->
        decode!(content, manifest_path)

      {:error, :enoent} ->
        %{"version" => 1, "entries" => %{}}

      {:error, reason} ->
        raise ArgumentError,
              "could not read ggen_igniter manifest at #{manifest_path}: #{inspect(reason)}"
    end
  end

  defp decode!(content, manifest_path) do
    case Jason.decode(content) do
      {:ok, %{"entries" => entries} = manifest} when is_map(entries) ->
        manifest

      {:ok, other} ->
        raise ArgumentError,
              "ggen_igniter manifest at #{manifest_path} has an unexpected shape " <>
                "(expected a JSON object with an \"entries\" object) -- refusing to guess " <>
                "its prior state; fix or remove the file. Got: #{inspect(other)}"

      {:error, reason} ->
        raise ArgumentError,
              "ggen_igniter manifest at #{manifest_path} is not valid JSON (#{inspect(reason)}) " <>
                "-- refusing to guess its prior state; fix or remove the file"
    end
  end

  @doc """
  The stable "recipe" key for one `(template, out_template)` pair -- see this
  module's moduledoc for why this pair (and not ontology path or pack name
  alone) is the real reconciliation identity.
  """
  @spec recipe_key(String.t(), String.t()) :: String.t()
  def recipe_key(template_path, out_template)
      when is_binary(template_path) and is_binary(out_template) do
    template_path <> "=>" <> out_template
  end

  @doc "Looks up one recipe's entry in a loaded manifest, or `nil` if this key has never been recorded."
  @spec get_entry(t(), String.t()) :: entry() | nil
  def get_entry(manifest, key), do: get_in(manifest, ["entries", key])

  @doc "The set of output paths a manifest entry last recorded (empty for `nil`, i.e. no prior entry)."
  @spec output_paths(entry() | nil) :: MapSet.t(String.t())
  def output_paths(nil), do: MapSet.new()

  def output_paths(%{"outputs" => outputs}) when is_map(outputs),
    do: outputs |> Map.keys() |> MapSet.new()

  def output_paths(_other), do: MapSet.new()

  @doc """
  `stale = old_paths - new_paths`: paths the entry previously recorded that
  are NOT among `new_paths` (this run's real, freshly-rendered output-path
  set). `new_paths` may be any `Enum.t()` (converted to a `MapSet` here).
  """
  @spec stale_paths(entry() | nil, Enum.t()) :: MapSet.t(String.t())
  def stale_paths(entry, new_paths),
    do: MapSet.difference(output_paths(entry), MapSet.new(new_paths))

  @doc "A `\"sha256:\" <> hex` digest of real binary content -- the real, written-to-disk bytes, not the in-memory rendered string."
  @spec hash_content(binary()) :: String.t()
  def hash_content(content) when is_binary(content) do
    "sha256:" <> (:crypto.hash(:sha256, content) |> Base.encode16(case: :lower))
  end

  @doc """
  Whether `outputs` (a fresh `%{path => hash}` map for this run) is
  IDENTICAL to what `entry` already recorded -- the real test for "nothing
  changed, don't touch the manifest file at all" (so a no-op re-run leaves
  the manifest file byte-for-byte unchanged, not merely logically
  equivalent-with-a-bumped-timestamp).
  """
  @spec same_outputs?(entry() | nil, %{String.t() => String.t()}) :: boolean()
  def same_outputs?(entry, outputs) when is_map(outputs) do
    existing =
      case entry do
        %{"outputs" => o} when is_map(o) -> o
        _ -> %{}
      end

    existing == outputs
  end

  @doc "Builds a fresh entry for `recipe_key/2`'s `(template_path, out_template)` pair, stamped with the current UTC time."
  @spec build_entry(String.t(), String.t(), String.t() | nil, %{String.t() => String.t()}) ::
          entry()
  def build_entry(template_path, out_template, pack_dir, outputs) when is_map(outputs) do
    %{
      "template" => template_path,
      "out_template" => out_template,
      "pack_dir" => pack_dir,
      "updated_at" => DateTime.utc_now() |> DateTime.to_iso8601(),
      "outputs" => outputs
    }
  end

  @doc "Returns a new manifest map with `entry` stored under `key` (every other entry untouched)."
  @spec put(t(), String.t(), entry()) :: t()
  def put(manifest, key, entry) do
    manifest
    |> Map.put_new("version", 1)
    |> Map.update("entries", %{key => entry}, &Map.put(&1, key, entry))
  end

  @doc """
  Atomically persists `manifest` to `path(base_dir)`: writes the real JSON to
  a sibling temp file first, then `File.rename!/2`s it into place (an atomic
  rename on the same POSIX filesystem) -- a crash/failure mid-write can never
  leave a half-written, corrupt manifest.json behind; the prior file (the
  last KNOWN-GOOD state) survives untouched until the new content is fully
  flushed to disk under a different name.

  Callers decide WHETHER to call this at all (see `same_outputs?/2`) -- this
  function itself unconditionally writes when called, matching
  `Mix.Tasks.GgenIgniter.Sync`'s own "only persist after this run's own
  actuation fully succeeds" partial-run-safety requirement (a raised
  exception mid-run never reaches this call).
  """
  @spec persist!(t(), String.t()) :: :ok
  def persist!(manifest, base_dir) do
    manifest_path = path(base_dir)
    File.mkdir_p!(Path.dirname(manifest_path))

    tmp_path =
      manifest_path <> ".tmp-#{System.unique_integer([:positive, :monotonic])}"

    json = Jason.encode!(manifest, pretty: true)
    File.write!(tmp_path, json <> "\n")
    File.rename!(tmp_path, manifest_path)
    :ok
  end

  @doc """
  Really deletes each path in `paths` (`File.rm/1` for real -- this is the
  `--on-stale prune` policy's actual destructive action). Returns
  `[{path, :pruned | :absent}]` -- `:absent` when the path was already gone
  (not an error; nothing left to prune). Any OTHER `File.rm/1` failure (e.g.
  a permissions error) raises `RuntimeError` naming the exact path and reason
  rather than silently continuing past a real, unexpected filesystem
  failure.
  """
  @spec prune!([String.t()]) :: [{String.t(), :pruned | :absent}]
  def prune!(paths) do
    paths
    |> Enum.sort()
    |> Enum.map(fn path ->
      case File.rm(path) do
        :ok ->
          {path, :pruned}

        {:error, :enoent} ->
          {path, :absent}

        {:error, reason} ->
          raise RuntimeError,
                "ggen_igniter: --on-stale prune could not delete stale output #{path}: #{inspect(reason)}"
      end
    end)
  end
end
