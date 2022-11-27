defmodule JanusTest.Schemas.Post do
  use Ecto.Schema
  import Ecto.Changeset

  alias JanusTest.Schemas.{Thread, User}

  schema "posts" do
    field :content, :string
    field :index, :integer
    field :archived, :boolean, default: false
    timestamps()

    belongs_to :author, User
    belongs_to :thread, Thread
  end

  def changeset(post, attrs) do
    post
    |> cast(attrs, [:content, :index, :archived, :author_id, :thread_id])
    |> validate_required([:content, :index, :author_id])
  end
end
