import Config

config :ash,
  allow_forbidden_field_for_relationships_by_default: true,
  show_keysets_for_all_actions?: false,
  default_page_type: :keyset,
  policies: [no_filter_static_forbidden_reads?: false],
  keep_read_action_loads_when_loading?: false,
  default_actions_require_atomic?: true,
  read_action_after_action_hooks_in_order?: true,
  bulk_actions_default_to_errors?: true,
  transaction_rollback_on_error?: true,
  redact_sensitive_values_in_errors?: true,
  default_string_length_count: :codepoints,
  many_to_many_destroy_destination_on_match?: true,
  known_types: [AshPostgres.Timestamptz, AshPostgres.TimestamptzUsec]

config :spark,
  formatter: [
    remove_parens?: true,
    "Ash.Resource": [
      section_order: [
        :postgres,
        :resource,
        :code_interface,
        :actions,
        :policies,
        :pub_sub,
        :preparations,
        :changes,
        :validations,
        :multitenancy,
        :attributes,
        :relationships,
        :calculations,
        :aggregates,
        :identities
      ]
    ],
    "Ash.Domain": [section_order: [:resources, :policies, :authorization, :domain, :execution]]
  ]

# Day zero: no domains registered. `mix ash.gen.domain` (composed by
# `mix book_library.manufacture --phase core`) appends to this list;
# `mix ash_postgres.install` (phase base) adds `ecto_repos:`;
# `mix ash.gen.base_resource` (phase base) adds `base_resources:`.
config :book_library,
  ash_domains: [BookLibrary.Circulation, BookLibrary.Catalog],
  ecto_repos: [BookLibrary.Repo],
  base_resources: [BookLibrary.Resource]

config :ash, :include_embedded_source_by_default?, false

import_config "#{config_env()}.exs"
