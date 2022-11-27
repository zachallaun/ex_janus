defmodule JanusTest.Repo.Migrations.AddForumTables do
  use Ecto.Migration

  def change do
    create table("users") do
      add :name, :string
      add :roles, :map
    end

    create table("threads") do
      add :title, :string
      add :archived, :boolean
      add :creator_id, references("users")

      timestamps()
    end

    create table("posts") do
      add :content, :string
      add :index, :integer
      add :archived, :boolean
      add :author_id, references("users")
      add :thread_id, references("threads")

      timestamps()
    end
  end
end
