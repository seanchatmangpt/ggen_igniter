defmodule GgenIgniter.PackManifest do
  @moduledoc """
  Mirrors Rust's marketplace registry `Pack` struct
  (`~/ggen/crates/ggen-marketplace/src/packs_registry/types.rs:6-52`).

  Distinct from `GgenIgniter.PackRef`/`GgenIgniter.PackageToml` below, which
  mirror the *separate*, structurally different `ggen.toml [[packs]]`
  reference type and the local `package.toml` reader
  (`~/ggen/crates/ggen-config/src/manifest/types.rs:54-69,77-94`) -- the real
  Rust codebase itself has these as two unrelated shapes (confirmed by
  review agent), so this module keeps them separate rather than merging them
  into one Elixir type that the Rust side doesn't actually have.
  """

  @enforce_keys [:id, :name, :version, :description, :category, :packages]
  defstruct id: nil,
            name: nil,
            version: nil,
            description: nil,
            category: nil,
            author: nil,
            repository: nil,
            license: nil,
            registry_type: nil,
            packages: [],
            templates: [],
            sparql_queries: %{},
            dependencies: [],
            tags: [],
            keywords: [],
            production_ready: false,
            metadata: %{}

  @type t :: %__MODULE__{
          id: String.t(),
          name: String.t(),
          version: String.t(),
          description: String.t(),
          category: String.t(),
          author: String.t() | nil,
          repository: String.t() | nil,
          license: String.t() | nil,
          registry_type: String.t() | nil,
          packages: [String.t()],
          templates: [GgenIgniter.PackManifest.PackTemplate.t()],
          sparql_queries: %{optional(String.t()) => String.t()},
          dependencies: [GgenIgniter.PackManifest.PackDependency.t()],
          tags: [String.t()],
          keywords: [String.t()],
          production_ready: boolean(),
          metadata: map()
        }
end

defmodule GgenIgniter.PackManifest.PackTemplate do
  @moduledoc "Placeholder mirror of Rust `PackTemplate` (referenced by `types.rs:6-52` but not itself read in this pass)."
  defstruct [:path, :description]
  @type t :: %__MODULE__{path: String.t() | nil, description: String.t() | nil}
end

defmodule GgenIgniter.PackManifest.PackDependency do
  @moduledoc "Mirrors Rust `PackDependency` (`~/ggen/crates/ggen-marketplace/src/packs_registry/types.rs:65-70`)."
  defstruct [:pack_id, :version, optional: false]

  @type t :: %__MODULE__{
          pack_id: String.t() | nil,
          version: String.t() | nil,
          optional: boolean()
        }

  @doc """
  Builds a `t:t/0` from a plain string-keyed map (the Rust struct's field is
  `pack_id`, not `name` -- no rename), defaulting `"optional"` to `false`
  when absent, mirroring the `#[serde(default)]` behavior on the Rust side.
  """
  @spec from_map(map()) :: t()
  def from_map(map) when is_map(map) do
    %__MODULE__{
      pack_id: Map.get(map, "pack_id"),
      version: Map.get(map, "version"),
      optional: Map.get(map, "optional", false)
    }
  end
end

defmodule GgenIgniter.PackRef do
  @moduledoc """
  Mirrors Rust `ggen_config::manifest::PackRef`
  (`~/ggen/crates/ggen-config/src/manifest/types.rs:54-69`) -- the
  `ggen.toml [[packs]]` reference entry.

  **Schema scope, a resolved and intentional decision** (from the Rust
  source's own doc comments): a *second*, structurally incompatible
  `PackRef` also exists at `ggen_engine::config::PackRef` (an untagged
  `Path{path,extra_ontologies,lock} | Git{git,version}` enum, `[packs]` as a
  table-of-tables keyed by name rather than an array-of-tables) -- which one
  a given `ggen.toml` uses is decided by `GgenIgniter.SchemaDispatch`, the
  one shared classifier/dispatch point (never re-derived locally). This
  module mirrors the array-of-tables (`ggen-config`)/`DeclarativeRules`
  shape only; its now-real sibling for the other schema is
  `GgenIgniter.FrontmatterPackRef`.
  """

  defstruct [:name, :path, :version, registry: "local"]

  @type t :: %__MODULE__{
          name: String.t(),
          registry: String.t(),
          path: String.t() | nil,
          version: String.t() | nil
        }
end

defmodule GgenIgniter.PackageToml do
  @moduledoc "Mirrors Rust `PackageToml` (`ggen-config/src/manifest/types.rs:77-84`) -- the local `package.toml` reader."
  defstruct pack: nil, outputs: %{}

  @type t :: %__MODULE__{
          pack: GgenIgniter.PackageToml.PackSection.t() | nil,
          outputs: %{optional(String.t()) => String.t()}
        }
end

defmodule GgenIgniter.PackageToml.PackSection do
  @moduledoc "Mirrors Rust `PackSection` (`ggen-config/src/manifest/types.rs:88-94`)."
  defstruct outputs: %{}
  @type t :: %__MODULE__{outputs: %{optional(String.t()) => String.t()}}
end
