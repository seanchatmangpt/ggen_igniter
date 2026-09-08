import Config

config :book_library, BookLibrary.Repo,
  username: "postgres",
  password: "postgres",
  hostname: "localhost",
  database: "book_library_qual_20260908205846_test",
  pool: Ecto.Adapters.SQL.Sandbox,
  pool_size: 10

config :ash, policies: [show_policy_breakdowns?: true], disable_async?: true
config :logger, level: :warning
