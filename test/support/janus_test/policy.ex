defmodule JanusTest.Policy do
  use Janus.Authorization, policy: __MODULE__
  use Janus.Policy, repo: JanusTest.Repo

  alias JanusTest.Schemas.Post
  alias JanusTest.Schemas.Thread

  @impl true
  def build_policy(policy, _actor) do
    policy
    |> allow(Post, :read)
    |> allow(Thread, :read, where: [archived: false])
  end
end
