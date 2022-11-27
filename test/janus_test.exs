defmodule JanusTest do
  use Janus.DataCase

  import Janus.Policy
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
      assert [%Post{}] = Janus.filter(Post, :read, policy) |> Repo.all()
    end

    test "should override allow with forbid" do
      policy =
        %Janus.Policy{}
        |> allow(:read, Thread)
        |> forbid(:read, Thread)

      thread = thread_fixture()

      assert Janus.forbids?(policy, :read, thread)
      assert [] = Janus.filter(Post, :read, policy) |> Repo.all()
    end

    test "should override forbid with always_allow" do
      policy =
        %Janus.Policy{}
        |> allow(:read, Thread)
        |> forbid(:read, Thread)
        |> always_allow(:read, Thread)

      thread = thread_fixture()

      assert Janus.allows?(policy, :read, thread)
      assert [%Thread{}] = Janus.filter(Thread, :read, policy) |> Repo.all()
    end
  end

  describe "permissions based on attribute" do
    test "should allow actions if :where attribute matches" do
      policy =
        %Janus.Policy{}
        |> allow(:read, Thread, where: [archived: false])

      unarchived = thread_fixture()
      archived = thread_fixture() |> Thread.changeset(%{archived: true}) |> Repo.update!()

      assert Janus.allows?(policy, :read, unarchived)
      assert Janus.forbids?(policy, :read, archived)
      assert [%Thread{} = thread] = Janus.filter(Thread, :read, policy) |> Repo.all()
      assert thread.id == unarchived.id
    end

    test "should allow actions if :where_not attribute doesn't match" do
      policy =
        %Janus.Policy{}
        |> allow(:read, Thread, where_not: [archived: true])

      thread = thread_fixture()

      assert Janus.allows?(policy, :read, thread)
      assert [%Thread{}] = Janus.filter(Thread, :read, policy) |> Repo.all()
    end

    test "should allow actions if multiple :where attributes match" do
      policy_for = fn user ->
        %Janus.Policy{}
        |> allow(:edit, Thread, where: [archived: false, creator_id: user.id])
      end

      [user1, user2] = [user_fixture(), user_fixture()]
      [policy1, policy2] = [policy_for.(user1), policy_for.(user2)]

      thread = thread_fixture(user1)

      assert Janus.allows?(policy1, :edit, thread)
      assert Janus.forbids?(policy2, :edit, thread)
      assert [%Thread{}] = Janus.filter(Thread, :edit, policy1) |> Repo.all()
      assert [] = Janus.filter(Thread, :edit, policy2) |> Repo.all()
    end

    test "should allow composition of :where and :where_not attributes" do
      [%{id: readable_id} = readable, unreadable] = [thread_fixture(), thread_fixture()]

      policy =
        %Janus.Policy{}
        |> allow(:read, Thread, where: [archived: false], where_not: [id: unreadable.id])

      assert Janus.allows?(policy, :read, readable)
      assert Janus.forbids?(policy, :read, unreadable)
      assert [%Thread{id: ^readable_id}] = Janus.filter(Thread, :read, policy) |> Repo.all()
    end
  end

  describe "derived permissions" do
    test "should allow actions based on other permissions" do
      policy =
        %Janus.Policy{}
        |> allow(:read, Thread, where: [archived: false])
        |> allow(:edit, Thread, where: allows(:read))

      thread = thread_fixture()

      assert Janus.allows?(policy, :read, thread)
      assert Janus.allows?(policy, :edit, thread)
      assert [%Thread{}] = Janus.filter(Thread, :edit, policy) |> Repo.all()

      thread = thread |> Thread.changeset(%{archived: true}) |> Repo.update!()

      assert Janus.forbids?(policy, :read, thread)
      assert Janus.forbids?(policy, :edit, thread)
      assert [] = Janus.filter(Thread, :edit, policy) |> Repo.all()
    end
  end
end
