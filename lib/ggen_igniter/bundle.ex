defmodule GgenIgniter.Bundle.Pack do
  @moduledoc """
  One pack entry inside a loaded bundle -- mirrors one element of
  `priv/bundles/fortune5_ready.json`'s `"packs"` array.

  `name` is the dedupe key `GgenIgniter.Bundle.merge/2` matches against a
  consumer's existing `ggen.toml` `[packs]` keys. `path_hint` is the default
  relative path an installer (out of scope here -- GGEN-1804) would propose
  when wiring a new `[packs]` entry; it is a hint, not authoritative.
  """
  @enforce_keys [:name, :path_hint]
  defstruct [:name, :path_hint]

  @type t :: %__MODULE__{name: String.t(), path_hint: String.t()}
end

defmodule GgenIgniter.Bundle do
  @moduledoc """
  Loads and merges the fortune5-ready pack bundle
  (`priv/bundles/fortune5_ready.json`), per
  `docs/jira/v26.9.1/03-BUNDLE-MANIFEST-AND-MERGE.md` (GGEN-1801 manifest,
  GGEN-1803 dedupe merge).

  ## Resolved design decision 1 -- manifest location (source epic §1.2)

  The bundle manifest lives in `ggen_igniter` itself
  (`priv/bundles/fortune5_ready.json`), not alongside the packs in
  `ggen-marketplace`. Co-locating with `ggen_igniter` means the manifest and
  the (out-of-scope-here) installer task that reads it always ship in
  lockstep -- a manifest naming packs the installed `ggen_igniter` version
  doesn't yet know how to merge correctly cannot exist, because both live in
  the same release artifact. Co-locating with `ggen-marketplace` would let
  the manifest evolve at the pack corpus's own cadence, but `ggen_igniter`
  has no vendoring/pinning mechanism today (unlike beam4pm's
  `vendor/ggen-marketplace` git submodule) -- bringing one in as a side
  effect of one bundle manifest is out of proportion to the problem this
  module solves. This is the cheaper interim answer with the lower blast
  radius; revisit if a pack-repo-side versioning need actually arises.

  ## Resolved design decision 2 -- bundle composition is name-keyed, not domain-aware yet (source epic §1.3)

  Bundle composition stays one-size-fits-all for v1 (a single
  `"fortune5_ready"` bundle), but the manifest's own data shape
  (`"bundles"` is a name-keyed map, not a single hardcoded module attribute)
  means a second, differently-scoped bundle is a data addition, not a schema
  change, if and when one is actually proposed. No second bundle is scoped
  or justified by this release -- inventing domain-awareness now would be
  speculative generality with no real second consumer.

  ## v1 bundle contents

  Exactly two packs ship in `"fortune5_ready"` today:
  `fortune5-architecture` and `fortune5-deployment-blocks`.
  `fortune5-required-capabilities` and `fortune5-testing-bblock` are
  deliberately excluded -- both are gated on their own upstream portability
  fixes landing in `ggen-marketplace` first (hardcoded
  `../../../../crates/ggen-marketplace` path, and
  `crates/ggen-cli`/`target/debug/ggen` self-detection, respectively) and
  this ticket's dependency does not re-run that portability re-test.
  `fortune5-enterprise-architecture` is out of scope entirely -- no
  portability audit has ever been run against it.
  """

  @type bundle :: %{manifest_version: String.t(), packs: [GgenIgniter.Bundle.Pack.t()]}

  @doc """
  Absolute path to the bundle manifest shipped inside this application's
  `priv/` directory. Resolved at call time (not compile time) via
  `Application.app_dir/2`, so it works correctly whether `ggen_igniter` is
  compiled in place or installed as a dependency.
  """
  @spec default_manifest_path() :: String.t()
  def default_manifest_path do
    Path.join([Application.app_dir(:ggen_igniter), "priv", "bundles", "fortune5_ready.json"])
  end

  @doc """
  Load and parse a bundle manifest JSON file, returning a name-keyed map of
  atom-keyed `bundle` structs (never raw string-keyed `Map.t()` left
  unconverted). Raises on a missing file or malformed JSON -- mirrors the
  `!` convention used elsewhere in this codebase for "this file must exist
  for the operation to make sense" loads.
  """
  @spec load!(String.t()) :: %{optional(String.t()) => bundle()}
  def load!(path \\ default_manifest_path()) do
    path
    |> File.read!()
    |> Jason.decode!()
    |> Map.fetch!("bundles")
    |> Map.new(fn {bundle_name, bundle} -> {bundle_name, build_bundle(bundle)} end)
  end

  @doc """
  Load the named bundle (default: `"fortune5_ready"`) from the manifest at
  `path` (default: `priv/bundles/fortune5_ready.json`), returning its
  `packs` list directly.
  """
  @spec load_packs!(String.t(), String.t()) :: [GgenIgniter.Bundle.Pack.t()]
  def load_packs!(bundle_name \\ "fortune5_ready", path \\ default_manifest_path()) do
    path
    |> load!()
    |> Map.fetch!(bundle_name)
    |> Map.fetch!(:packs)
  end

  defp build_bundle(%{"manifest_version" => version, "packs" => packs}) do
    %{
      manifest_version: version,
      packs: Enum.map(packs, &build_pack/1)
    }
  end

  defp build_pack(%{"name" => name, "path_hint" => path_hint}) do
    %GgenIgniter.Bundle.Pack{name: name, path_hint: path_hint}
  end

  @doc """
  Merge a bundle's packs into an already-parsed `%GgenIgniter.FrontmatterConfig{}`
  (ticket 01/02's real `SchemaDispatch.load/1` output for the `:frontmatter`
  schema -- table-of-tables `[packs]`, the schema real consumers like
  beam4pm actually use). Returns the list of `GgenIgniter.Bundle.Pack.t()`
  entries that need to be **added** -- entries already present (by name) are
  never returned, never duplicated, never mutated.

  Dedup key is pack name/alias exactly as it appears in the consumer's
  `ggen.toml` `[packs]` table today -- **not path**. Two differently-named
  entries could legitimately point at the same path in principle (this
  function does not adjudicate that), so a bundle pack whose `path_hint`
  happens to collide with an existing entry's `path` under a different name
  is still reported as a new entry to add.
  """
  @spec merge(GgenIgniter.FrontmatterConfig.t(), [GgenIgniter.Bundle.Pack.t()]) ::
          [GgenIgniter.Bundle.Pack.t()]
  def merge(%GgenIgniter.FrontmatterConfig{packs: existing_packs}, bundle_packs)
      when is_map(existing_packs) and is_list(bundle_packs) do
    existing_names = existing_packs |> Map.keys() |> MapSet.new()

    Enum.reject(bundle_packs, fn %GgenIgniter.Bundle.Pack{name: name} ->
      MapSet.member?(existing_names, name)
    end)
  end
end
