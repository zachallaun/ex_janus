Supervisor.start_link([JanusTest.Repo], strategy: :one_for_one, name: JanusTest.Supervisor)
ExUnit.start()
