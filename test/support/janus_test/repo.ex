defmodule JanusTest.Repo do
  use Ecto.Repo,
    otp_app: :janus,
    adapter: Etso.Adapter
end
