defmodule JanusTest.Repo do
  use Ecto.Repo,
    otp_app: :janus,
    adapter: Ecto.Adapters.Postgres,
    pool: Ecto.Adapters.SQL.Sandbox,
    database: "janus_test",
    username: "dev",
    password: "dev",
    hostname: "localhost"
end
