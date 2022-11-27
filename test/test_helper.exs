ExUnit.start()

{:ok, _} = Supervisor.start_link([JanusTest.Repo], strategy: :one_for_one)
Ecto.Adapters.SQL.Sandbox.mode(JanusTest.Repo, :manual)
