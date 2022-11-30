{:ok, _} = Supervisor.start_link([JanusTest.Repo], strategy: :one_for_one)
Ecto.Adapters.SQL.Sandbox.mode(JanusTest.Repo, :manual)

defmodule Scratch.Policy do
  use Janus

  @impl true
  def policy_for(policy \\ %Janus.Policy{}, _) do
    policy
    |> allow(:read, JanusTest.User)
    |> allow(:read, JanusTest.Thread)
    |> allow(:read, JanusTest.Post)
  end
end

defmodule Scratch do
  import Ecto.Query, warn: false

  alias JanusTest.{Forum, Repo}
  alias JanusTest.Schemas.{User, Thread, Post}

  def run do
    :ok = Ecto.Adapters.SQL.Sandbox.checkout(Repo)

    # create 3 users and threads
    [{u1, t1}, {u2, t2}, {u3, t3}] =
      for i <- 1..3 do
        name = "user-#{i}"
        {:ok, u} = Forum.create_user(%{name: name})
        {:ok, t} = Forum.create_thread(u, "#{name} thread 1", "#{name} post 1/1")

        {u, t}
      end

    # create 4th user with no threads
    {:ok, u4} = Forum.create_user(%{name: "user-4"})

    # create 2 posts in t1 for u4
    Forum.create_post(u4, t1, "user-4 post 1/2")
    Forum.create_post(u4, t1, "user-4 post 1/3")

    # create 5th user
    {:ok, _} = Forum.create_user(%{name: "user-5"})

    # create extra post for u1
    Forum.create_post(u1, t2, "user-1 post 2/2")

    # create extra thread for u2
    Forum.create_thread(u2, "user-2 thread 2", "user-2 post 2/1")

    ecto_query()
    |> Repo.all()
    |> IO.inspect()
  end

  # def filter_query do
  #   most_recent_post =
  #     from(Post, order_by: [desc: :id], limit: 1)

  #   most_recent_thread =
  #     from(Thread, order_by: [desc: :id], limit: 1)

  #   first_post_in_thread =
  #     from(Post, order_by: [asc: :id], limit: 1)

  #   Scratch.Policy.filter(User, :read, :actor,
  #     preload_filtered: [
  #       posts: most_recent_post,
  #       threads: {most_recent_thread, posts: first_post_in_thread}
  #     ]
  #   )
  # end

  def ecto_query do
    most_recent_post =
      from(Post, order_by: [desc: :id], limit: 1)

    most_recent_thread =
      from(Thread, order_by: [desc: :id], limit: 1)

    first_post_in_thread =
      from(Post, order_by: [asc: :id], limit: 1)

    query =
      from(u in User, as: :u,
        # most recent post
        left_join: p in assoc(u, :posts), as: :posts,
        left_lateral_join: p_filtered in subquery(
          from(p2 in most_recent_post,
            where: p2.author_id == parent_as(:u).id,
            select: %{id: p2.id, lateral_selected: true}
          )
        ),
        on: p.id == p_filtered.id,
        where: is_nil(p.id) or p_filtered.lateral_selected,
        # most recent thread
        left_join: t in assoc(u, :threads), as: :threads,
        left_lateral_join: t_filtered in subquery(
          from(t2 in most_recent_thread,
            where: [creator_id: parent_as(:u).id],
            select: %{id: t2.id, lateral_selected: true}
          )
        ), as: :t_filtered,
        on: t.id == t_filtered.id,
        where: is_nil(t.id) or t_filtered.lateral_selected,
        # first post in most recent thread
        left_join: t_p in assoc(t, :posts), as: :thread_posts,
        left_lateral_join: t_p_filtered in subquery(
          from(p2 in first_post_in_thread,
            where: [thread_id: parent_as(:t_filtered).id],
            select: %{id: p2.id, lateral_selected: true},
          )
        ),
        on: t_p.id == t_p_filtered.id,
        where: is_nil(t_p.id) or t_p_filtered.lateral_selected
      )

    query
    |> preload([posts: p, threads: t, thread_posts: tp], [posts: p, threads: {t, posts: tp}])
  end
end

Scratch.run()
