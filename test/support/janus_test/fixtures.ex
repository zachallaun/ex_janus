defmodule JanusTest.Fixtures do
  alias JanusTest.Forum

  def user_fixture(attrs \\ %{}) do
    {:ok, user} =
      attrs
      |> Enum.into(%{name: rand_name()})
      |> Forum.create_user()

    user
  end

  def thread_fixture(creator \\ user_fixture(), title \\ rand_title(), content \\ rand_content()) do
    {:ok, thread} = Forum.create_thread(creator, title, content)
    thread
  end

  def post_fixture(
        author \\ user_fixture(),
        thread \\ thread_fixture(),
        content \\ rand_content()
      ) do
    {:ok, post} = Forum.create_post(author, thread, content)
    JanusTest.Repo.preload(post, [:thread, :author])
  end

  defp rand_string, do: Ecto.UUID.generate()
  defp rand_name, do: "Name #{rand_string()}"
  defp rand_title, do: "Title #{rand_string()}"
  defp rand_content, do: "Content #{rand_string()}"
end
