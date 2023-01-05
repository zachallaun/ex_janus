defmodule Janus.AuthorizationTest do
  use Janus.DataCase
  import Ecto.Query

  import Janus.Policy
  alias Janus.Authorization, as: Auth

  describe "authorized/4" do
    test "should derive schema from query" do
      _ = [thread_fixture(), thread_fixture(), thread_fixture()]

      policy =
        %Janus.Policy{}
        |> allow(:read, Thread)

      query = from(Thread, limit: 1)

      assert [_] = query |> Auth.scope(:read, policy) |> Repo.all()

      query = from(subquery(query))

      assert [_] = query |> Auth.scope(:read, policy) |> Repo.all()
    end
  end

  describe "any_authorized?/3" do
    test "should check whether any permissions might authorize the action" do
      policy =
        %Janus.Policy{}
        |> allow(:read, Thread)

      assert Auth.any_authorized?(Thread, :read, policy)
      refute Auth.any_authorized?(Thread, :edit, policy)
      refute Auth.any_authorized?(Post, :read, policy)
    end

    test "should return false if a blanket deny exists" do
      policy =
        %Janus.Policy{}
        |> allow(:read, Thread)
        |> deny(:read, Thread)

      refute Auth.any_authorized?(Thread, :read, policy)

      policy =
        %Janus.Policy{}
        |> deny(:read, Thread)
        |> allow(:read, Thread)

      refute Auth.any_authorized?(Thread, :read, policy)
    end

    test "should return true if a deny is conditional on an unmatched attribute" do
      policy =
        %Janus.Policy{}
        |> allow(:read, Thread)
        |> deny(:read, Thread, where: [archived: true])

      assert Auth.any_authorized?(Thread, :read, policy)
    end

    test "should accept a query as first argument" do
      policy = %Janus.Policy{}
      query = order_by(Thread, desc: :inserted_at)

      refute Auth.any_authorized?(query, :read, policy)
    end
  end

  describe "blanket permissions" do
    test "should allow specified actions and deny all others" do
      policy =
        %Janus.Policy{}
        |> allow(:read, Thread)
        |> allow(:read, Post)

      thread = thread_fixture()
      [post] = thread.posts

      assert {:ok, ^thread} = Auth.authorize(thread, :read, policy)
      assert {:ok, ^post} = Auth.authorize(post, :read, policy)
      assert {:error, :not_authorized} = Auth.authorize(thread, :other, policy)
      assert {:error, :not_authorized} = Auth.authorize(thread.creator, :read, policy)
      assert [%Post{}] = Auth.scope(Post, :read, policy) |> Repo.all()
    end

    test "should override allow with deny" do
      policy =
        %Janus.Policy{}
        |> allow(:read, Thread)
        |> deny(:read, Thread)

      thread = thread_fixture()

      assert {:error, :not_authorized} = Auth.authorize(thread, :ready, policy)
      assert [] = Auth.scope(Post, :read, policy) |> Repo.all()
    end
  end

  describe "attribute permissions" do
    test "should allow action if :where attribute matches" do
      policy =
        %Janus.Policy{}
        |> allow(:read, Thread, where: [archived: false])

      unarchived = thread_fixture()
      archived = thread_fixture() |> Thread.changeset(%{archived: true}) |> Repo.update!()

      assert {:ok, ^unarchived} = Auth.authorize(unarchived, :read, policy)
      assert {:error, :not_authorized} = Auth.authorize(archived, :read, policy)
      assert [%Thread{} = thread] = Auth.scope(Thread, :read, policy) |> Repo.all()
      assert thread.id == unarchived.id
    end

    test "should allow action if :where_not attribute doesn't match" do
      policy =
        %Janus.Policy{}
        |> allow(:read, Thread, where_not: [archived: true])

      thread = thread_fixture()

      assert {:ok, ^thread} = Auth.authorize(thread, :read, policy)
      assert [%Thread{}] = Auth.scope(Thread, :read, policy) |> Repo.all()
    end

    test "should allow action if multiple :where attributes match" do
      build_policy = fn user ->
        %Janus.Policy{}
        |> allow(:edit, Thread, where: [archived: false, creator_id: user.id])
      end

      [user1, user2] = [user_fixture(), user_fixture()]
      [policy1, policy2] = [build_policy.(user1), build_policy.(user2)]

      thread = thread_fixture(%{creator_id: user1.id})

      assert {:ok, ^thread} = Auth.authorize(thread, :edit, policy1)
      assert {:error, :not_authorized} = Auth.authorize(thread, :edit, policy2)
      assert [%Thread{}] = Auth.scope(Thread, :edit, policy1) |> Repo.all()
      assert [] = Auth.scope(Thread, :edit, policy2) |> Repo.all()
    end

    test "should allow composition of :where and :where_not attributes" do
      [%{id: readable_id} = readable, unreadable] = [thread_fixture(), thread_fixture()]

      policy =
        %Janus.Policy{}
        |> allow(:read, Thread, where: [archived: false], where_not: [id: unreadable.id])

      assert {:ok, ^readable} = Auth.authorize(readable, :read, policy)
      assert {:error, :not_authorized} = Auth.authorize(unreadable, :read, policy)

      assert [%Thread{id: ^readable_id}] = Auth.scope(Thread, :read, policy) |> Repo.all()
    end

    test "should deny action if an allow is overriden" do
      policy =
        %Janus.Policy{}
        |> allow(:read, Thread)
        |> deny(:read, Thread, where: [archived: true])

      %{id: thread_id} = thread = thread_fixture()

      assert {:ok, ^thread} = Auth.authorize(thread, :read, policy)

      assert [%Thread{id: ^thread_id}] = Auth.scope(Thread, :read, policy) |> Repo.all()

      denied = thread_fixture(%{archived: true})

      assert {:error, :not_authorized} = Auth.authorize(denied, :read, policy)

      assert [%Thread{id: ^thread_id}] = Auth.scope(Thread, :read, policy) |> Repo.all()
    end

    test "should dump values to the correct underlying type" do
      policy =
        %Janus.Policy{}
        |> allow(:read, User, where: [status: :active])

      [%{id: u1_id} = u1, u2] = [user_fixture(), user_fixture()]
      {:ok, u2} = u2 |> User.changeset(%{status: :banned}) |> Repo.update()

      assert {:ok, ^u1} = Auth.authorize(u1, :read, policy)
      assert {:error, :not_authorized} = Auth.authorize(u2, :read, policy)
      assert [%User{id: ^u1_id}] = Auth.scope(User, :read, policy) |> Repo.all()
    end

    test "should allow comparisons to nil" do
      policy =
        %Janus.Policy{}
        |> allow(:read, Thread, where: [category: nil])

      %{id: allowed_id} = allowed = thread_fixture()
      not_allowed = thread_fixture(%{category: "anything"})

      assert {:ok, ^allowed} = Auth.authorize(allowed, :read, policy)
      assert {:error, :not_authorized} = Auth.authorize(not_allowed, :read, policy)

      assert [%Thread{id: ^allowed_id}] = Auth.scope(Thread, :read, policy) |> Repo.all()
    end

    test "should raise on filter if field value cannot be dumped to expected type" do
      policy =
        %Janus.Policy{}
        |> allow(:read, Thread, where: [archived: "foo"])

      message = ~r(could not dump "foo" to type :boolean)

      assert_raise ArgumentError, message, fn ->
        Auth.scope(Thread, :read, policy)
      end
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
                dynamic(not as(^binding).archived)
            end
          ]
        )

      [%{id: t1_id} = t1, t2] = [thread_fixture(), thread_fixture()]
      {:ok, t2} = t2 |> Thread.changeset(%{archived: true}) |> Repo.update()

      assert {:ok, ^t1} = Auth.authorize(t1, :read, policy)
      assert {:error, :not_authorized} = Auth.authorize(t2, :read, policy)
      assert [%Thread{id: ^t1_id}] = Auth.scope(Thread, :read, policy) |> Repo.all()
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
                  dynamic(not as(^binding).archived)
              end
            ]
          ]
        )

      [%{posts: [%{id: p1_id} = p1]}, %{posts: [p2]} = t2] = [thread_fixture(), thread_fixture()]
      {:ok, _} = t2 |> Thread.changeset(%{archived: true}) |> Repo.update()

      p1 = Repo.preload(p1, :thread)
      p2 = Repo.preload(p2, :thread)

      assert {:ok, ^p1} = Auth.authorize(p1, :read, policy)
      assert {:error, :not_authorized} = Auth.authorize(p2, :read, policy)
      assert [%Post{id: ^p1_id}] = Auth.scope(Post, :read, policy) |> Repo.all()
    end

    test "raise if incorrect arity is given" do
      policy =
        %Janus.Policy{}
        |> allow(:read, Thread, where: [archived: fn -> :boom end])

      thread = thread_fixture()

      message = ~r"permission functions must take 3 arguments"

      assert_raise ArgumentError, message, fn ->
        Auth.authorize(thread, :read, policy)
      end

      assert_raise ArgumentError, message, fn ->
        Auth.scope(Thread, :read, policy)
      end
    end
  end

  describe "association permissions" do
    test "should allow action if associated :where attribute matches" do
      policy =
        %Janus.Policy{}
        |> allow(:read, Post, where: [thread: [archived: false]])

      post = post_fixture()

      assert {:ok, ^post} = Auth.authorize(post, :read, policy)
      assert [_, _] = Auth.scope(Post, :read, policy) |> Repo.all()

      _ = post.thread |> Thread.changeset(%{archived: true}) |> Repo.update!()
      post = Repo.preload(post, :thread, force: true)

      assert {:error, :not_authorized} = Auth.authorize(post, :read, policy)
      assert [] = Auth.scope(Post, :read, policy) |> Repo.all()
    end

    test "should allow action if nested association :where attribute matches" do
      user = user_fixture()

      policy =
        %Janus.Policy{}
        |> allow(:edit, Post, where: [thread: [creator: [id: user.id]]])

      %{posts: [post]} = thread_fixture(%{creator_id: user.id})
      post = Repo.preload(post, thread: :creator)

      assert {:ok, ^post} = Auth.authorize(post, :edit, policy)
      assert [_] = Auth.scope(Post, :edit, policy) |> Repo.all()
    end

    test "raise if a required association is not loaded" do
      policy = allow(%Janus.Policy{}, :read, Thread, where: [creator: [id: 1]])

      thread = thread_fixture()
      thread = Ecto.reset_fields(thread, [:creator])

      assert_raise ArgumentError, ~r"field :creator must be preloaded", fn ->
        Auth.authorize(thread, :read, policy)
      end
    end

    test "load required associations if `:repo` and `:load_associations` are set" do
      user = user_fixture()
      thread = thread_fixture(%{creator_id: user.id})
      policy = allow(%Janus.Policy{}, :read, Thread, where: [creator: [id: user.id]])

      thread = Ecto.reset_fields(thread, [:creator])

      assert %{creator: %Ecto.Association.NotLoaded{}} = thread

      assert {:ok, thread} =
               Auth.authorize(thread, :read, policy, repo: Repo, load_associations: true)

      assert %{creator: %User{}} = thread
    end

    test "load required nested associations if `:repo` and `:load_associations` are set" do
      user = user_fixture()
      thread = thread_fixture(%{creator_id: user.id})
      post = post_fixture(%{thread_id: thread.id, author_id: user.id})

      policy =
        %Janus.Policy{}
        |> allow(:read, Post, where: [thread: [creator: [id: user.id]]])

      post = Ecto.reset_fields(post, [:thread])

      assert %{thread: %Ecto.Association.NotLoaded{}} = post

      assert {:ok, post} =
               Auth.authorize(post, :read, policy, repo: Repo, load_associations: true)

      assert %{thread: %Thread{creator: %User{}}} = post
    end

    test "should allow associations in subsequent clauses" do
      t1 = thread_fixture()
      %{id: t2_id} = t2 = thread_fixture()

      p1 =
        %Janus.Policy{}
        |> allow(:read, Thread,
          where: [archived: false],
          where_not: [creator: [id: t1.creator_id]]
        )

      assert {:error, :not_authorized} = Auth.authorize(t1, :read, p1)
      assert {:ok, ^t2} = Auth.authorize(t2, :read, p1)
      assert [%Thread{id: ^t2_id}] = Auth.scope(Thread, :read, p1) |> Repo.all()

      p2 =
        %Janus.Policy{}
        |> allow(:read, Thread,
          where: [archived: false],
          where_not: [creator: [id: t1.creator_id]],
          where_not: [creator: [id: t2.creator_id]]
        )

      assert {:error, :not_authorized} = Auth.authorize(t1, :read, p2)
      assert {:error, :not_authorized} = Auth.authorize(t2, :read, p2)
      assert [] = Auth.scope(Thread, :read, p2) |> Repo.all()
    end
  end

  describe ":preload_authorized" do
    setup do
      # Create 3 threads with 2 posts each. The third thread is archived.
      threads =
        for i <- 1..3 do
          t = thread_fixture(%{content: "t#{i} post", archived: i == 3})
          Forum.create_post(%{author_id: t.creator_id, thread_id: t.id, content: "post"})
          t
        end

      {:ok, threads: threads}
    end

    test "should only load authorized associations" do
      policy =
        %Janus.Policy{}
        |> allow(:read, Thread, where: [archived: false])
        |> allow(:read, Post, where: [archived: false])

      query =
        Post
        |> order_by(:id)
        |> Auth.scope(:read, policy, preload_authorized: :thread)

      assert [
               %Post{thread: %Thread{}},
               %Post{thread: %Thread{}},
               %Post{thread: %Thread{}},
               %Post{thread: %Thread{}},
               %Post{thread: nil},
               %Post{thread: nil}
             ] = query |> Repo.all()
    end

    test "shouldn't exclude records with empty preloads" do
      policy =
        %Janus.Policy{}
        |> allow(:read, User)

      query = Auth.scope(User, :read, policy, preload_authorized: :threads)

      assert [%User{threads: []}, %User{threads: []}, %User{threads: []}] = query |> Repo.all()
    end

    test "should load nested preloads" do
      policy =
        %Janus.Policy{}
        |> allow(:read, Thread, where: [archived: false])
        |> allow(:read, Post, where: [archived: false, thread: allows(:read)])

      query = Auth.scope(Post, :read, policy, preload_authorized: [thread: :posts])

      assert [
               %Post{thread: %Thread{posts: [%Post{}, %Post{}]}},
               %Post{thread: %Thread{posts: [%Post{}, %Post{}]}},
               %Post{thread: %Thread{posts: [%Post{}, %Post{}]}},
               %Post{thread: %Thread{posts: [%Post{}, %Post{}]}}
             ] = query |> Repo.all()
    end

    test ":preload_authorized should accept a query to filter preloads" do
      policy =
        %Janus.Policy{}
        |> allow(:read, Thread, where: [archived: false])
        |> allow(:read, Post, where: [archived: false, thread: allows(:read)])

      first_post_query = from(Post, order_by: :id, limit: 1)

      query = Auth.scope(Thread, :read, policy, preload_authorized: [posts: first_post_query])

      assert [
               %Thread{posts: [%Post{content: "t1 post"}]},
               %Thread{posts: [%Post{content: "t2 post"}]}
             ] = query |> Repo.all()
    end

    test ":preload_authorized should accept queries to filter nested preloads" do
      policy =
        %Janus.Policy{}
        |> allow(:read, User)
        |> allow(:read, Thread, where: [archived: false])
        |> allow(:read, Post, where: [archived: false, thread: allows(:read)])

      first_thread_query = from(Thread, order_by: :id, limit: 1)
      first_post_query = from(Post, order_by: :id, limit: 1)

      query =
        Auth.scope(User, :read, policy,
          preload_authorized: [threads: {first_thread_query, posts: first_post_query}]
        )
        |> order_by(:id)

      assert [
               %User{threads: [%Thread{posts: [%Post{content: "t1 post"}]}]},
               %User{threads: [%Thread{posts: [%Post{content: "t2 post"}]}]},
               %User{threads: []}
             ] = query |> Repo.all()
    end
  end

  describe "derived permissions" do
    test "allows/1 in allow/4" do
      policy =
        %Janus.Policy{}
        |> allow(:read, Thread, where: [archived: false])
        |> allow(:edit, Thread, where: allows(:read))

      thread = thread_fixture()

      assert {:ok, ^thread} = Auth.authorize(thread, :read, policy)
      assert {:ok, ^thread} = Auth.authorize(thread, :edit, policy)
      assert [%Thread{}] = Auth.scope(Thread, :edit, policy) |> Repo.all()

      thread = thread |> Thread.changeset(%{archived: true}) |> Repo.update!()

      assert {:error, :not_authorized} = Auth.authorize(thread, :read, policy)
      assert {:error, :not_authorized} = Auth.authorize(thread, :edit, policy)
      assert [] = Auth.scope(Thread, :edit, policy) |> Repo.all()
    end

    test "allows/1 in allow/4 with associations" do
      policy =
        %Janus.Policy{}
        |> allow(:read, Thread, where: [archived: false])
        |> allow(:read, Post, where: [thread: allows(:read)])

      post = post_fixture()

      assert {:ok, ^post} = Auth.authorize(post, :read, policy)
      assert [_, _] = Auth.scope(Post, :read, policy) |> Repo.all()
    end

    test "allows/1 in deny/4" do
      thread = thread_fixture()

      policy =
        %Janus.Policy{}
        |> allow(:read, Thread, where: [archived: false])
        |> allow(:edit, Thread, where: [creator_id: thread.creator_id])
        |> deny(:edit, Thread, where_not: allows(:read))

      assert {:ok, ^thread} = Auth.authorize(thread, :read, policy)
      assert {:ok, ^thread} = Auth.authorize(thread, :edit, policy)
      assert [%Thread{}] = Auth.scope(Thread, :edit, policy) |> Repo.all()

      thread = thread |> Thread.changeset(%{archived: true}) |> Repo.update!()

      assert {:error, :not_authorized} = Auth.authorize(thread, :read, policy)
      assert {:error, :not_authorized} = Auth.authorize(thread, :edit, policy)
      assert [] = Auth.scope(Thread, :edit, policy) |> Repo.all()
    end
  end

  describe "scope/4" do
    test "should derive the schema source from a query" do
      policy = %Janus.Policy{}

      assert %Ecto.Query{} = Auth.scope(Thread, :read, policy)
      assert %Ecto.Query{} = Auth.scope(from(Thread), :read, policy)
      assert %Ecto.Query{} = Auth.scope({from(Thread), Thread}, :read, policy)

      message = ~r"could not resolve query and schema"

      assert_raise ArgumentError, message, fn ->
        Auth.scope("threads", :read, policy)
      end

      assert_raise ArgumentError, message, fn ->
        Auth.scope(from("threads"), :read, policy)
      end
    end
  end

  describe "hooks" do
    test "should pass the object through" do
      thread = thread_fixture() |> Ecto.reset_fields([:creator])

      policy =
        %Janus.Policy{}
        |> allow(:read, Thread)
        |> attach_hook(:preload_creator, Thread, fn
          :authorize, thread, :read ->
            {:cont, Repo.preload(thread, :creator)}

          :scope, query, :read ->
            {:cont, from(query, select_merge: %{title: "foo"})}
        end)

      assert %Thread{creator: %Ecto.Association.NotLoaded{}} = thread
      assert {:ok, %Thread{creator: %User{}}} = Auth.authorize(thread, :read, policy)
      assert [%Thread{title: "foo"}] = Auth.scope(Thread, :read, policy) |> Repo.all()
    end

    test "should not authorize anything if :halt returned" do
      %{posts: [post]} = thread = thread_fixture()

      policy =
        %Janus.Policy{}
        |> allow(:read, Thread)
        |> allow(:read, Post)
        |> attach_hook(:do_halt, Thread, fn _, _, _ -> :halt end)

      assert {:error, :not_authorized} = Auth.authorize(thread, :read, policy)
      assert [] = Auth.scope(Thread, :read, policy) |> Repo.all()

      assert {:ok, %Post{}} = Auth.authorize(post, :read, policy)
      assert [%Post{}] = Auth.scope(Post, :read, policy) |> Repo.all()
    end

    test "raise on invalid return" do
      thread = thread_fixture()

      policy =
        %Janus.Policy{}
        |> allow(:read, Thread)
        |> attach_hook(:should_raise, fn _, _, _ -> :bad end)

      message = ~r"hook :should_raise returned an invalid result"

      assert_raise ArgumentError, message, fn ->
        Auth.authorize(thread, :read, policy)
      end

      assert_raise ArgumentError, message, fn ->
        Auth.scope(Thread, :read, policy)
      end
    end
  end
end
