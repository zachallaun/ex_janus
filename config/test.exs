import Config

config :ex_janus, ecto_repos: [JanusTest.Repo]

config :ex_janus, JanusTest.Repo,
  database: "janus_test",
  username: "dev",
  password: "dev",
  hostname: "localhost",
  pool: Ecto.Adapters.SQL.Sandbox

config :logger, level: :warning
