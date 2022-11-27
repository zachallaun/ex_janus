defmodule Janus.DataCase do
  @moduledoc """
  Defines the setup for tests that use the `JanusTest` repo and schemas.

  Aliases `Repo` and all schemas.
  """

  use ExUnit.CaseTemplate

  alias JanusTest.Repo
  alias JanusTest.Schemas.{User, Post, Thread}

  using do
    quote do
      alias JanusTest.Repo
      alias JanusTest.Schemas.{User, Post, Thread}
    end
  end

  setup_all do
    start_supervised!(Repo)
    :ok
  end

  setup do
    on_exit(:drop_repo_data, fn ->
      for schema <- [User, Post, Thread] do
        Repo.delete_all(schema)
      end
    end)
  end
end
