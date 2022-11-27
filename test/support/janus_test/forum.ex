defmodule JanusTest.Forum do
  import Ecto.Query

  alias JanusTest.Repo
  alias JanusTest.Schemas.{User, Post, Thread}

  def create_user(attrs \\ %{}) do
    %User{}
    |> User.changeset(Enum.into(attrs, %{}))
    |> Repo.insert()
  end

  def create_thread(creator, title, content) do
    thread_attrs = %{
      creator_id: creator.id,
      title: title,
      posts: [%{author_id: creator.id, content: content, index: 0}]
    }

    %Thread{}
    |> Thread.changeset(thread_attrs)
    |> Repo.insert()
  end

  def create_post(author, thread, content) do
    index =
      from(p in Post,
        where: [thread_id: ^thread.id],
        select: p.index,
        order_by: [desc: :index],
        limit: 1
      )
      |> Repo.one!()

    post_attrs = %{
      author_id: author.id,
      thread_id: thread.id,
      content: content,
      index: index + 1
    }

    %Post{}
    |> Post.changeset(post_attrs)
    |> Repo.insert()
  end
end
