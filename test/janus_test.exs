defmodule JanusTest do
  use Janus.DataCase

  require Ecto.Query

  require Janus
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

    test "defines filter/3 accepting a first-argument schema" do
      require ExamplePolicy
      _ = [thread_fixture(), thread_fixture(), thread_fixture()]
      query = ExamplePolicy.filter(Thread, :read, :user)

      assert %Ecto.Query{} = query
      assert [_, _, _] = Repo.all(query)
    end

    test "defines filter/3 accepting a first-argument query" do
      require ExamplePolicy
      _ = [thread_fixture(), thread_fixture(), thread_fixture()]

      query =
        Thread
        |> Ecto.Query.limit(1)
        |> ExamplePolicy.filter(:read, :user)

      assert [_] = Repo.all(query)
    end
  end

  describe "filter/4" do
    test "should derive schema from query" do
      _ = [thread_fixture(), thread_fixture(), thread_fixture()]

      policy =
        %Janus.Policy{}
        |> allow(:read, Thread)

      query = Ecto.Query.from(Thread, limit: 1)

      assert [_] = query |> Janus.filter(:read, policy) |> Repo.all()

      query = Ecto.Query.from(Ecto.Query.subquery(query))

      assert [_] = query |> Janus.filter(:read, policy) |> Repo.all()
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

  describe "attribute permissions" do
    test "should allow action if :where attribute matches" do
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

    test "should allow action if :where_not attribute doesn't match" do
      policy =
        %Janus.Policy{}
        |> allow(:read, Thread, where_not: [archived: true])

      thread = thread_fixture()

      assert Janus.allows?(policy, :read, thread)
      assert [%Thread{}] = Janus.filter(Thread, :read, policy) |> Repo.all()
    end

    test "should allow action if multiple :where attributes match" do
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

  describe "function permissions" do
    test "can be used for attribute comparison" do
      policy =
        %Janus.Policy{}
        |> allow(:read, Thread,
          where: [
            archived: fn
              :boolean, record, :archived ->
                !record.archived

              :dynamic, binding, :archived ->
                Ecto.Query.dynamic(not as(^binding).archived)
            end
          ]
        )

      [%{id: t1_id} = t1, t2] = [thread_fixture(), thread_fixture()]
      {:ok, t2} = t2 |> Thread.changeset(%{archived: true}) |> Repo.update()

      assert Janus.allows?(policy, :read, t1)
      assert Janus.forbids?(policy, :read, t2)
      assert [%Thread{id: ^t1_id}] = Janus.filter(Thread, :read, policy) |> Repo.all()
    end

    test "can be used for association attribute comparison" do
      policy =
        %Janus.Policy{}
        |> allow(:read, Post,
          where: [
            thread: [
              archived: fn
                :boolean, record, :archived ->
                  !record.archived

                :dynamic, binding, :archived ->
                  Ecto.Query.dynamic(not as(^binding).archived)
              end
            ]
          ]
        )

      [%{posts: [%{id: p1_id} = p1]}, %{posts: [p2]} = t2] = [thread_fixture(), thread_fixture()]
      {:ok, _} = t2 |> Thread.changeset(%{archived: true}) |> Repo.update()

      p1 = Repo.preload(p1, :thread)
      p2 = Repo.preload(p2, :thread)

      assert Janus.allows?(policy, :read, p1)
      assert Janus.forbids?(policy, :read, p2)
      assert [%Post{id: ^p1_id}] = Janus.filter(Post, :read, policy) |> Repo.all()
    end
  end

  describe "association permissions" do
    test "should allow action if associated :where attribute matches" do
      policy =
        %Janus.Policy{}
        |> allow(:read, Post, where: [thread: [archived: false]])

      post = post_fixture()

      assert Janus.allows?(policy, :read, post)
      assert [_, _] = Janus.filter(Post, :read, policy) |> Repo.all()

      _ = post.thread |> Thread.changeset(%{archived: true}) |> Repo.update!()
      post = Repo.preload(post, :thread, force: true)

      assert Janus.forbids?(policy, :read, post)
      assert [] = Janus.filter(Post, :read, policy) |> Repo.all()
    end

    test "should allow action if nested association :where attribute matches" do
      user = user_fixture()

      policy =
        %Janus.Policy{}
        |> allow(:edit, Post, where: [thread: [creator: [id: user.id]]])

      %{posts: [post]} = thread_fixture(user)
      post = Repo.preload(post, thread: :creator)

      assert Janus.allows?(policy, :edit, post)
      assert [_] = Janus.filter(Post, :edit, policy) |> Repo.all()
    end

    test ":preload_filtered should load filtered associations" do
      policy =
        %Janus.Policy{}
        |> allow(:read, Thread, where: [archived: false])
        |> allow(:read, Post, where: [archived: false])

      [_t1, _t2, t3] = for _ <- 1..3, do: thread_fixture()
      _ = t3 |> Thread.changeset(%{archived: true}) |> Repo.update!()

      query = Janus.filter(Post, :read, policy, preload_filtered: :thread)

      assert [%Post{thread: %Thread{}}, %Post{thread: %Thread{}}] = query |> Repo.all()
    end

    test ":preload_filtered should include records with empty associations" do
      policy =
        %Janus.Policy{}
        |> allow(:read, User)

      _ = user_fixture()

      query = Janus.filter(User, :read, policy, preload_filtered: :threads)

      assert [%User{}] = query |> Repo.all()
    end

    test ":preload_filtered should load nested associations" do
      policy =
        %Janus.Policy{}
        |> allow(:read, Thread, where: [archived: false])
        |> allow(:read, Post, where: [archived: false, thread: allows(:read)])

      [_t1, _t2, t3] = for _ <- 1..3, do: thread_fixture()
      _ = t3 |> Thread.changeset(%{archived: true}) |> Repo.update!()

      query = Janus.filter(Post, :read, policy, preload_filtered: [thread: :posts])

      assert [
               %Post{thread: %Thread{posts: [%Post{}]}},
               %Post{thread: %Thread{posts: [%Post{}]}}
             ] = query |> Repo.all()
    end
  end

  describe "derived permissions" do
    test "should allow action based on other permissions" do
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

    test "should allow action based on permission of an association" do
      policy =
        %Janus.Policy{}
        |> allow(:read, Thread, where: [archived: false])
        |> allow(:read, Post, where: [thread: allows(:read)])

      post = post_fixture()

      assert Janus.allows?(policy, :read, post)
      assert [_, _] = Janus.filter(Post, :read, policy) |> Repo.all()
    end
  end
end
