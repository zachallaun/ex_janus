import Config

if System.get_env("ECTO_DEBUG") do
  config :logger, level: :debug
end
