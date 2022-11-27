defmodule JanusTest.Schemas.User do
  use Ecto.Schema
  import Ecto.Changeset

  schema "users" do
    field :roles, :map, default: %{}
    field :name, :string
  end

  def changeset(user, attrs) do
    user
    |> cast(attrs, [:roles, :name])
  end
end
