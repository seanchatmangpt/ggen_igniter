import Config

config :dcatr,
  env: Mix.env(),
  load_path: ["config/gno"],
  manifest_type: Gno.Manifest,
  manifest_base: "http://example.com/"

# Ash 3.33+ requires an explicit string-length count mode; ash_ai/ash_a2a
# (dev/test deps) compile Ash resources and fail without it.
config :ash, default_string_length_count: :codepoints

config :tesla, adapter: {Tesla.Adapter.Finch, name: GgenIgniter.Finch}

import_config "#{Mix.env()}.exs"
