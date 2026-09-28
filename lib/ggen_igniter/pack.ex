defmodule GgenIgniter.Pack do
  @moduledoc """
  Resolves the `priv/ggen/<pack-name>/` convention (or an explicit `--pack-dir`)
  into sane defaults for `--ontology`/`--query`/`--template`, per the pack
  convention design:

      priv/ggen/<pack-name>/
      ├── pack.toml            # legacy: optional; Core profile: REQUIRED + consumed
      ├── ontology.ttl          # default --ontology
      ├── gates/*.rq            # default --query source, one query per file
      └── templates/*.{eex,tmpl} # default --template source (single-file case;
                                 # `discover_templates/1` lists them all for
                                 # `--pack-dir` multi-template fan-out)

  ## RFC-GPACK-001: pack.toml consumption + identity correspondence (D3)

  Historically `pack.toml` was optional and never read here (RFC-GPACK-001
  §4.2/D3: "Manifest Authority" divergence). Per RFC-GPACK-001 §86 steps 1+2
  this module now consumes it -- compatibly, by profile:

    * **Core profile** (`gp:profile gp:Core1` or `gp:Portable1` declared in the
      pack's graph, §10/§12.1/§12.2) -- `pack.toml` is REQUIRED and strict:
      `parse_manifest/1` enforces §7.1 exactly (`[pack]` with `name`,
      `version`, `description`; unknown keys inside `[pack]` refuse as
      `REFUSED:PACK_MANIFEST_INVALID`), and `admit_pack_manifest/2` enforces
      the §8 identity correspondence `Project(I_S) = I_B` (graph `gp:name` ==
      manifest `name`; a Core graph declaring no `gp:name` fails closed as
      `REFUSED:PACK_IDENTITY_MISMATCH`, since a Core pack SHOULD
      self-describe, §10 -- missing is recorded as mismatch).
    * **Legacy** (no `gp:profile` in the graph, the GGEN-PACK-IGNITER-LEGACY-1
      shape of §89) -- `admit_pack_manifest/2` returns `:ok` without even
      reading `pack.toml`: today's optional-manifest behavior, byte-compat,
      zero new refusals (§86 step 2, §89).

  Enforcement seam: `GgenIgniter.Reactors.ReconcileReactor` (the single
  dispatch path of `mix ggen_igniter.sync`) runs `admit_pack_manifest/2`
  between pack/graph resolution and any query/render/actuation, and its
  read-only `plan/1` applies the same check. `fetch_pack!/2` below is
  transport only (§69: `Fetched ≠ Verified`) -- it deliberately performs no
  manifest admission.

  Pure helper, no `Igniter` dependency, so both `ggen_igniter.sync` and
  `ggen_igniter.doctor` (and tests) can call it directly.

  ## Marketplace fetch (`fetch_pack!/2`)

  Modeled on the real Rust `ggen`'s `ggen pack add <registry>:<id>`
  (`crates/ggen-marketplace/src/marketplace/install.rs`): resolve a package
  spec, download a real archive over HTTP, verify it, extract it into a local
  cache directory so `resolve_dir!/1`-style discovery works against it.

  Two real, simple registry sources are implemented -- **their verification
  strength is genuinely different, and this moduledoc says so honestly**:

    * `"github:owner/repo"` (optionally `"@ref"`, default `"main"`, and
      optionally a monorepo subpath `"#packs/my-pack"` or `"//packs/my-pack"`,
      e.g. `"github:seanchatmangpt/ggen-marketplace@main#packs/ash-extension-pack"`,
      in which case the SUBDIRECTORY is returned as the pack root; a subpath
      that is absolute, contains `..`, or passes through a symlink is refused
      before anything is written -- see `extract_archive!/3`) -- fetches
      `https://github.com/<owner>/<repo>/archive/refs/heads/<ref>.tar.gz`.
      GitHub's archive endpoint publishes **no checksum** to verify against,
      so this path is **print-only**: the real SHA-256 of the downloaded
      archive is printed so the caller can pin/verify it manually (e.g. against
      a value they've recorded from a prior trusted fetch). This is not
      fail-closed verification -- there is nothing to fail closed against.
    * `"hex:name@version"` (or `"hex:name"` to resolve the latest stable
      version via the Hex API) -- fetches the real Hex package tarball from
      `https://repo.hex.pm/tarballs/<name>-<version>.tar` and compares its
      real SHA-256 against the `checksum` field hex.pm's own API
      (`https://hex.pm/api/packages/<name>/releases/<version>`) publishes for
      that release. This path **is** fail-closed: a mismatch raises before
      anything is extracted.

  Neither source is fabricated -- both are real public HTTP endpoints exercised
  by the test suite (tagged `:requires_network`, see
  `test/ggen_igniter_pack_fetch_test.exs`; the subpath/extraction logic is
  covered offline on a real local `.tar.gz` by
  `test/ggen_igniter_pack_marketplace_fetch_test.exs`).

  **Consumer requirement:** the HTTP layer is `Tesla`, an `optional: true`
  dependency of `ggen_igniter`. A consuming app that wants `fetch_pack!/2` /
  `mix ggen_igniter.pack.fetch` MUST add `{:tesla, "~> 1.8"}` to its own
  `mix.exs` deps; without it `fetch_pack!/2` raises a `RuntimeError` saying so
  (the rest of this module works without it).

  ## `--pack NAME` resolution

  `resolve_dir!/1` resolves `--pack NAME` to the cwd-relative
  `priv/ggen/NAME` when that directory exists, else to the pack SHIPPED with
  this package (`Path.join(:code.priv_dir(:ggen_igniter), "ggen/NAME")`, i.e.
  `deps/ggen_igniter/priv/ggen/NAME` in a consumer). `missing_dir_message/1`
  explains both searched paths when neither exists.
  """
  require Logger

  @doc """
  Resolves the pack directory from `opts[:pack_dir]` (explicit override) or
  `opts[:pack]` (looked up under `priv/ggen/<name>/`). Raises `ArgumentError`
  if neither is given.
  """
  @spec resolve_dir!(keyword() | map()) :: String.t()
  def resolve_dir!(opts) do
    case fetch(opts, :pack_dir) || fetch_pack(opts) do
      nil ->
        raise ArgumentError, "either --pack NAME or --pack-dir DIR is required to resolve a pack"

      dir ->
        dir
    end
  end

  # `--pack NAME`: the cwd-relative `priv/ggen/NAME` wins when it exists; else
  # the pack SHIPPED inside this package (`<priv_dir>/ggen/NAME`, i.e.
  # `deps/ggen_igniter/priv/ggen/NAME` in a consumer) when that exists; else
  # the cwd-relative path is returned unchanged so callers keep their own
  # "not found" diagnostics -- enriched via `missing_dir_message/1`.
  defp fetch_pack(opts) do
    case fetch(opts, :pack) do
      nil ->
        nil

      name ->
        relative = Path.join(["priv", "ggen", name])
        shipped = shipped_pack_dir(name)

        cond do
          File.dir?(relative) -> relative
          shipped != nil and File.dir?(shipped) -> shipped
          true -> relative
        end
    end
  end

  defp shipped_pack_dir(name) do
    case :code.priv_dir(:ggen_igniter) do
      {:error, _} -> nil
      priv -> Path.join([to_string(priv), "ggen", name])
    end
  end

  @doc """
  When the pack named by `opts` (`:pack_dir` wins over `:pack`) does not exist
  as a directory, returns a message naming the resolved directory, the
  cwd-relative path searched and the shipped-package path
  (`<priv_dir>/ggen/NAME`) also searched; `nil` when the directory exists or
  neither option is given. Callers append it to their "no template/ontology
  found" errors so an unknown `--pack NAME` is no longer reported as a
  template-discovery failure.
  """
  @spec missing_dir_message(keyword() | map()) :: String.t() | nil
  def missing_dir_message(opts) do
    cond do
      (dir = fetch(opts, :pack_dir)) not in [nil, ""] ->
        if File.dir?(dir), do: nil, else: "pack directory #{dir} does not exist"

      (name = fetch(opts, :pack)) not in [nil, ""] ->
        missing_named_pack_message(name, resolve_dir!(opts))

      true ->
        nil
    end
  end

  defp missing_named_pack_message(name, dir) do
    if File.dir?(dir) do
      nil
    else
      shipped = shipped_pack_dir(name)

      shipped_note =
        if shipped,
          do: " and the shipped package path #{shipped} (neither exists); ",
          else: "; "

      "pack directory #{dir} does not exist -- searched #{Path.expand(dir)} " <>
        "(cwd-relative priv/ggen/#{name})" <>
        shipped_note <> "check the --pack name, or pass --pack-dir DIR"
    end
  end

  defp fetch(opts, key) when is_map(opts), do: Map.get(opts, key)
  defp fetch(opts, key) when is_list(opts), do: Keyword.get(opts, key)

  @doc "Default `--ontology` path for `pack_dir`: `<pack_dir>/ontology.ttl`."
  @spec default_ontology(String.t()) :: String.t()
  def default_ontology(pack_dir), do: Path.join(pack_dir, "ontology.ttl")

  # -- RFC-GPACK-001 §7/§8/§10: pack.toml + identity correspondence ----------

  @gp_namespace "https://ggen.dev/ns/pack#"

  # §12.1/§12.2: the Core-family profiles that make pack.toml REQUIRED and
  # strict. `gp:Portable1` is Core + portability additions, so it inherits
  # every Core requirement (ticket scope: "gp:profile gp:Core1 or Portable1").
  @core_profile_iris MapSet.new([
                       @gp_namespace <> "Core1",
                       @gp_namespace <> "Portable1"
                     ])

  # §7.1: the manifest SHALL remain exactly these three keys.
  @manifest_required_keys MapSet.new(["name", "version", "description"])

  @type pack_admission ::
          :ok
          | {:refused, {:pack_manifest_missing, diagnostic: String.t()}}
          | {:refused, {:pack_manifest_invalid, diagnostic: String.t()}}
          | {:refused, {:pack_identity_mismatch, diagnostic: String.t()}}

  @doc """
  Parses `<pack_dir>/pack.toml` strictly per RFC-GPACK-001 §7.1.

  Returns:

    * `{:ok, %GgenIgniter.Pack.Manifest{}}` -- a `[pack]` table carrying
      exactly the three REQUIRED string keys `name`/`version`/`description`.
    * `:absent` -- no `pack.toml` file at `<pack_dir>` (a neutral result: only
      Core-profile packs turn it into `REFUSED:PACK_MANIFEST_MISSING`, via
      `admit_pack_manifest/2`; legacy packs keep the manifest optional).
    * `{:refused, {:pack_manifest_invalid, diagnostic: String.t()}}` -- the
      file exists but violates §7.1: not valid TOML, no `[pack]` table,
      missing a required key, a non-string value, or an UNKNOWN key inside
      `[pack]` (§7.1: "A Core v1 implementation MUST reject unknown keys
      inside `[pack]`" -- the one explicit normative MUST; keys outside
      `[pack]` are deliberately not refused by this function because the RFC
      attaches no MUST to them -- recorded edge, not silent acceptance of
      inside-`[pack]` laxity).

  Note this function alone does not know the pack's profile -- a legacy pack
  may keep a nonconforming `pack.toml` (e.g. `test/fixtures/sample-pack`'s
  top-keyed shape) because the legacy path never calls this parser; the
  profile-aware entry point is `admit_pack_manifest/2`.
  """
  @spec parse_manifest(String.t()) ::
          {:ok, GgenIgniter.Pack.Manifest.t()}
          | :absent
          | {:refused, {:pack_manifest_invalid, diagnostic: String.t()}}
  def parse_manifest(pack_dir) do
    manifest_path = Path.join(pack_dir, "pack.toml")

    case File.read(manifest_path) do
      {:error, :enoent} ->
        :absent

      {:error, reason} ->
        {:refused,
         {:pack_manifest_invalid,
          diagnostic: "could not read #{manifest_path}: #{inspect(reason)}"}}

      {:ok, raw} ->
        decode_manifest(raw)
    end
  end

  defp decode_manifest(raw) do
    case Toml.decode(raw) do
      {:ok, %{"pack" => pack}} when is_map(pack) ->
        validate_pack_table(pack)

      {:ok, _document} ->
        {:refused,
         {:pack_manifest_invalid,
          diagnostic:
            "pack.toml has no [pack] table -- RFC-GPACK-001 §7.1 requires " <>
              "[pack] with exactly name, version, description"}}

      {:error, reason} ->
        {:refused,
         {:pack_manifest_invalid, diagnostic: "pack.toml is not valid TOML: #{inspect(reason)}"}}
    end
  end

  defp validate_pack_table(pack) do
    present = MapSet.new(Map.keys(pack))

    unknown =
      pack
      |> Map.keys()
      |> Enum.reject(&MapSet.member?(@manifest_required_keys, &1))
      |> Enum.sort()

    missing =
      @manifest_required_keys
      |> MapSet.difference(present)
      |> MapSet.to_list()
      |> Enum.sort()

    cond do
      unknown != [] ->
        {:refused,
         {:pack_manifest_invalid,
          diagnostic:
            "unknown key(s) inside [pack]: #{Enum.map_join(unknown, ", ", &inspect/1)} -- " <>
              "RFC-GPACK-001 §7.1 requires [pack] to hold exactly name, version, description " <>
              "(unknown keys MUST be rejected); dependencies/capabilities/lifecycle belong in " <>
              "the RDF graph (§7.2)"}}

      missing != [] ->
        {:refused,
         {:pack_manifest_invalid,
          diagnostic:
            "missing required [pack] key(s): #{Enum.map_join(missing, ", ", &inspect/1)} -- " <>
              "RFC-GPACK-001 §7.1 requires name, version, and description"}}

      not Enum.all?(~w(name version description), fn key -> is_binary(Map.get(pack, key)) end) ->
        {:refused,
         {:pack_manifest_invalid,
          diagnostic:
            "every [pack] key must be a string -- got: " <>
              "#{inspect(Map.take(pack, ~w(name version description)))}"}}

      true ->
        {:ok,
         %GgenIgniter.Pack.Manifest{
           name: Map.fetch!(pack, "name"),
           version: Map.fetch!(pack, "version"),
           description: Map.fetch!(pack, "description")
         }}
    end
  end

  @doc """
  Which pack profile does the pack's own graph declare? RFC-GPACK-001 §10.

  Scans the graph for `?s gp:profile ?o` and returns:

    * `{:core, iri_string}` -- the object is `gp:Core1` or `gp:Portable1`
      (`https://ggen.dev/ns/pack#...`): the Core-family, where pack.toml is
      REQUIRED and identity correspondence is enforced.
    * `:legacy` -- no `gp:profile` triple with a Core-family object: the
      GGEN-PACK-IGNITER-LEGACY-1 shape (§89). A `gp:profile` naming an
      unimplemented profile is NOT silently legacy -- it also classifies
      `:legacy` here, but only because this function only answers "is this
      Core-family"; an unknown-profile pack never gets Core enforcement and
      never gets Core privileges (recorded edge: unknown profiles are a
      §100 `UNSUPPORTED` question for a later ladder, not a D3 concern).

  Accepts an `%RDF.Graph{}` (triples) or `%RDF.Dataset{}` (quads) -- the two
  shapes `GgenIgniter.Ontology.load!/1` can return.
  """
  @spec declared_profile(RDF.Graph.t() | RDF.Dataset.t()) :: :legacy | {:core, String.t()}
  def declared_profile(graph) do
    profile_predicate = RDF.iri(@gp_namespace <> "profile")

    result =
      graph
      |> pack_metadata_objects(profile_predicate)
      |> Enum.find(:legacy, fn iri -> MapSet.member?(@core_profile_iris, iri) end)

    case result do
      :legacy -> :legacy
      iri -> {:core, iri}
    end
  end

  # All objects `o` of statements `?s <predicate> ?o` whose object is an IRI,
  # as plain strings. Works over Graph triples and Dataset quads alike.
  defp pack_metadata_objects(graph, predicate) do
    graph
    |> statements()
    |> Enum.flat_map(fn
      {_s, ^predicate, o} -> [iri_string(o)]
      {_s, _p, _o} -> []
      {_s, ^predicate, o, _graph_name} -> [iri_string(o)]
      {_s, _p, _o, _graph_name} -> []
    end)
    |> Enum.reject(&is_nil/1)
  end

  # All literal VALUES of `?s gp:name ?o` in the graph (0, 1, or many).
  #
  # The RFC (§8) requires `Project(I_S) = I_B` when "the semantic graph
  # declares the corresponding identity". Multiple/zero `gp:name` triples are
  # both real observations, so this returns the full list and lets
  # `admit_pack_manifest/2` fail closed on zero (missing identity) or on ANY
  # disagreement (a second, disagreeing name is still a disagreement, not a
  # silent first-match).
  @doc false
  @spec declared_pack_names(RDF.Graph.t() | RDF.Dataset.t()) :: [String.t()]
  def declared_pack_names(graph) do
    name_predicate = RDF.iri(@gp_namespace <> "name")

    graph
    |> statements()
    |> Enum.flat_map(fn
      {_s, ^name_predicate, o} -> [literal_value(o)]
      {_s, _p, _o} -> []
      {_s, ^name_predicate, o, _graph_name} -> [literal_value(o)]
      {_s, _p, _o, _graph_name} -> []
    end)
    |> Enum.reject(&is_nil/1)
  end

  defp statements(%RDF.Graph{} = graph), do: RDF.Graph.triples(graph)
  defp statements(%RDF.Dataset{} = dataset), do: RDF.Dataset.statements(dataset)

  defp iri_string(%RDF.IRI{} = iri), do: RDF.IRI.to_string(iri)
  defp iri_string(_other), do: nil

  defp literal_value(%RDF.Literal{} = literal), do: RDF.Literal.value(literal)
  defp literal_value(_other), do: nil

  @doc """
  Admission gate for a resolved pack directory against its own loaded graph
  (RFC-GPACK-001 §7, §8, §12.1, §86 steps 1+2, §89; typed codes from
  Appendix C).

  * `pack_dir` `nil` (no `--pack`/`--pack-dir` given -- an explicit
    `--ontology` run is not pack resolution) => `:ok`, nothing is read.
  * Legacy graph (no Core-family `gp:profile`) => `:ok` WITHOUT reading
    `pack.toml` -- today's optional-manifest behavior, byte-compat, zero new
    refusals (§86 step 2, §89).
  * Core-family graph => `pack.toml` is REQUIRED (`:absent` =>
    `{:refused, {:pack_manifest_missing, ...}}` = `REFUSED:PACK_MANIFEST_MISSING`),
    strict §7.1 (`parse_manifest/1` refusals propagate =
    `REFUSED:PACK_MANIFEST_INVALID`), and the §8 correspondence
    `Project(I_S) = I_B` must hold: every `gp:name` the graph declares must
    equal the manifest `name`. A Core graph declaring NO `gp:name` also
    fails closed as `REFUSED:PACK_IDENTITY_MISMATCH` (the RFC requires the
    projection relation to hold when the graph declares identity; a Core
    pack SHOULD self-describe, §10 -- missing identity is recorded as
    mismatch, per the ticket).
  """
  @spec admit_pack_manifest(String.t() | nil, RDF.Graph.t() | RDF.Dataset.t()) ::
          pack_admission()
  def admit_pack_manifest(nil, _graph), do: :ok

  def admit_pack_manifest(pack_dir, graph) do
    case declared_profile(graph) do
      # §86 step 2 / §89: legacy keeps optional-manifest behavior -- do not
      # even read pack.toml, so a legacy pack cannot newly refuse regardless
      # of what its manifest contains (byte-compat by construction).
      :legacy ->
        :ok

      {:core, profile} ->
        admit_core(pack_dir, graph, profile)
    end
  end

  defp admit_core(pack_dir, graph, profile) do
    case parse_manifest(pack_dir) do
      :absent ->
        {:refused,
         {:pack_manifest_missing,
          diagnostic:
            "pack declares Core profile <#{profile}> but there is no pack.toml at " <>
              "#{Path.join(pack_dir, "pack.toml")} -- RFC-GPACK-001 §12.1/§86.1 makes pack.toml " <>
              "REQUIRED for Core-profile packs ([pack] with name, version, description, §7.1)"}}

      {:refused, _invalid} = refusal ->
        refusal

      {:ok, manifest} ->
        check_identity_correspondence(graph, manifest, profile)
    end
  end

  defp check_identity_correspondence(graph, manifest, profile) do
    declared = declared_pack_names(graph)

    cond do
      declared == [] ->
        {:refused,
         {:pack_identity_mismatch,
          diagnostic:
            "Core-profile pack (<#{profile}>) declares no gp:name in its graph while pack.toml " <>
              "declares name #{inspect(manifest.name)} -- RFC-GPACK-001 §8 Project(I_S)=I_B fails " <>
              "closed: a Core pack SHOULD self-describe (§10), and missing graph identity is " <>
              "treated as mismatch"}}

      Enum.any?(declared, &(&1 != manifest.name)) ->
        {:refused,
         {:pack_identity_mismatch,
          diagnostic:
            "graph gp:name #{inspect(declared |> Enum.uniq() |> Enum.sort())} does not correspond " <>
              "with pack.toml [pack].name #{inspect(manifest.name)} -- RFC-GPACK-001 §8 " <>
              "Project(I_S)=I_B (bootstrap identity and semantic identity MUST agree)"}}

      true ->
        :ok
    end
  end

  @doc """
  Discovers every `<pack_dir>/gates/*.rq` file, sorted lexically (so the
  `NNN_` numeric-prefix convention controls ordering), mapped to
  `{name, path}` where `name` is the filename stem with any leading
  `^\\d+_` digit-prefix stripped: `010_spec.rq` -> `"spec"`, `entities.rq` ->
  `"entities"` (no prefix, no change).
  """
  @spec discover_queries(String.t()) :: [{String.t(), String.t()}]
  def discover_queries(pack_dir) do
    pack_dir
    |> Path.join("gates/*.rq")
    |> Path.wildcard()
    |> Enum.sort()
    |> Enum.map(fn path -> {query_name(path), path} end)
  end

  defp query_name(path) do
    path
    |> Path.basename(".rq")
    |> String.replace(~r/^\d+_/, "")
  end

  @doc """
  Discovers the `--template` under `<pack_dir>/templates/`.

  With `stem` omitted (or `nil`) -- the plain `--pack NAME` case -- returns
  `{:ok, path}` when exactly one `*.eex` or `*.tmpl` file exists,
  `{:error, :none}` when there are zero, or `{:error, {:ambiguous, paths}}`
  when there is more than one (no guessing which of N templates is "the" one).

  With `stem` given -- the `--pack NAME:TEMPLATE_STEM` case (see
  `Mix.Tasks.GgenIgniter.Sync`'s moduledoc) -- selects the one template file
  whose basename up to its first `.` equals `stem` (`"resource.ex.eex"` ->
  stem `"resource"`, `"domain.ex.eex"` -> stem `"domain"`), bypassing the
  ambiguity error entirely even when the pack has multiple templates:
  `{:ok, path}` on a unique match, `{:error, {:stem_not_found, stem, paths}}`
  when no template's stem matches (`paths` lists every template actually
  found, for a helpful error), or `{:error, {:ambiguous, paths}}` in the
  degenerate case of two templates sharing the same stem with different
  extensions (e.g. both `resource.eex` and `resource.tmpl` present).
  """
  @spec discover_template(String.t(), String.t() | nil) ::
          {:ok, String.t()}
          | {:error, :none}
          | {:error, {:ambiguous, [String.t()]}}
          | {:error, {:stem_not_found, String.t(), [String.t()]}}
  def discover_template(pack_dir, stem \\ nil) do
    paths =
      [
        Path.wildcard(Path.join(pack_dir, "templates/*.eex")),
        Path.wildcard(Path.join(pack_dir, "templates/*.tmpl"))
      ]
      |> List.flatten()
      |> Enum.sort()

    select_template(paths, stem)
  end

  @doc """
  The "no template" error text for `pack_dir` (resolved from `opts`). Always
  contains `no *.eex/*.tmpl template found in <pack_dir>/templates/ -- pass
  <flag> explicitly`; when the pack directory itself is missing it is prefixed
  with `missing_dir_message/1`'s explanation, so an unknown `--pack NAME` is
  diagnosed as a missing pack, not as an empty `templates/` dir.
  """
  @spec no_template_message(keyword() | map(), String.t(), String.t()) :: String.t()
  def no_template_message(opts, pack_dir, flag) do
    base = "no *.eex/*.tmpl template found in #{pack_dir}/templates/ -- pass #{flag} explicitly"

    case missing_dir_message(opts) do
      nil -> base
      missing -> "#{missing}: #{base}"
    end
  end

  @doc """
  Every `<pack_dir>/templates/*.{eex,tmpl}` file, sorted -- the fan-out set
  `mix ggen_igniter.sync --pack-dir DIR` renders (each with its own
  frontmatter `to:`) when no `--template` is given and the pack holds more
  than one template (the ggen-marketplace multi-template shape, e.g.
  `ash-extension-pack`).
  """
  @spec discover_templates(String.t()) :: [String.t()]
  def discover_templates(pack_dir) do
    [
      Path.wildcard(Path.join(pack_dir, "templates/*.eex")),
      Path.wildcard(Path.join(pack_dir, "templates/*.tmpl"))
    ]
    |> List.flatten()
    |> Enum.sort()
  end

  defp select_template(paths, nil) do
    case paths do
      [] -> {:error, :none}
      [single] -> {:ok, single}
      many -> {:error, {:ambiguous, many}}
    end
  end

  defp select_template(paths, stem) do
    case Enum.filter(paths, fn path -> template_stem(path) == stem end) do
      [single] -> {:ok, single}
      [] -> {:error, {:stem_not_found, stem, paths}}
      many -> {:error, {:ambiguous, many}}
    end
  end

  # A template's "stem" (for `--pack NAME:STEM` selection) is its basename up
  # to its FIRST `.`, not `Path.basename/2` with a known extension stripped --
  # `"resource.ex.eex"` must resolve to `"resource"`, not `"resource.ex"`, so
  # the stem the CLI accepts is the same one either extension convention
  # (`*.eex`/`*.tmpl`) produces regardless of how many dots follow it.
  defp template_stem(path) do
    path
    |> Path.basename()
    |> String.split(".", parts: 2)
    |> List.first()
  end

  # -- Marketplace fetch ----------------------------------------------------

  @doc """
  Fetches a real marketplace pack over HTTP and extracts it into a local
  cache directory, returning the extracted pack directory (usable directly
  with `resolve_dir!/1` via `pack_dir:`).

  `spec` is one of:

    * `"github:owner/repo"` or `"github:owner/repo@ref"` (ref defaults to
      `"main"`) -- see the moduledoc for what verification this gives you
      (print-only SHA-256, no source-supplied checksum to compare against).
    * `"hex:name"` or `"hex:name@version"` (version defaults to the latest
      stable release per the Hex API) -- fail-closed SHA-256 verification
      against hex.pm's own published release checksum.

  Options:

    * `:cache_dir` -- override the cache root (default
      `~/.cache/ggen_igniter/packs`). Each pack is extracted to a
      spec-derived subdirectory under this root and is safe to re-fetch
      (previous contents at that path are replaced).

  Raises `ArgumentError` for an unrecognized spec, and `RuntimeError` for any
  HTTP failure or (hex only) checksum mismatch.
  """
  @spec fetch_pack!(String.t(), keyword()) :: String.t()
  def fetch_pack!(spec, opts \\ []) do
    cache_root = Keyword.get(opts, :cache_dir, default_cache_dir())
    File.mkdir_p!(cache_root)

    case parse_spec(spec) do
      {:github, owner, repo, ref, subpath} ->
        fetch_github!(owner, repo, ref, subpath, cache_root)

      {:hex, name, version} ->
        fetch_hex!(name, version, cache_root)

      :error ->
        raise ArgumentError,
              "unrecognized pack spec #{inspect(spec)} -- expected \"github:owner/repo[@ref][#subpath]\" or \"hex:name[@version]\""
    end
  end

  defp default_cache_dir, do: Path.join([System.user_home!(), ".cache", "ggen_igniter", "packs"])

  @doc false
  # `github:owner/repo[@ref][#subpath | //subpath]` -> `{:github, owner, repo,
  # ref, subpath | nil}`; `hex:name[@version]` -> `{:hex, name, version}`.
  @spec parse_spec(String.t()) ::
          {:github, String.t(), String.t(), String.t(), String.t() | nil}
          | {:hex, String.t(), String.t() | nil}
          | :error
  def parse_spec("github:" <> rest) do
    {rest, subpath} = split_subpath(rest)

    case String.split(rest, "/", parts: 2) do
      [owner, repo_and_ref] when owner != "" and subpath != :empty ->
        {repo, ref} = split_ref(repo_and_ref, "main")
        if repo == "", do: :error, else: {:github, owner, repo, ref, subpath}

      _ ->
        :error
    end
  end

  def parse_spec("hex:" <> rest) when rest != "" do
    {name, version} = split_ref(rest, nil)
    if name == "", do: :error, else: {:hex, name, version}
  end

  def parse_spec(_), do: :error

  # `#subpath` wins; else the first `//` after `owner/repo` (`@ref` may itself
  # contain single slashes, e.g. `@feature/x`). `:empty` marks a present but
  # empty subpath (`github:o/r#`), refused as an unrecognized spec.
  defp split_subpath(rest) do
    case String.split(rest, "#", parts: 2) do
      [head, ""] ->
        {head, :empty}

      [head, sub] ->
        {head, sub}

      [_] ->
        case String.split(rest, "//", parts: 2) do
          [head, ""] -> {head, :empty}
          [head, sub] -> {head, sub}
          [_] -> {rest, nil}
        end
    end
  end

  defp split_ref(str, default) do
    case String.split(str, "@", parts: 2) do
      [name, ref] -> {name, ref}
      [name] -> {name, default}
    end
  end

  defp fetch_github!(owner, repo, ref, subpath, cache_root) do
    url = "https://github.com/#{owner}/#{repo}/archive/refs/heads/#{ref}.tar.gz"
    body = http_get!(url)
    digest = sha256_hex(body)

    Logger.info(
      "ggen_igniter: fetched github:#{owner}/#{repo}@#{ref} (#{byte_size(body)} bytes), sha256=#{digest} " <>
        "-- GitHub's archive endpoint publishes no checksum to verify against; " <>
        "record this digest yourself if you need to pin/verify this fetch."
    )

    dest = Path.join(cache_root, github_cache_name(owner, repo, ref, subpath))
    extract_archive!(body, dest, strip_top_dir: true, subpath: subpath)
    dest
  end

  defp github_cache_name(owner, repo, ref, nil), do: "github-#{owner}-#{repo}-#{ref}"

  defp github_cache_name(owner, repo, ref, subpath) do
    "github-#{owner}-#{repo}-#{ref}--#{String.replace(subpath, ~r/[^A-Za-z0-9._-]+/, "_")}"
  end

  defp fetch_hex!(name, nil, cache_root) do
    case http_get_json!("https://hex.pm/api/packages/#{name}") do
      %{"releases" => releases} when is_list(releases) and releases != [] ->
        # The Hex API lists releases newest-first but does not itself flag
        # which is "stable" -- take the first version without a pre-release
        # suffix (no "-"), matching Hex's own definition of a stable version.
        stable = Enum.find(releases, fn %{"version" => v} -> not String.contains?(v, "-") end)

        version =
          case stable do
            %{"version" => v} -> v
            nil -> releases |> List.first() |> Map.fetch!("version")
          end

        fetch_hex!(name, version, cache_root)

      other ->
        raise "ggen_igniter: --pack hex:#{name} (no version pinned) could not determine the " <>
                "latest stable release -- hex.pm's package-listing API " <>
                "(GET https://hex.pm/api/packages/#{name}) returned an unexpected shape: " <>
                "#{inspect(other)}. This is user-correctable: either the package name " <>
                "#{inspect(name)} is wrong/unpublished (check https://hex.pm/packages/#{name}), " <>
                "or hex.pm's response shape changed. Next step: pin an explicit version " <>
                "yourself with --pack hex:#{name}@<version> (see the Versions tab on the " <>
                "hex.pm package page for a real version to pin)."
    end
  end

  defp fetch_hex!(name, version, cache_root) do
    release = http_get_json!("https://hex.pm/api/packages/#{name}/releases/#{version}")
    expected_checksum = release |> Map.fetch!("checksum") |> String.downcase()

    tarball_url = "https://repo.hex.pm/tarballs/#{name}-#{version}.tar"
    body = http_get!(tarball_url)
    actual_checksum = sha256_hex(body)

    if actual_checksum != expected_checksum do
      raise "checksum mismatch for hex:#{name}@#{version}: hex.pm published #{expected_checksum}, " <>
              "downloaded tarball hashes to #{actual_checksum} -- refusing to extract (fail-closed)"
    end

    Logger.info(
      "ggen_igniter: verified hex:#{name}@#{version} sha256=#{actual_checksum} against hex.pm's published release checksum"
    )

    dest = Path.join(cache_root, "hex-#{name}-#{version}")
    extract_hex_tarball!(body, dest)
    dest
  end

  # A Hex package tarball is itself a plain (uncompressed) POSIX tar containing
  # VERSION, CHECKSUM, metadata.config, and contents.tar.gz -- the last of
  # these is the real gzipped source tree. Unpack the outer tar to a scratch
  # dir, then extract contents.tar.gz into `dest`.
  defp extract_hex_tarball!(body, dest) do
    with_scratch_dir(fn scratch ->
      outer = Path.join(scratch, "pack.tar")
      File.write!(outer, body)
      :ok = :erl_tar.extract(to_charlist(outer), [{:cwd, to_charlist(scratch)}])

      contents_gz = Path.join(scratch, "contents.tar.gz")

      unless File.exists?(contents_gz) do
        raise "hex tarball did not contain contents.tar.gz -- unexpected Hex package format"
      end

      File.rm_rf!(dest)
      File.mkdir_p!(dest)
      :ok = :erl_tar.extract(to_charlist(contents_gz), [{:cwd, to_charlist(dest)}, :compressed])
    end)

    dest
  end

  @doc false
  # Extracts a `.tar.gz` archive `body` into `dest` and returns `dest`.
  #
  # Options:
  #   * `strip_top_dir: true` -- GitHub's archive tarball wraps everything in a
  #     single top-level `<repo>-<ref>/` directory; strip it so `dest` is the
  #     repo root.
  #   * `subpath: "packs/x"` -- (monorepo) after stripping, `dest` is that
  #     subdirectory of the repo instead. The subpath must be relative, hold
  #     no `..`/empty segments, and no component may be a symlink (an archive
  #     could otherwise point a symlink outside the extracted tree); refused
  #     with `ArgumentError` ("refusing subpath ...") BEFORE `dest` is touched.
  @spec extract_archive!(binary(), String.t(), keyword()) :: String.t()
  def extract_archive!(body, dest, opts) do
    with_scratch_dir(fn scratch ->
      archive = Path.join(scratch, "pack.tar.gz")
      File.write!(archive, body)
      extracted = Path.join(scratch, "extracted")
      File.mkdir_p!(extracted)

      case :erl_tar.extract(to_charlist(archive), [
             {:cwd, to_charlist(extracted)},
             :compressed
           ]) do
        :ok ->
          :ok

        {:error, reason} ->
          # e.g. `{path, :unsafe_symlink}` -- OTP's own extractor refuses a
          # link pointing outside the extraction dir; surface it as a clean
          # refusal rather than a MatchError.
          raise ArgumentError, "refusing archive: #{inspect(reason)}"
      end

      repo_root =
        if Keyword.get(opts, :strip_top_dir, false) do
          single_top_level_dir(extracted)
        else
          extracted
        end

      source_root =
        case Keyword.get(opts, :subpath) do
          nil -> repo_root
          subpath -> resolve_subpath!(repo_root, subpath)
        end

      File.rm_rf!(dest)
      File.cp_r!(source_root, dest)
    end)

    dest
  end

  defp resolve_subpath!(repo_root, subpath) do
    segments = Path.split(subpath)

    cond do
      subpath == "" or Path.type(subpath) != :relative ->
        raise ArgumentError,
              "refusing subpath #{inspect(subpath)}: must be a relative path inside the repository"

      Enum.any?(segments, &(&1 in ["..", ".", ""])) ->
        raise ArgumentError,
              "refusing subpath #{inspect(subpath)}: `..`/`.` segments could escape the extracted archive"

      true ->
        :ok
    end

    target = Path.join(repo_root, subpath)

    unless Path.expand(target) |> String.starts_with?(Path.expand(repo_root) <> "/") do
      raise ArgumentError,
            "refusing subpath #{inspect(subpath)}: resolves outside the extracted archive"
    end

    # No component of the subpath may be a symlink (checked with lstat so a
    # link is never followed).
    segments
    |> Enum.scan(repo_root, fn segment, acc -> Path.join(acc, segment) end)
    |> Enum.each(fn path ->
      case File.lstat(path) do
        {:ok, %File.Stat{type: :symlink}} ->
          raise ArgumentError,
                "refusing subpath #{inspect(subpath)}: component #{inspect(Path.relative_to(path, repo_root))} is a symlink"

        _ ->
          :ok
      end
    end)

    unless File.dir?(target) do
      raise ArgumentError,
            "subpath #{inspect(subpath)} not found in the fetched archive (a directory is required)"
    end

    target
  end

  # GitHub's archive layout wraps everything in exactly one top-level
  # directory; when that's the only entry, descend into it, otherwise leave
  # `extracted` as-is (defensive: an archive that doesn't follow the
  # single-top-level convention).
  defp single_top_level_dir(extracted) do
    case File.ls!(extracted) do
      [only] -> Path.join(extracted, only)
      _ -> extracted
    end
  end

  defp with_scratch_dir(fun) do
    scratch =
      Path.join(
        System.tmp_dir!(),
        "ggen_igniter_fetch_#{System.unique_integer([:positive, :monotonic])}"
      )

    File.mkdir_p!(scratch)

    try do
      fun.(scratch)
    after
      File.rm_rf!(scratch)
    end
  end

  defp sha256_hex(body), do: GgenIgniter.Digest.hex(body)

  # `:tesla` is `optional: true` in `mix.exs`: it still resolves/compiles for
  # THIS project's own dev/test/prod, but a consuming app that adds
  # `ggen_igniter` without adding `:tesla` to its own deps must still be able
  # to compile it. Branching on `Code.ensure_loaded?/1` here (at the FUNCTION
  # level, evaluated once at compile time -- the same technique
  # `lib/ggen_igniter/query/qlever.ex` uses at the module level for `:gno`)
  # means the real `Tesla.client/1`/`Tesla.get/2` calls are only ever compiled
  # when `:tesla` is actually present, so a consumer without it gets a clean
  # compile with no "Tesla is undefined" warnings at all -- not just a
  # RuntimeError deferred to call time.
  if Code.ensure_loaded?(Tesla) do
    defp http_client do
      Tesla.client([
        {Tesla.Middleware.FollowRedirects, max_redirects: 5},
        {Tesla.Middleware.Headers, [{"user-agent", "ggen_igniter/0.1.0 (+https://github.com/)"}]},
        # Scoped only to this module's github:/hex: pack-fetch HTTP path (this
        # is the only `Tesla.client/1` call site in the project) -- retries
        # real transient connection failures (Tesla.Middleware.Retry's
        # default `should_retry` only matches `{:error, _reason}` results,
        # e.g. `nxdomain`/`connrefused`/timeouts, NOT HTTP-level error
        # statuses like 404/500, which `http_get!/1` below already surfaces
        # as a distinct, user-actionable `RuntimeError` and should not be
        # silently retried). `max_retries: 3` and the library's own
        # exponential-backoff-with-jitter `delay`/`max_delay` defaults (50ms
        # base, 5000ms cap -- see `deps/tesla/lib/tesla/middleware/retry.ex`)
        # are sane for a one-shot CLI fetch: enough attempts to ride out a
        # flaky network blip without turning a real, permanent DNS/network
        # failure into a long hang.
        {Tesla.Middleware.Retry, max_retries: 3}
      ])
    end

    defp http_get!(url) do
      # `%{status: ..., body: ...}` (a plain map pattern), NOT `%Tesla.Env{...}`
      # (the `%Struct{}` sugar): the latter requires `Tesla.Env.__struct__/0`
      # to be resolvable at compile time to expand the pattern -- irrelevant
      # to compiling THIS branch (Tesla is loaded here), but kept as a plain
      # map pattern anyway since it matches a `%Tesla.Env{}` struct's
      # `status`/`body` keys identically at runtime (structs are maps).
      case Tesla.get(http_client(), url) do
        {:ok, %{status: 200, body: body}} ->
          body

        {:ok, %{status: status}} ->
          raise "ggen_igniter: --pack fetch GET #{url} failed with HTTP #{status} (expected " <>
                  "200). This is user-correctable: a 404 usually means the package/repo/ref " <>
                  "name or version in your --pack spec is wrong or was never published/pushed " <>
                  "-- verify the spec by opening #{url} in a browser. Next step: fix the " <>
                  "--pack spec and retry `mix ggen_igniter.sync`/`.plan`, or if the URL is " <>
                  "correct and this persists, hex.pm/GitHub may be temporarily unavailable --" <>
                  " retry shortly."

        {:error, reason} ->
          raise "ggen_igniter: --pack fetch GET #{url} failed before a response was received: " <>
                  "#{inspect(reason)}. This is typically a local network/DNS/proxy problem, " <>
                  "not a bad --pack spec. Next step: check your network connectivity to " <>
                  "#{URI.parse(url).host}, then retry `mix ggen_igniter.sync`/`.plan`; if you " <>
                  "are behind a proxy, ensure HTTPS_PROXY is set for this shell."
      end
    end

    defp http_get_json!(url) do
      url
      |> http_get!()
      |> Jason.decode!()
    end
  else
    defp http_get!(_url) do
      raise RuntimeError,
        message:
          "ggen_igniter: :tesla is required for --pack fetch from github:/hex: URLs " <>
            "but is not loaded -- add {:tesla, \"~> 1.8\"} to your own mix.exs deps"
    end

    # Without :tesla `http_get!/1` never returns, so decoding its result is
    # statically dead code (Elixir's type checker warns "incompatible types
    # given to Jason.decode!/1 ... none()" on the piped form). Delegate
    # directly instead.
    defp http_get_json!(url), do: http_get!(url)
  end
end
