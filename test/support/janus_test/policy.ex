defmodule JanusTest.Policy do
  use Janus, repo: JanusTest.Repo

  @impl true
  def build_policy(policy, _actor), do: policy
end
