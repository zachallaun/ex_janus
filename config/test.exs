import Config

config :janus, ecto_repos: [JanusTest.Repo]

config :janus, JanusTest.Repo,
  database: "janus_test",
  username: "dev",
  password: "dev",
  hostname: "localhost",
  pool: Ecto.Adapters.SQL.Sandbox

config :logger, level: :warn
