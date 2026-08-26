import Config

config :dcatr,
  env: Mix.env(),
  load_path: ["config/gno"],
  manifest_type: Gno.Manifest,
  manifest_base: "http://example.com/"

config :tesla, adapter: {Tesla.Adapter.Finch, name: GgenIgniter.Finch}

import_config "#{Mix.env()}.exs"
