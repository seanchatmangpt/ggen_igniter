import Config

config :book_library, BookLibrary.Repo,
  username: "postgres",
  password: "postgres",
  hostname: "localhost",
  database: "book_library_qual_20260908205846_dev",
  show_sensitive_data_on_connection_error: true,
  pool_size: 10

config :ash, policies: [show_policy_breakdowns?: true]
