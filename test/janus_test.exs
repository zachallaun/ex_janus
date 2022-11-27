defmodule JanusTest do
  use ExUnit.Case
  import JanusTest.Fixtures

  describe "basic guest policy" do
    defmodule BasicGuestPolicy do
      use Janus

      alias JanusTest.Schemas.{Thread, Post}

      @impl true
      def policy_for(policy \\ %Janus.Policy{}, actor)

      def policy_for(policy, :basic_read) do
        policy
        |> allow(:read, Thread)
        |> allow(:read, Post)
      end

      def policy_for(policy, :basic_forbid) do
        policy
        |> allow(:read, Post)
        |> forbid(:read, Post)
      end
    end

    test ":basic_read" do
      post = post_fixture()

      assert BasicGuestPolicy.allows?(:basic_read, :read, post)
      assert BasicGuestPolicy.allows?(:basic_read, :read, post.thread)
      assert BasicGuestPolicy.forbids?(:basic_read, :update, post)
      assert BasicGuestPolicy.forbids?(:basic_read, :read, post.author)
    end

    test ":basic_forbid" do
      post = post_fixture()

      assert BasicGuestPolicy.forbids?(:basic_forbid, :read, post)
    end
  end
end
