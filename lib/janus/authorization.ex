defmodule Janus.Authorization do
  @moduledoc """
  Authorize and load resources using policies.

  Policy modules expose a minimal API that can be used to authorize and load resources
  throughout the rest of your application.

    * `authorize/4` - authorize an individual, already-loaded resource
    * `filter_authorized/4` - construct an `Ecto` query for a schema that will filter
      results to only those that are authorized
    * `any_authorized?/3` - checks whether the given actor/policy has _any_ access to
      the given schema for the given action

  These functions will usually be called from your policy module directly, since wrappers
  that accept either a policy or an actor are injected when you invoke `use Janus`.
  Documentation examples will show usage from your policy module.

  See individual function documentation for details.
  """

  alias Janus.Policy

  @type filterable :: Janus.schema_module() | Ecto.Query.t()

  @callback authorize(Ecto.Schema.t(), Janus.action(), Janus.actor() | Policy.t(), keyword()) ::
              {:ok, Ecto.Schema.t()} | :error

  @callback any_authorized?(filterable, Janus.action(), Janus.actor() | Policy.t()) ::
              boolean()

  @callback filter_authorized(filterable, Janus.action(), Janus.actor() | Policy.t(), keyword()) ::
              Ecto.Query.t()

  @doc """
  Checks whether any permissions are defined for the given schema, action, and actor.

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
  @spec any_authorized?(filterable, Janus.action(), Policy.t()) :: boolean()
  def any_authorized?(schema_or_query, action, policy) do
    {_query, schema} = Janus.Utils.resolve_query_and_schema!(schema_or_query)

    case Janus.Policy.rule_for(policy, action, schema) do
      %{allow: []} -> false
      _ -> true
    end
  end

  @doc """
  Create an `%Ecto.Query{}` that results in only authorized records.

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
  @spec filter_authorized(filterable, Janus.action(), Policy.t(), keyword()) :: Ecto.Query.t()
  def filter_authorized(query_or_schema, action, policy, opts \\ []) do
    Janus.Authorization.Filter.filter(query_or_schema, action, policy, opts)
  end

  @doc """
  Authorizes a loaded resource.

  Expects to receive a struct, an action, and an actor or policy.

  Returns `{:ok, resource}` if authorized, otherwise `:error`.

  ## Examples

      iex> MyPolicy.authorize(%MyResource{}, :read, actor) # accepts an actor
      {:ok, %MyResource{}}

      iex> MyPolicy.authorize(%MyResource{}, :read, policy) # or a policy
      {:ok, %MyResource{}}

      iex> MyPolicy.authorize(%MyResource{}, :delete, actor)
      :error
  """
  @spec authorize(Ecto.Schema.t(), Janus.action(), Policy.t(), keyword()) ::
          {:ok, Ecto.Schema.t()} | :error
  def authorize(%schema{} = resource, action, policy, _opts \\ []) do
    rule = Janus.Policy.rule_for(policy, action, schema)

    allow_if_any?(rule.allow, policy, resource)
    |> forbid_if_any?(rule.forbid, policy, resource)
    |> case do
      true -> {:ok, resource}
      false -> :error
    end
  end

  defp allow_if_any?(allowed? \\ false, conditions, policy, resource) do
    allowed? || Enum.any?(conditions, &condition_match?(&1, policy, resource))
  end

  defp forbid_if_any?(allowed?, conditions, policy, resource) do
    allowed? && !Enum.any?(conditions, &condition_match?(&1, policy, resource))
  end

  defp condition_match?([], _policy, _resource), do: true

  defp condition_match?(condition, policy, resource) when is_list(condition) do
    Enum.all?(condition, &condition_match?(&1, policy, resource))
  end

  defp condition_match?({:where, clause}, policy, resource) do
    clause_match?(clause, policy, resource)
  end

  defp condition_match?({:where_not, clause}, policy, resource) do
    !clause_match?(clause, policy, resource)
  end

  defp clause_match?(list, policy, resource) when is_list(list) do
    Enum.all?(list, &clause_match?(&1, policy, resource))
  end

  defp clause_match?({:__derived_allow__, action}, policy, resource) do
    case authorize(resource, action, policy) do
      {:ok, _} -> true
      :error -> false
    end
  end

  defp clause_match?({field, value}, policy, %schema{} = resource) do
    if field in schema.__schema__(:associations) do
      clause_match?(value, policy, fetch_associated!(resource, field))
    else
      compare_field(resource, field, value)
    end
  end

  defp compare_field(resource, field, fun) when is_function(fun, 3) do
    fun.(:boolean, resource, field)
  end

  defp compare_field(_resource, _field, fun) when is_function(fun) do
    raise ArgumentError, "permission functions must take 3 arguments (#{inspect(fun)})"
  end

  defp compare_field(resource, field, value) do
    Map.get(resource, field) == value
  end

  defp fetch_associated!(resource, field) do
    case Map.fetch!(resource, field) do
      %Ecto.Association.NotLoaded{} ->
        raise ArgumentError, "field #{inspect(field)} must be preloaded on #{inspect(resource)}"

      value ->
        value
    end
  end
end
