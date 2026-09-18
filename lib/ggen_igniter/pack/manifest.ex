defmodule GgenIgniter.Pack.Manifest do
  @moduledoc """
  The RFC-GPACK-001 §7.1 bootstrap manifest (`pack.toml`) as parsed by
  `GgenIgniter.Pack.parse_manifest/1`:

  ```toml
  [pack]
  name = "example-pack"
  version = "1.2.3"
  description = "Example semantic manufacturing pack."
  ```

  `name`, `version`, and `description` are REQUIRED (§7.1); a Core v1
  implementation MUST reject unknown keys inside `[pack]` (§7.1) -- that
  strictness is enforced at parse time by `GgenIgniter.Pack.parse_manifest/1`,
  not by this struct. The manifest exists to answer "what object is this,
  which version, what is it called, what is its human summary" (§7.2) -- it
  MUST NOT become a second ontology; dependencies, capabilities, lifecycle,
  authority, and every other protocol extension belong in the pack's RDF
  graph.

  **Deliberately distinct from `GgenIgniter.PackManifest`** (no dot), which
  mirrors Rust's *marketplace registry* `Pack` struct
  (`ggen-marketplace/src/packs_registry/types.rs`) -- a different, richer
  shape. This struct is the per-pack-directory `pack.toml` bootstrap header
  (RFC-GPACK-001 §5.3), the one Rust `ggen` already parses strictly and
  `GgenIgniter.Pack` historically ignored (RFC-GPACK-001 §4.2/D3).
  """

  @enforce_keys [:name, :version, :description]
  defstruct [:name, :version, :description]

  @type t :: %__MODULE__{
          name: String.t(),
          version: String.t(),
          description: String.t()
        }
end
