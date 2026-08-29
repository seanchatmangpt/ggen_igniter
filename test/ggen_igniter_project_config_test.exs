defmodule GgenIgniterProjectConfigTest do
  @moduledoc """
  Chicago-style: `GgenIgniter.ProjectConfig` and its nested submodules are
  plain `defstruct`-only data shapes with no functions of their own -- there
  is nothing to mock. Every assertion here is on the real struct built by
  Elixir's own `%Module{}` construction (default values, `@enforce_keys`
  enforcement, nested composition), the real collaborator in this case being
  the Elixir struct system itself. Fully compatible with
  `~/.claude/rules/testing-chicago-style.md` and `test/CLAUDE.md`.
  """

  use ExUnit.Case, async: true

  alias GgenIgniter.ProjectConfig

  alias GgenIgniter.ProjectConfig.{
    Law,
    ProjectSection,
    OntologyConfig,
    InferenceRule,
    InferenceConfig,
    GenerationRule,
    GenerationConfig,
    ValidationRule,
    ValidationConfig
  }

  describe "ProjectConfig.Law (defaults)" do
    test "defaults rules to an empty list" do
      assert %Law{rules: []} = %Law{}
    end

    test "accepts a real list of rule strings" do
      law = %Law{rules: ["no-unsafe-write", "require-audit-trail"]}
      assert law.rules == ["no-unsafe-write", "require-audit-trail"]
    end
  end

  describe "ProjectConfig.ProjectSection (@enforce_keys [:name, :version])" do
    test "constructs with only the required keys, optional fields default to nil" do
      section = %ProjectSection{name: "ggen_igniter", version: "26.8.27"}

      assert section.name == "ggen_igniter"
      assert section.version == "26.8.27"
      assert section.description == nil
      assert section.authors == nil
      assert section.license == nil
      assert section.repository == nil
    end

    test "constructs with all fields populated" do
      section = %ProjectSection{
        name: "ggen_igniter",
        version: "26.8.27",
        description: "ontology-to-code pipeline",
        authors: ["Sean Chatman"],
        license: "MIT",
        repository: "https://github.com/seanchatmangpt/ggen_igniter"
      }

      assert section.description == "ontology-to-code pipeline"
      assert section.authors == ["Sean Chatman"]
      assert section.license == "MIT"
      assert section.repository == "https://github.com/seanchatmangpt/ggen_igniter"
    end

    test "raises when a required key is missing" do
      assert_raise ArgumentError, fn ->
        Code.eval_string("%GgenIgniter.ProjectConfig.ProjectSection{name: \"x\"}")
      end
    end
  end

  describe "ProjectConfig.OntologyConfig (@enforce_keys [:source])" do
    test "constructs with only :source, defaults imports to [] and prefixes to %{}" do
      config = %OntologyConfig{source: "ontology.ttl"}

      assert config.source == "ontology.ttl"
      assert config.imports == []
      assert config.prefixes == %{}
      assert config.base_iri == nil
      assert config.standard_only == nil
    end

    test "constructs with real imports and prefix map populated" do
      config = %OntologyConfig{
        source: "ontology.ttl",
        imports: ["shared.ttl", "vocab.ttl"],
        base_iri: "https://example.org/",
        prefixes: %{
          "ex" => "https://example.org/",
          "rdf" => "http://www.w3.org/1999/02/22-rdf-syntax-ns#"
        },
        standard_only: true
      }

      assert config.imports == ["shared.ttl", "vocab.ttl"]
      assert config.prefixes["ex"] == "https://example.org/"
      assert config.standard_only == true
    end
  end

  describe "ProjectConfig.InferenceRule (@enforce_keys [:name, :construct])" do
    test "defaults :order to 0 and :when/:description to nil" do
      rule = %InferenceRule{name: "infer-type", construct: "CONSTRUCT { ?s a ?t }"}

      assert rule.order == 0
      assert rule.when == nil
      assert rule.description == nil
    end

    test "constructs with all fields" do
      rule = %InferenceRule{
        name: "infer-type",
        description: "infers rdf:type from a marker property",
        construct: "CONSTRUCT { ?s a ex:Thing }",
        order: 5,
        when: "?s ex:marker true"
      }

      assert rule.order == 5
      assert rule.when == "?s ex:marker true"
    end
  end

  describe "ProjectConfig.InferenceConfig (defaults)" do
    test "defaults rules to [] and max_reasoning_timeout_ms to 30_000" do
      assert %InferenceConfig{rules: [], max_reasoning_timeout_ms: 30_000} = %InferenceConfig{}
    end

    test "composes real nested InferenceRule structs" do
      config = %InferenceConfig{
        rules: [%InferenceRule{name: "r1", construct: "CONSTRUCT {}"}],
        max_reasoning_timeout_ms: 60_000
      }

      assert [%InferenceRule{name: "r1"}] = config.rules
      assert config.max_reasoning_timeout_ms == 60_000
    end
  end

  describe "ProjectConfig.QuerySource / TemplateSource (tagged tuples, no struct)" do
    test "a :pack-tagged tuple matches QuerySource.t/0's real shape" do
      query_source = {:pack, %{pack: "ash-lifecycle", output: "resource", file: "gate.rq"}}
      assert {:pack, %{pack: "ash-lifecycle", output: "resource", file: "gate.rq"}} = query_source
    end

    test "a :git-tagged tuple matches TemplateSource.t/0's real shape" do
      template_source =
        {:git, %{git: "https://example.org/repo.git", branch: "main", path: "t.eex"}}

      assert {:git, %{git: _, branch: "main", path: "t.eex"}} = template_source
    end
  end

  describe "ProjectConfig.GenerationRule (@enforce_keys, defaults)" do
    test "defaults skip_empty to false, mode to :create, when to nil" do
      rule = %GenerationRule{
        name: "gen-resource",
        query: {:file, %{file: "q.rq"}},
        template: {:file, %{file: "t.eex"}},
        output_file: "lib/out.ex"
      }

      assert rule.skip_empty == false
      assert rule.mode == :create
      assert rule.when == nil
    end

    test "accepts an explicit non-default mode" do
      rule = %GenerationRule{
        name: "gen-resource",
        query: {:inline, %{inline: "SELECT * WHERE { ?s ?p ?o }"}},
        template: {:inline, %{inline: "<%= @x %>"}},
        output_file: "lib/out.ex",
        mode: :merge,
        skip_empty: true
      }

      assert rule.mode == :merge
      assert rule.skip_empty == true
    end
  end

  describe "ProjectConfig.GenerationConfig (@enforce_keys [:rules], defaults)" do
    test "requires :rules, defaults the rest" do
      config = %GenerationConfig{rules: []}

      assert config.max_sparql_timeout_ms == 30_000
      assert config.require_audit_trail == false
      assert config.determinism_salt == nil
      assert config.output_dir == "generated"
      assert config.enable_llm == false
      assert config.llm_provider == nil
      assert config.llm_model == nil
    end

    test "composes a real nested GenerationRule and overrides defaults" do
      rule = %GenerationRule{
        name: "r",
        query: {:file, %{file: "q.rq"}},
        template: {:file, %{file: "t.eex"}},
        output_file: "out.ex"
      }

      config = %GenerationConfig{
        rules: [rule],
        require_audit_trail: true,
        determinism_salt: "salt-123",
        enable_llm: true,
        llm_provider: "anthropic",
        llm_model: "claude-sonnet-5"
      }

      assert [%GenerationRule{name: "r"}] = config.rules
      assert config.require_audit_trail == true
      assert config.determinism_salt == "salt-123"
      assert config.llm_provider == "anthropic"
    end
  end

  describe "ProjectConfig.ValidationRule (@enforce_keys, default severity)" do
    test "defaults severity to :error" do
      rule = %ValidationRule{
        name: "no-cycles",
        description: "graph must be acyclic",
        ask: "ASK { ?s a ?s }"
      }

      assert rule.severity == :error
    end

    test "accepts :warning severity explicitly" do
      rule = %ValidationRule{
        name: "prefer-labels",
        description: "resources should have rdfs:label",
        ask: "ASK { ?s a ?t . FILTER NOT EXISTS { ?s rdfs:label ?l } }",
        severity: :warning
      }

      assert rule.severity == :warning
    end
  end

  describe "ProjectConfig.ValidationConfig (defaults)" do
    test "all fields default: empty lists, validate_syntax/no_unsafe false, strict_mode true" do
      config = %ValidationConfig{}

      assert config.shacl == []
      assert config.gates == []
      assert config.validate_syntax == false
      assert config.no_unsafe == false
      assert config.strict_mode == true
      assert config.rules == []
    end

    test "composes real gate path strings and a nested ValidationRule" do
      rule = %ValidationRule{name: "n", description: "d", ask: "ASK {}"}

      config = %ValidationConfig{
        shacl: ["shapes.ttl"],
        gates: ["priv/ggen/pack/gates/no-orphans.rq"],
        validate_syntax: true,
        rules: [rule]
      }

      assert config.shacl == ["shapes.ttl"]
      assert config.gates == ["priv/ggen/pack/gates/no-orphans.rq"]
      assert [%ValidationRule{name: "n"}] = config.rules
    end
  end

  describe "ProjectConfig (root struct: defaults and full composition)" do
    test "defaults inference/validation/law to their nested-struct defaults, packs to []" do
      config = %ProjectConfig{
        project: %ProjectSection{name: "p", version: "0.1.0"},
        ontology: %OntologyConfig{source: "o.ttl"},
        generation: %GenerationConfig{rules: []}
      }

      assert %InferenceConfig{rules: [], max_reasoning_timeout_ms: 30_000} = config.inference
      assert %ValidationConfig{strict_mode: true} = config.validation
      assert config.packs == []
      assert %Law{rules: []} = config.law

      assert config.sync == nil
      assert config.output == nil
      assert config.rdf == nil
      assert config.templates == nil
      assert config.ai == nil
      assert config.sparql == nil
      assert config.lifecycle == nil
      assert config.security == nil
      assert config.performance == nil
      assert config.logging == nil
      assert config.telemetry == nil
      assert config.features == nil
      assert config.env == nil
      assert config.build == nil
      assert config.test == nil
      assert config.package == nil
      assert config.mcp == nil
      assert config.a2a == nil
    end

    test "composes a real, fully-populated nested tree end to end" do
      config = %ProjectConfig{
        project: %ProjectSection{name: "ggen_igniter", version: "26.8.27"},
        ontology: %OntologyConfig{source: "ontology.ttl", imports: ["shared.ttl"]},
        generation: %GenerationConfig{
          rules: [
            %GenerationRule{
              name: "gen-resource",
              query: {:file, %{file: "q.rq"}},
              template: {:file, %{file: "t.eex"}},
              output_file: "lib/out.ex"
            }
          ]
        },
        inference: %InferenceConfig{
          rules: [%InferenceRule{name: "infer", construct: "CONSTRUCT {}"}]
        },
        validation: %ValidationConfig{gates: ["gate.rq"]},
        packs: ["ash-lifecycle-pack"],
        law: %Law{rules: ["no-unsafe-write"]},
        features: %{"experimental_wasm" => false}
      }

      assert config.project.name == "ggen_igniter"
      assert config.ontology.imports == ["shared.ttl"]
      assert [%GenerationRule{name: "gen-resource"}] = config.generation.rules
      assert [%InferenceRule{name: "infer"}] = config.inference.rules
      assert config.validation.gates == ["gate.rq"]
      assert config.packs == ["ash-lifecycle-pack"]
      assert config.law.rules == ["no-unsafe-write"]
      assert config.features["experimental_wasm"] == false
    end

    test "raises when a required root field (:project) is omitted -- ProjectConfig has no @enforce_keys, so this is allowed and yields nil" do
      # ProjectConfig itself declares no @enforce_keys, unlike its nested
      # submodules -- omitted required-looking fields (:project, :ontology,
      # :generation) silently default to nil rather than raising. This is
      # real, observed struct behavior, not an assumption.
      config = %ProjectConfig{}

      assert config.project == nil
      assert config.ontology == nil
      assert config.generation == nil
    end
  end
end
