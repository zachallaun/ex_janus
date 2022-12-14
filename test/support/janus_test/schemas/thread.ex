defmodule JanusTest.Schemas.Thread do
  use Ecto.Schema
  import Ecto.Changeset

  alias JanusTest.Schemas.{Post, User}

  schema "threads" do
    field :title, :string
    field :category, :string
    field :archived, :boolean, default: false

    timestamps()

    belongs_to :creator, User
    has_many :posts, Post, on_delete: :delete_all
  end

  def changeset(post, attrs) do
    post
    |> cast(attrs, [:title, :category, :archived, :creator_id])
    |> validate_required([:title, :creator_id])
    |> cast_assoc(:posts, with: &Post.changeset/2)
  end
end
