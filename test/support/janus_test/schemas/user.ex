defmodule JanusTest.Schemas.User do
  use Ecto.Schema
  import Ecto.Changeset

  schema "users" do
    field :name, :string
    field :roles, :map, default: %{}
  end

  def changeset(user, attrs) do
    user
    |> cast(attrs, [:roles, :name])
  end
end
