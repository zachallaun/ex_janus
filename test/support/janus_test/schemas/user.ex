defmodule JanusTest.Schemas.User do
  use Ecto.Schema
  import Ecto.Changeset

  alias JanusTest.Schemas.{Thread, Post}

  schema "users" do
    field :name, :string
    field :roles, :map, default: %{}
    field :status, Ecto.Enum, values: [:active, :banned], default: :active

    has_many :threads, Thread, foreign_key: :creator_id
    has_many :posts, Post, foreign_key: :author_id
  end

  def changeset(user, attrs) do
    user
    |> cast(attrs, [:roles, :name, :status])
  end
end
