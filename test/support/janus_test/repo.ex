defmodule JanusTest.Repo do
  use Ecto.Repo,
    otp_app: :ex_janus,
    adapter: Ecto.Adapters.Postgres
end
