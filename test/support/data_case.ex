defmodule Janus.DataCase do
  @moduledoc """
  Defines the setup for tests that use the `JanusTest` repo and schemas.

  Aliases `Repo` and all schemas.
  """

  use ExUnit.CaseTemplate

  using do
    quote do
      import JanusTest.Fixtures
      alias JanusTest.{Forum, Repo}
      alias JanusTest.Schemas.{User, Post, Thread}
    end
  end

  setup do
    :ok = Ecto.Adapters.SQL.Sandbox.checkout(JanusTest.Repo)
  end
end
