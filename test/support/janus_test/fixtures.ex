defmodule JanusTest.Fixtures do
  alias JanusTest.{Forum, Repo}

  def user_fixture(attrs \\ %{}) do
    {:ok, user} =
      attrs
      |> Enum.into(%{name: rand_name()})
      |> Forum.create_user()

    user
  end

  def thread_fixture(attrs \\ %{}) do
    attrs =
      attrs
      |> Map.put_new_lazy(:creator_id, fn -> Map.fetch!(user_fixture(), :id) end)
      |> Map.put_new_lazy(:title, &rand_title/0)
      |> Map.put_new_lazy(:content, &rand_content/0)

    {:ok, thread} = Forum.create_thread(attrs)
    Repo.preload(thread, :creator)
  end

  def post_fixture(attrs \\ %{}) do
    attrs =
      attrs
      |> Map.put_new_lazy(:thread_id, fn -> Map.fetch!(thread_fixture(), :id) end)
      |> Map.put_new_lazy(:author_id, fn -> Map.fetch!(user_fixture(), :id) end)
      |> Map.put_new_lazy(:content, &rand_content/0)

    {:ok, post} = Forum.create_post(attrs)
    Repo.preload(post, [:thread, :author])
  end

  defp rand_name, do: "Name #{rand_string()}"
  defp rand_title, do: "Title #{rand_string()}"
  defp rand_content, do: "Content #{rand_string()}"
  defp rand_string, do: Ecto.UUID.generate()
end
