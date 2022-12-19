defmodule JanusTest do
  use Janus.DataCase

  require Ecto.Query

  require Janus
  import Janus.Policy
  import JanusTest.Fixtures

  alias JanusTest.Schemas.{Thread, Post, User}, warn: false
  alias JanusTest.{Forum, Repo}

  describe "basic policy module" do
    defmodule ExamplePolicy do
      use Janus.Policy

      @impl true
      def policy_for(policy, _) do
        policy
        |> allow(:read, Thread)
      end
    end

    test "defines authorize/3" do
      thread = thread_fixture()
      assert {:ok, ^thread} = ExamplePolicy.authorize(thread, :read, :user)
    end

    test "defines any_authorized?/3" do
      assert ExamplePolicy.any_authorized?(Thread, :read, :user)
    end

    test "defines authorized/3 accepting a first-argument schema" do
      require ExamplePolicy
      _ = [thread_fixture(), thread_fixture(), thread_fixture()]
      query = ExamplePolicy.filter_authorized(Thread, :read, :user)

      assert %Ecto.Query{} = query
      assert [_, _, _] = Repo.all(query)
    end

    test "defines authorized/3 accepting a first-argument query" do
      require ExamplePolicy
      _ = [thread_fixture(), thread_fixture(), thread_fixture()]

      query =
        Thread
        |> Ecto.Query.limit(1)
        |> ExamplePolicy.filter_authorized(:read, :user)

      assert [_] = Repo.all(query)
    end

    test "defines __using__ and imports authorize and authorized" do
      use ExamplePolicy

      t = thread_fixture()

      assert {:ok, ^t} = authorize(t, :read, :user)
      assert [%Thread{}] = filter_authorized(Thread, :read, :user) |> Repo.all()
    end
  end

  describe "policy module with hooks" do
    defmodule ExamplePolicyWithHooks do
      use Janus.Policy

      before_policy_for :wrap_if_1
      before_policy_for :halt_if_2
      before_policy_for :shouldnt_run_after_halt_if_2
      before_policy_for :invalid_if_3

      @impl true
      def before_policy_for(hook, policy, actor)

      def before_policy_for(:wrap_if_1, policy, 1) do
        {:cont, policy, {:wrapped, 1}}
      end

      def before_policy_for(:wrap_if_1, policy, actor), do: {:cont, policy, actor}

      def before_policy_for(:halt_if_2, policy, 2) do
        {:halt, policy}
      end

      def before_policy_for(:halt_if_2, policy, actor), do: {:cont, policy, actor}

      def before_policy_for(:shouldnt_run_after_halt_if_2, policy, 2) do
        send(self(), :shouldnt_run_after_halt_if_2)
        {:cont, policy, 2}
      end

      def before_policy_for(:shouldnt_run_after_halt_if_2, policy, actor) do
        {:cont, policy, actor}
      end

      def before_policy_for(:invalid_if_3, _policy, 3) do
        :invalid
      end

      def before_policy_for(:invalid_if_3, policy, actor), do: {:cont, policy, actor}

      @impl true
      def policy_for(policy, actor) do
        send(self(), {:policy_for, policy, actor})
        policy
      end
    end

    test "should continue with modified policy/actor if :cont tuple returned" do
      assert %Janus.Policy{} = ExamplePolicyWithHooks.policy_for(1)
      assert_received {:policy_for, %Janus.Policy{}, {:wrapped, 1}}
    end

    test "shouldn't run later hooks or policy_for if :halt tuple returned" do
      assert %Janus.Policy{} = ExamplePolicyWithHooks.policy_for(2)
      refute_received :shouldnt_run_after_halt_if_2
      refute_received {:policy_for, _, _}
    end

    test "raises on invalid return from hook" do
      message = ~r"invalid return from hook `:invalid_if_3`"

      assert_raise(ArgumentError, message, fn ->
        ExamplePolicyWithHooks.policy_for(3)
      end)
    end
  end

  describe "authorized/4" do
    test "should derive schema from query" do
      _ = [thread_fixture(), thread_fixture(), thread_fixture()]

      policy =
        %Janus.Policy{}
        |> allow(:read, Thread)

      query = Ecto.Query.from(Thread, limit: 1)

      assert [_] = query |> Janus.filter_authorized(:read, policy) |> Repo.all()

      query = Ecto.Query.from(Ecto.Query.subquery(query))

      assert [_] = query |> Janus.filter_authorized(:read, policy) |> Repo.all()
    end
  end

  describe "any_authorized?/3" do
    test "should check whether any permissions might authorize the action" do
      policy =
        %Janus.Policy{}
        |> allow(:read, Thread)

      assert Janus.any_authorized?(Thread, :read, policy)
      refute Janus.any_authorized?(Thread, :edit, policy)
      refute Janus.any_authorized?(Post, :read, policy)
    end

    test "should return false if a blanket forbid exists" do
      policy =
        %Janus.Policy{}
        |> allow(:read, Thread)
        |> forbid(:read, Thread)

      refute Janus.any_authorized?(Thread, :read, policy)

      policy =
        %Janus.Policy{}
        |> forbid(:read, Thread)
        |> allow(:read, Thread)

      refute Janus.any_authorized?(Thread, :read, policy)
    end

    test "should return true if a forbid is conditional on attribute match" do
      policy =
        %Janus.Policy{}
        |> allow(:read, Thread)
        |> forbid(:read, Thread, where: [archived: true])

      assert Janus.any_authorized?(Thread, :read, policy)
    end

    test "should accept a query as first argument" do
      policy = %Janus.Policy{}
      query = Ecto.Query.order_by(Thread, desc: :inserted_at)

      refute Janus.any_authorized?(query, :read, policy)
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

      assert {:ok, ^thread} = Janus.authorize(thread, :read, policy)
      assert {:ok, ^post} = Janus.authorize(post, :read, policy)
      assert :error = Janus.authorize(thread, :other, policy)
      assert :error = Janus.authorize(thread.creator, :read, policy)
      assert [%Post{}] = Janus.filter_authorized(Post, :read, policy) |> Repo.all()
    end

    test "should override allow with forbid" do
      policy =
        %Janus.Policy{}
        |> allow(:read, Thread)
        |> forbid(:read, Thread)

      thread = thread_fixture()

      assert :error = Janus.authorize(thread, :ready, policy)
      assert [] = Janus.filter_authorized(Post, :read, policy) |> Repo.all()
    end
  end

  describe "attribute permissions" do
    test "should allow action if :where attribute matches" do
      policy =
        %Janus.Policy{}
        |> allow(:read, Thread, where: [archived: false])

      unarchived = thread_fixture()
      archived = thread_fixture() |> Thread.changeset(%{archived: true}) |> Repo.update!()

      assert {:ok, ^unarchived} = Janus.authorize(unarchived, :read, policy)
      assert :error = Janus.authorize(archived, :read, policy)
      assert [%Thread{} = thread] = Janus.filter_authorized(Thread, :read, policy) |> Repo.all()
      assert thread.id == unarchived.id
    end

    test "should allow action if :where_not attribute doesn't match" do
      policy =
        %Janus.Policy{}
        |> allow(:read, Thread, where_not: [archived: true])

      thread = thread_fixture()

      assert {:ok, ^thread} = Janus.authorize(thread, :read, policy)
      assert [%Thread{}] = Janus.filter_authorized(Thread, :read, policy) |> Repo.all()
    end

    test "should allow action if multiple :where attributes match" do
      policy_for = fn user ->
        %Janus.Policy{}
        |> allow(:edit, Thread, where: [archived: false, creator_id: user.id])
      end

      [user1, user2] = [user_fixture(), user_fixture()]
      [policy1, policy2] = [policy_for.(user1), policy_for.(user2)]

      thread = thread_fixture(%{creator_id: user1.id})

      assert {:ok, ^thread} = Janus.authorize(thread, :edit, policy1)
      assert :error = Janus.authorize(thread, :edit, policy2)
      assert [%Thread{}] = Janus.filter_authorized(Thread, :edit, policy1) |> Repo.all()
      assert [] = Janus.filter_authorized(Thread, :edit, policy2) |> Repo.all()
    end

    test "should allow composition of :where and :where_not attributes" do
      [%{id: readable_id} = readable, unreadable] = [thread_fixture(), thread_fixture()]

      policy =
        %Janus.Policy{}
        |> allow(:read, Thread, where: [archived: false], where_not: [id: unreadable.id])

      assert {:ok, ^readable} = Janus.authorize(readable, :read, policy)
      assert :error = Janus.authorize(unreadable, :read, policy)

      assert [%Thread{id: ^readable_id}] =
               Janus.filter_authorized(Thread, :read, policy) |> Repo.all()
    end

    test "should dump values to the correct underlying type" do
      policy =
        %Janus.Policy{}
        |> allow(:read, User, where: [status: :active])

      [%{id: u1_id} = u1, u2] = [user_fixture(), user_fixture()]
      {:ok, u2} = u2 |> User.changeset(%{status: :banned}) |> Repo.update()

      assert {:ok, ^u1} = Janus.authorize(u1, :read, policy)
      assert :error = Janus.authorize(u2, :read, policy)
      assert [%User{id: ^u1_id}] = Janus.filter_authorized(User, :read, policy) |> Repo.all()
    end

    test "should allow comparisons to nil" do
      policy =
        %Janus.Policy{}
        |> allow(:read, Thread, where: [category: nil])

      %{id: allowed_id} = allowed = thread_fixture()
      not_allowed = thread_fixture(%{category: "anything"})

      assert {:ok, ^allowed} = Janus.authorize(allowed, :read, policy)
      assert :error = Janus.authorize(not_allowed, :read, policy)

      assert [%Thread{id: ^allowed_id}] =
               Janus.filter_authorized(Thread, :read, policy) |> Repo.all()
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

      assert {:ok, ^t1} = Janus.authorize(t1, :read, policy)
      assert :error = Janus.authorize(t2, :read, policy)
      assert [%Thread{id: ^t1_id}] = Janus.filter_authorized(Thread, :read, policy) |> Repo.all()
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

      assert {:ok, ^p1} = Janus.authorize(p1, :read, policy)
      assert :error = Janus.authorize(p2, :read, policy)
      assert [%Post{id: ^p1_id}] = Janus.filter_authorized(Post, :read, policy) |> Repo.all()
    end
  end

  describe "association permissions" do
    test "should allow action if associated :where attribute matches" do
      policy =
        %Janus.Policy{}
        |> allow(:read, Post, where: [thread: [archived: false]])

      post = post_fixture()

      assert {:ok, ^post} = Janus.authorize(post, :read, policy)
      assert [_, _] = Janus.filter_authorized(Post, :read, policy) |> Repo.all()

      _ = post.thread |> Thread.changeset(%{archived: true}) |> Repo.update!()
      post = Repo.preload(post, :thread, force: true)

      assert :error = Janus.authorize(post, :read, policy)
      assert [] = Janus.filter_authorized(Post, :read, policy) |> Repo.all()
    end

    test "should allow action if nested association :where attribute matches" do
      user = user_fixture()

      policy =
        %Janus.Policy{}
        |> allow(:edit, Post, where: [thread: [creator: [id: user.id]]])

      %{posts: [post]} = thread_fixture(%{creator_id: user.id})
      post = Repo.preload(post, thread: :creator)

      assert {:ok, ^post} = Janus.authorize(post, :edit, policy)
      assert [_] = Janus.filter_authorized(Post, :edit, policy) |> Repo.all()
    end

    test ":preload_authorized should load authorizeded associations" do
      policy =
        %Janus.Policy{}
        |> allow(:read, Thread, where: [archived: false])
        |> allow(:read, Post, where: [archived: false])

      [_t1, _t2, t3] = for _ <- 1..3, do: thread_fixture()
      _ = t3 |> Thread.changeset(%{archived: true}) |> Repo.update!()

      query = Janus.filter_authorized(Post, :read, policy, preload_authorized: :thread)

      assert [%Post{thread: %Thread{}}, %Post{thread: %Thread{}}] = query |> Repo.all()
    end

    test ":preload_authorized should include records with empty associations" do
      policy =
        %Janus.Policy{}
        |> allow(:read, User)

      _ = user_fixture()

      query = Janus.filter_authorized(User, :read, policy, preload_authorized: :threads)

      assert [%User{}] = query |> Repo.all()
    end

    test ":preload_authorized should load nested associations" do
      policy =
        %Janus.Policy{}
        |> allow(:read, Thread, where: [archived: false])
        |> allow(:read, Post, where: [archived: false, thread: allows(:read)])

      [_t1, _t2, t3] = for _ <- 1..3, do: thread_fixture()
      _ = t3 |> Thread.changeset(%{archived: true}) |> Repo.update!()

      query = Janus.filter_authorized(Post, :read, policy, preload_authorized: [thread: :posts])

      assert [
               %Post{thread: %Thread{posts: [%Post{}]}},
               %Post{thread: %Thread{posts: [%Post{}]}}
             ] = query |> Repo.all()
    end

    test ":preload_authorized should accept queries to be applied to each nested assoc" do
      policy =
        %Janus.Policy{}
        |> allow(:read, Thread, where: [archived: false])
        |> allow(:read, Post, where: [archived: false, thread: allows(:read)])

      [t1, t2, t3] = for _ <- 1..3, do: thread_fixture()

      _ = t3 |> Thread.changeset(%{archived: true}) |> Repo.update!()

      {:ok, _} = Forum.create_post(%{author_id: t1.creator.id, thread_id: t1.id, content: "post"})
      {:ok, _} = Forum.create_post(%{author_id: t2.creator.id, thread_id: t2.id, content: "post"})

      {:ok, _} =
        Forum.create_post(%{
          author_id: t3.creator.id,
          thread_id: t3.id,
          content: "non-visible post"
        })

      first_post_query = Ecto.Query.from(Post, order_by: :id, limit: 1)

      query =
        Janus.filter_authorized(Thread, :read, policy,
          preload_authorized: [posts: first_post_query]
        )

      %{posts: [%{id: p1_id}]} = t1
      %{posts: [%{id: p2_id}]} = t2

      assert [
               %Thread{posts: [%{id: ^p1_id}]},
               %Thread{posts: [%{id: ^p2_id}]}
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

      assert {:ok, ^thread} = Janus.authorize(thread, :read, policy)
      assert {:ok, ^thread} = Janus.authorize(thread, :edit, policy)
      assert [%Thread{}] = Janus.filter_authorized(Thread, :edit, policy) |> Repo.all()

      thread = thread |> Thread.changeset(%{archived: true}) |> Repo.update!()

      assert :error = Janus.authorize(thread, :read, policy)
      assert :error = Janus.authorize(thread, :edit, policy)
      assert [] = Janus.filter_authorized(Thread, :edit, policy) |> Repo.all()
    end

    test "should allow action based on permission of an association" do
      policy =
        %Janus.Policy{}
        |> allow(:read, Thread, where: [archived: false])
        |> allow(:read, Post, where: [thread: allows(:read)])

      post = post_fixture()

      assert {:ok, ^post} = Janus.authorize(post, :read, policy)
      assert [_, _] = Janus.filter_authorized(Post, :read, policy) |> Repo.all()
    end
  end
end
