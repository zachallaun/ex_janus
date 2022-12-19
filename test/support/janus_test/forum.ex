defmodule JanusTest.Forum do
  import Ecto.Query

  alias JanusTest.Repo
  alias JanusTest.Schemas.{User, Post, Thread}

  def create_user(attrs \\ %{}) do
    %User{}
    |> User.changeset(Enum.into(attrs, %{}))
    |> Repo.insert()
  end

  def create_thread(%{creator_id: id} = attrs) do
    {content, attrs} = Map.pop!(attrs, :content)
    attrs = Map.put(attrs, :posts, [%{author_id: id, content: content, index: 0}])

    %Thread{}
    |> Thread.changeset(attrs)
    |> Repo.insert()
  end

  def create_post(%{thread_id: id} = attrs) do
    index =
      from(p in Post,
        where: [thread_id: ^id],
        select: p.index,
        order_by: [desc: :index],
        limit: 1
      )
      |> Repo.one!()

    attrs = Map.put(attrs, :index, index + 1)

    %Post{}
    |> Post.changeset(attrs)
    |> Repo.insert()
  end
end
