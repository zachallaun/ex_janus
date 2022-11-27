defmodule JanusTest do
  use Janus.DataCase
  import JanusTest.Fixtures

  alias JanusTest.Schemas.{Thread, Post, User}, warn: false
  alias JanusTest.Repo

  describe "policy module" do
    defmodule ExamplePolicy do
      use Janus

      @impl true
      def policy_for(policy \\ %Janus.Policy{}, _) do
        policy
        |> allow(:read, Thread)
        |> forbid(:read, Thread)
        |> always_allow(:read, Thread)
      end
    end

    test "defines allows?/3" do
      thread = thread_fixture()
      assert ExamplePolicy.allows?(:user, :read, thread)
    end

    test "defines forbids?/3" do
      thread = thread_fixture()
      refute ExamplePolicy.forbids?(:user, :read, thread)
    end

    test "defines filter/3" do
      _ = [thread_fixture(), thread_fixture(), thread_fixture()]
      query = ExamplePolicy.filter(Thread, :read, :user)

      assert %Ecto.Query{} = query
      assert [_, _, _] = Repo.all(query)
    end
  end

  describe "blanket permissions" do
    import Janus.Policy

    test "should allow specified actions and forbid all others" do
      policy =
        %Janus.Policy{}
        |> allow(:read, Thread)
        |> allow(:read, Post)

      thread = thread_fixture()
      [post] = thread.posts

      assert Janus.allows?(policy, :read, thread)
      assert Janus.allows?(policy, :read, post)
      assert Janus.forbids?(policy, :other, thread)
      assert Janus.forbids?(policy, :read, thread.creator)
    end

    test "should be overriden by forbids" do
      policy =
        %Janus.Policy{}
        |> allow(:read, Thread)
        |> forbid(:read, Thread)

      thread = thread_fixture()

      assert Janus.forbids?(policy, :read, thread)
    end

    test "should override forbids with always_allow" do
      policy =
        %Janus.Policy{}
        |> allow(:read, Thread)
        |> forbid(:read, Thread)
        |> always_allow(:read, Thread)

      thread = thread_fixture()

      assert Janus.allows?(policy, :read, thread)
    end
  end
end
