{:ok, _} = Supervisor.start_link([JanusTest.Repo], strategy: :one_for_one)
Ecto.Adapters.SQL.Sandbox.mode(JanusTest.Repo, :manual)

# Get Mix output sent to the current process to avoid polluting tests.
Mix.shell(Mix.Shell.Process)

ExUnit.start()
Mneme.start()
