import Config

config :laravex,
  env_file: ".env"

config :logger, :console,
  format: "$time $metadata[$level] $message\n"

import_config "#{config_env()}.exs"
