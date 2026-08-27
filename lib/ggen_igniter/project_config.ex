defmodule GgenIgniter.ProjectConfig.Law do
  @moduledoc "Mirrors Rust `Law` (`manifest/types.rs:...` near `GgenManifest`)."
  defstruct rules: []
  @type t :: %__MODULE__{rules: [String.t()]}
end

defmodule GgenIgniter.ProjectConfig.ProjectSection do
  @moduledoc "Mirrors Rust `ProjectConfig` -- `ggen.toml [project]` (`manifest/types.rs:280-305`)."
  @enforce_keys [:name, :version]
  defstruct [:name, :version, :description, :authors, :license, :repository]

  @type t :: %__MODULE__{
          name: String.t(),
          version: String.t(),
          description: String.t() | nil,
          authors: [String.t()] | nil,
          license: String.t() | nil,
          repository: String.t() | nil
        }
end

defmodule GgenIgniter.ProjectConfig.OntologyConfig do
  @moduledoc "Mirrors Rust `OntologyConfig` -- `ggen.toml [ontology]`/`[ontology.prefixes]` (`manifest/types.rs:307-329`)."
  @enforce_keys [:source]
  defstruct [:source, :base_iri, :standard_only, imports: [], prefixes: %{}]

  @type t :: %__MODULE__{
          source: String.t(),
          imports: [String.t()],
          base_iri: String.t() | nil,
          prefixes: %{optional(String.t()) => String.t()},
          standard_only: boolean() | nil
        }
end

defmodule GgenIgniter.ProjectConfig.InferenceRule do
  @moduledoc "Mirrors Rust `InferenceRule` -- `ggen.toml [[inference.rules]]` (`manifest/types.rs:345-365`)."
  @enforce_keys [:name, :construct]
  defstruct [:name, :description, :construct, :when, order: 0]

  @type t :: %__MODULE__{
          name: String.t(),
          description: String.t() | nil,
          construct: String.t(),
          order: integer(),
          when: String.t() | nil
        }
end

defmodule GgenIgniter.ProjectConfig.InferenceConfig do
  @moduledoc "Mirrors Rust `InferenceConfig` -- `ggen.toml [inference]` (`manifest/types.rs:331-343`)."
  defstruct rules: [], max_reasoning_timeout_ms: 30_000

  @type t :: %__MODULE__{
          rules: [GgenIgniter.ProjectConfig.InferenceRule.t()],
          max_reasoning_timeout_ms: non_neg_integer()
        }
end

defmodule GgenIgniter.ProjectConfig.QuerySource do
  @moduledoc """
  Mirrors Rust `#[serde(untagged)] enum QuerySource { Pack{..}, File{..}, Inline{..} }`.
  As with `GgenIgniter.Frontmatter.MatchSpec`, represented as a tagged tuple
  since Elixir has no untagged-union deserialization primitive.
  """
  @type t ::
          {:pack, %{pack: String.t(), output: String.t(), file: String.t()}}
          | {:file, %{file: String.t()}}
          | {:inline, %{inline: String.t()}}
end

defmodule GgenIgniter.ProjectConfig.TemplateSource do
  @moduledoc """
  Mirrors Rust `#[serde(untagged)] enum TemplateSource { Pack{..}, File{..}, Inline{..}, Git{..}, Package{..} }`.
  """
  @type t ::
          {:pack, %{pack: String.t(), output: String.t(), file: String.t()}}
          | {:file, %{file: String.t()}}
          | {:inline, %{inline: String.t()}}
          | {:git, %{git: String.t(), branch: String.t() | nil, path: String.t()}}
          | {:package, %{package: String.t(), version: String.t() | nil, path: String.t()}}
end

defmodule GgenIgniter.ProjectConfig.GenerationRule do
  @moduledoc "Mirrors Rust `GenerationRule` -- `ggen.toml [[generation.rules]]` (`manifest/types.rs:...`)."
  @enforce_keys [:name, :query, :template, :output_file]
  defstruct [:name, :query, :template, :output_file, :when, skip_empty: false, mode: :create]

  @type t :: %__MODULE__{
          name: String.t(),
          query: GgenIgniter.ProjectConfig.QuerySource.t(),
          template: GgenIgniter.ProjectConfig.TemplateSource.t(),
          output_file: String.t(),
          skip_empty: boolean(),
          mode: :create | :overwrite | :merge,
          when: String.t() | nil
        }
end

defmodule GgenIgniter.ProjectConfig.GenerationConfig do
  @moduledoc "Mirrors Rust `GenerationConfig` -- `ggen.toml [generation]` (`manifest/types.rs:367-384`)."
  @enforce_keys [:rules]
  defstruct [
    :rules,
    max_sparql_timeout_ms: 30_000,
    require_audit_trail: false,
    determinism_salt: nil,
    output_dir: "generated",
    enable_llm: false,
    llm_provider: nil,
    llm_model: nil
  ]

  @type t :: %__MODULE__{
          rules: [GgenIgniter.ProjectConfig.GenerationRule.t()],
          max_sparql_timeout_ms: non_neg_integer(),
          require_audit_trail: boolean(),
          determinism_salt: String.t() | nil,
          output_dir: String.t(),
          enable_llm: boolean(),
          llm_provider: String.t() | nil,
          llm_model: String.t() | nil
        }
end

defmodule GgenIgniter.ProjectConfig.ValidationRule do
  @moduledoc """
  Mirrors Rust `ValidationRule` (`manifest/types.rs:611-637`) -- the closest
  typed shape to a "gate" in the real Rust codebase.

  **Real caveat, confirmed by review agent**: there is no typed `Gate`/
  `GateResult` struct anywhere in `~/ggen`. The actual `[validation].gates`
  mechanism the real `ggen.toml` uses is untyped: `gates: [String.t()]`
  (declared on `GgenIgniter.ProjectConfig.ValidationConfig` below) pointing
  at standalone `.rq` files, each an ASK (true = violation) or SELECT (any
  row = violation) query -- pass/fail on query evaluation, no in-memory
  result struct. `GgenIgniter.Gate` (if/when built) should mirror that same
  untyped, query-evaluation-only reality rather than inventing a typed
  gate-result shape the Rust side doesn't have.
  """
  @enforce_keys [:name, :description, :ask]
  defstruct [:name, :description, :ask, severity: :error]

  @type t :: %__MODULE__{
          name: String.t(),
          description: String.t(),
          ask: String.t(),
          severity: :error | :warning
        }
end

defmodule GgenIgniter.ProjectConfig.ValidationConfig do
  @moduledoc "Mirrors Rust `ValidationConfig` -- `ggen.toml [validation]` (`manifest/types.rs:553-609`)."
  defstruct shacl: [],
            gates: [],
            validate_syntax: false,
            no_unsafe: false,
            strict_mode: true,
            rules: []

  @type t :: %__MODULE__{
          shacl: [String.t()],
          gates: [String.t()],
          validate_syntax: boolean(),
          no_unsafe: boolean(),
          strict_mode: boolean(),
          rules: [GgenIgniter.ProjectConfig.ValidationRule.t()]
        }
end

defmodule GgenIgniter.ProjectConfig do
  @moduledoc """
  Mirrors Rust `GgenManifest`, the `ggen.toml` root config struct
  (`~/ggen/crates/ggen-config/src/manifest/types.rs:171-265`, confirmed
  against the real, current `~/ggen/ggen.toml` example).

  Only the fields `ggen_igniter` has any real use for yet are given full
  nested-struct shapes below (`project`, `ontology`, `inference`,
  `generation`, `validation`, `packs`, `law`). The remaining `Option<toml::
  Value>` / free-form fields on the Rust struct (`sync`, `output`, `rdf`,
  `templates`, `ai`, `sparql`, `lifecycle`, `security`, `performance`,
  `logging`, `telemetry`, `features`, `env`, `build`, `test`, `package`,
  `mcp`, `a2a`) are kept here as opaque `map() | nil` passthroughs -- mirrored
  by presence and name, not by internal shape, since the Rust side itself
  treats most of them as opaque `toml::Value` today.

  **Real caveat** (from the Rust source's own doc comments, confirmed by
  review agent): a second, structurally different `ggen.toml` schema
  (`ggen_engine::config::GgenConfig`) also exists in the real codebase --
  chosen instead of this one, at parse time, when `[[generation.rules]]` is
  empty. This module mirrors `ggen_config::manifest::GgenManifest` only.
  """

  defstruct [
    :project,
    :ontology,
    :generation,
    inference: %GgenIgniter.ProjectConfig.InferenceConfig{},
    validation: %GgenIgniter.ProjectConfig.ValidationConfig{},
    packs: [],
    law: %GgenIgniter.ProjectConfig.Law{},
    sync: nil,
    output: nil,
    rdf: nil,
    templates: nil,
    ai: nil,
    sparql: nil,
    lifecycle: nil,
    security: nil,
    performance: nil,
    logging: nil,
    telemetry: nil,
    features: nil,
    env: nil,
    build: nil,
    test: nil,
    package: nil,
    mcp: nil,
    a2a: nil
  ]

  @type t :: %__MODULE__{
          project: GgenIgniter.ProjectConfig.ProjectSection.t(),
          ontology: GgenIgniter.ProjectConfig.OntologyConfig.t(),
          inference: GgenIgniter.ProjectConfig.InferenceConfig.t(),
          generation: GgenIgniter.ProjectConfig.GenerationConfig.t(),
          validation: GgenIgniter.ProjectConfig.ValidationConfig.t(),
          packs: [GgenIgniter.PackRef.t()],
          law: GgenIgniter.ProjectConfig.Law.t(),
          sync: map() | nil,
          output: map() | nil,
          rdf: map() | nil,
          templates: map() | nil,
          ai: map() | nil,
          sparql: map() | nil,
          lifecycle: map() | nil,
          security: map() | nil,
          performance: map() | nil,
          logging: map() | nil,
          telemetry: map() | nil,
          features: %{optional(String.t()) => boolean()} | nil,
          env: map() | nil,
          build: map() | nil,
          test: map() | nil,
          package: map() | nil,
          mcp: map() | nil,
          a2a: map() | nil
        }
end
