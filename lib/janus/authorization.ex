defmodule Janus.Authorization do
  @moduledoc """
  Behaviour for using policy modules to authorize and load resources.

  Policy modules expose a minimal API that can be used to authorize and load resources
  throughout the rest of your application.

    * `c:authorize/4` - authorize an individual, already-loaded resource
    * `c:filter_authorized/4` - construct an `Ecto` query for a schema that will filter
      results to only those that are authorized
    * `c:any_authorized?/3` - checks whether the given actor/policy has _any_ access to
      the given schema for the given action

  Definitions for these callbacks are generally injected into your policy module that
  invoked `use Janus`.

  See the callback documentation for additional details and usage.
  """

  alias Janus.Policy

  @doc """
  Authorizes a loaded resource.

  Returns `{:ok, resource}` if authorized, otherwise `:error`.

  `c:authorize/4` can accept either an actor or a policy as its third argument. If an
  actor is passed, `c:policy_for/2` will be used to get the policy for that actor.

  ## Examples

      iex> MyPolicy.authorize(resource, :read, actor)
      {:ok, resource}

      iex> MyPolicy.authorize(resource, :read, policy)
      {:ok, resource}

      iex> MyPolicy.authorize(resource, :delete, actor)
      :error
  """
  @callback authorize(struct(), Janus.action(), Janus.actor() | Policy.t(), keyword()) ::
              {:ok, struct()} | :error

  @doc """
  Checks whether any permissions are defined for the given schema, action, and actor.

  `c:any_authorized?/3` can accept either an actor or a policy as its third argument. If
  an actor is passed, `c:policy_for/2` will be used to get the policy for that actor.

  This function is most useful in conjunction with `c:filter_authorized/4`, which builds
  an `Ecto` query that filters to only those resources the actor is authorized for. If
  you run the resulting query and receive `[]`, it is not possible to determine whether
  the result is empty because the actor wasn't authorized for _any_ resources or because
  of other restrictions on the query.

  For example, you might use the following pattern to load all the resources a user is
  allowed to read that were inserted in the last day:

      query = from(r in MyResource, where: r.inserted_at > from_now(-1, "day"))

      if any_authorized?(query, :read, user) do
        {:ok, filter_authorized(query, :read, user) |> Repo.all()}
      else
        :error
      end

  This would result in `{:ok, results}` if the user is authorized to read any resources,
  even if the result set is empty, and would result in `:error` if the user isn't
  authorized to read the resources at all.

  ## Examples

      iex> MyPolicy.any_authorized?(MyResource, :read, actor)
      true

      iex> MyPolicy.any_authorized?(MyResource, :delete, actor)
      false
  """
  @callback any_authorized?(Janus.schema(), Janus.action(), Janus.actor() | Policy.t()) ::
              boolean()

  @doc """
  Create an `%Ecto.Query{}` that results in only authorized records.

  `c:filter_authorized?/3` can accept either an actor or a policy as its third argument.
  If an actor is passed, `c:policy_for/2` will be used to get the policy for that actor.

  Like the `Ecto.Query` API, this function can accept a schema as the first argument or a
  query, in which case it will compose with that query. If a query is passed, the
  appropriate schema will be derived from that query's source.

      filter_authorized(MyResource, :read, user)

      query = from(r in MyResource, where: r.inserted_at > from_ago(1, "day"))
      filter_authorized(query, :read, user)

  If the query specifies the source as a string, we cannot derive the schema. For
  example, this will not work:

      # Raises an ArgumentError
      query = from(r in "my_resources", where: r.inserted_at > from_ago(1, "day"))
      filter_authorized(query, :read, user)

  ## Options

    * `:preload_authorized` - Similar to `Ecto.Query.preload/3`, but only preloads those
      associated records that are authorized. Note that this requires a database that
      supports lateral joins. See "Preloading authorized associations" for more
      information.

  ## Preloading authorized associations

  The `:preload_authorized` option can be used to preload associated records, but only
  those that are authorized for the given actor. An additional query can be specified
  for each preloaded association that will be run as if scoped to its parent row.

  This can simplify certain queries dramatically. For instance, imagine a user search
  interface that lists users along with their most recent comment. Naughty comments can
  be hidden by moderators, but those hidden comments should still be visible if a
  moderator is searching. Here's how that might be accomplished:

      iex> last_comment = from(Comment, order_by: [desc: :inserted_at], limit: 1)

      iex> User
      ...> |> search(search_params)
      ...> |> MyPolicy.filter_authorized(:read, current_user,
      ...>   preload_authorized: [comments: last_comment]
      ...> )
      ...> |> Repo.all()
      [%User{comments: [%Comment{}]}, %User{comments: [%Comment{}]}, ...]

  Some things to note about this example:

    * The `last_comment` query runs as if scoped to each user's comments. This means that
      the `:limit` applies to each user's comments, not the entire set of comments.
    * The comment will be the last inserted comment that is authorized to be read by the
      `current_user`. Moderators may be able to see hidden comments, while normal users
      may not.

  It is also possible to nest authorized preloads. For instance, you could preload
  comments and their associated post.

      MyPolicy.filter_authorized(User, :read, current_user,
        preload_authorized: [comments: :post]
      )

  This would load all comments. You could incorporate the `last_comment` query above by
  specifying it as the first element of a tuple, followed by the list of inner preloads:

      MyPolicy.filter_authorized(User, :read, current_user,
        preload_authorized: [comments: {last_comment, [:post]}]
      )

  This would load only the latest comment as well as its associated post (assuming it too
  is authorized to be read by `current_user`).

  ## Examples

      iex> MyPolicy.filter_authorized(MyResource, :read, actor)
      %Ecto.Query{}

      iex> MyPolicy.filter_authorized(MyResource, :read, actor) |> Repo.all()
      [%MyResource{}, ...]

      iex> MyResource
      ...> |> MyPolicy.filter_authorized(:read, actor)
      ...> |> order_by(inserted_at: :desc)
      ...> |> limit(1)
      ...> |> Repo.one()
      %MyResource{}

      iex> MyResource
      ...> |> MyPolicy.filter_authorized(:read, actor,
      ...>   preload_authorized: :other
      ...> )
      ...> |> Repo.all()
      [%MyResource{other: %OtherResource{}}, ...]
  """
  @callback filter_authorized(
              Ecto.Query.t() | Janus.schema(),
              Janus.action(),
              Janus.actor() | Policy.t(),
              keyword()
            ) :: Ecto.Query.t()
end
