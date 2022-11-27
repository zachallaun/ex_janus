defmodule JanusTest do
  use ExUnit.Case
  import JanusTest.Fixtures

  describe "basic guest policy" do
    defmodule BasicGuestPolicy do
      use Janus

      alias JanusTest.Schemas.{Thread, Post}

      @impl true
      def policy_for(policy \\ %Janus.Policy{}, actor)

      def policy_for(policy, :can_read) do
        policy
        |> allow(:read, Thread)
        |> allow(:read, Post)
      end

      def policy_for(policy, :forbid_read) do
        policy
        |> allow(:read, Post)
        |> forbid(:read, Post)
      end

      def policy_for(policy, :override_forbid) do
        policy
        |> allow(:read, Post)
        |> forbid(:read, Post)
        |> always_allow(:read, Post)
      end
    end

    test ":can_read" do
      post = post_fixture()

      assert BasicGuestPolicy.allows?(:can_read, :read, post)
      assert BasicGuestPolicy.allows?(:can_read, :read, post.thread)
      assert BasicGuestPolicy.forbids?(:can_read, :update, post)
      assert BasicGuestPolicy.forbids?(:can_read, :read, post.author)
    end

    test ":forbid_read" do
      post = post_fixture()

      assert BasicGuestPolicy.forbids?(:forbid_read, :read, post)
    end

    test ":override_forbid" do
      post = post_fixture()

      assert BasicGuestPolicy.allows?(:override_forbid, :read, post)
    end
  end
end
