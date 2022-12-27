defmodule Janus.Authorization do
  @moduledoc """
  Authorize and load resources using policies.

  Policy modules expose a minimal API that can be used to authorize and load resources
  throughout the rest of your application.

    * `authorize/4` - authorize an individual, already-loaded resource
    * `scope/4` - construct an `Ecto` query for a schema that will filter
      results to only those that are authorized
    * `any_authorized?/3` - checks whether the given actor/policy has _any_ access to
      the given schema for the given action
    * `validate_authorized/4` - authorize an action on an `%Ecto.Changeset{}`, adding a
      validation error if not authorized

  These functions will usually be called from your policy module directly, since wrappers
  that accept either a policy or an actor are injected when you invoke `use Janus`.
  Documentation examples will show usage from your policy module.

  See individual function documentation for details.
  """

  alias Janus.Policy

  @type filterable :: Janus.schema_module() | Ecto.Query.t()

  @callback authorize(Ecto.Schema.t(), Janus.action(), Janus.actor() | Policy.t(), keyword()) ::
              {:ok, Ecto.Schema.t()} | {:error, :not_authorized}

  @callback any_authorized?(filterable, Janus.action(), Janus.actor() | Policy.t()) ::
              boolean()

  @callback scope(filterable, Janus.action(), Janus.actor() | Policy.t(), keyword()) ::
              Ecto.Query.t()

  @callback validate_authorized(
              Ecto.Changeset.t(Ecto.Schema.t()),
              Janus.action(),
              Janus.actor(),
              keyword()
            ) :: Ecto.Changeset.t(Ecto.Schema.t())

  @doc """
  Checks whether any permissions are defined for the given schema, action, and actor.

  This function is most useful in conjunction with `scope/4`, which builds
  an `Ecto` query that filters to only those resources the actor is authorized for. If
  you run the resulting query and receive `[]`, it is not possible to determine whether
  the result is empty because the actor wasn't authorized for _any_ resources or because
  of other restrictions on the query.

  For example, you might use the following pattern to load all the resources a user is
  allowed to read that were inserted in the last day:

      query = from(r in MyResource, where: r.inserted_at > from_now(-1, "day"))

      if any_authorized?(query, :read, user) do
        {:ok, scope(query, :read, user) |> Repo.all()}
      else
        {:error, :not_authorized}
      end

  This would result in `{:ok, results}` if the user is authorized to read any resources,
  even if the result set is empty, and would result in `{:error, :not_authorized}` if the
  user isn't authorized to read the resources at all.

  ## Examples

      iex> MyPolicy.any_authorized?(MyResource, :read, actor)
      true

      iex> MyPolicy.any_authorized?(MyResource, :delete, actor)
      false
  """
  @spec any_authorized?(filterable, Janus.action(), Policy.t()) :: boolean()
  def any_authorized?(schema_or_query, action, policy) do
    {_query, schema} = Janus.Utils.resolve_query_and_schema!(schema_or_query)

    case Policy.rule_for(policy, action, schema) do
      %{allow: []} -> false
      _ -> true
    end
  end

  @doc """
  Create an `%Ecto.Query{}` that results in only authorized records.

  Like the `Ecto.Query` API, this function can accept a schema as the first argument or a
  query, in which case it will compose with that query. If a query is passed, the
  appropriate schema will be derived from that query's source.

      scope(MyResource, :read, user)

      query = from(r in MyResource, where: r.inserted_at > from_ago(1, "day"))
      scope(query, :read, user)

  If the query specifies the source as a string, we cannot derive the schema. For
  example, this will not work:

      # Raises an ArgumentError
      query = from(r in "my_resources", where: r.inserted_at > from_ago(1, "day"))
      scope(query, :read, user)

  ## Options

    * `:preload_authorized` - Similar to `Ecto.Query.preload/3`, but only preloads those
      associated records that are authorized. Note that this requires Ecto v3.9.4 or
      later and a database that supports lateral joins. See "Preloading authorized
      associations" for more information.

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
      ...> |> MyPolicy.scope(:read, current_user,
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

      MyPolicy.scope(User, :read, current_user,
        preload_authorized: [comments: :post]
      )

  This would load all comments. You could incorporate the `last_comment` query above by
  specifying it as the first element of a tuple, followed by the list of inner preloads:

      MyPolicy.scope(User, :read, current_user,
        preload_authorized: [comments: {last_comment, [:post]}]
      )

  This would load only the latest comment as well as its associated post (assuming it too
  is authorized to be read by `current_user`).

  ## Examples

      iex> MyPolicy.scope(MyResource, :read, actor)
      %Ecto.Query{}

      iex> MyPolicy.scope(MyResource, :read, actor) |> Repo.all()
      [%MyResource{}, ...]

      iex> MyResource
      ...> |> MyPolicy.scope(:read, actor)
      ...> |> order_by(inserted_at: :desc)
      ...> |> limit(1)
      ...> |> Repo.one()
      %MyResource{}

      iex> MyResource
      ...> |> MyPolicy.scope(:read, actor,
      ...>   preload_authorized: :other
      ...> )
      ...> |> Repo.all()
      [%MyResource{other: %OtherResource{}}, ...]
  """
  @spec scope(filterable, Janus.action(), Policy.t(), keyword()) :: Ecto.Query.t()
  def scope(query_or_schema, action, policy, opts \\ []) do
    Janus.Authorization.Filter.filter(query_or_schema, action, policy, opts)
  end

  @doc """
  Authorizes a loaded resource.

  Expects to receive a struct, an action, and an actor or policy.

  Returns `{:ok, resource}` if authorized, otherwise `{:error, :not_authorized}`.

  ## Options

    * `:repo`
    * `:load_associations`

  ## Examples

      iex> MyPolicy.authorize(%MyResource{}, :read, actor) # accepts an actor
      {:ok, %MyResource{}}

      iex> MyPolicy.authorize(%MyResource{}, :read, policy) # or a policy
      {:ok, %MyResource{}}

      iex> MyPolicy.authorize(%MyResource{}, :delete, actor)
      {:error, :not_authorized}
  """
  @spec authorize(Ecto.Schema.t(), Janus.action(), Policy.t(), keyword()) ::
          {:ok, Ecto.Schema.t()} | {:error, :not_authorized}
  def authorize(%schema{} = resource, action, policy, opts \\ []) do
    opts = Keyword.validate!(opts, [:repo, :load_associations])
    policy = Policy.merge_config(policy, opts)
    rule = Policy.rule_for(policy, action, schema)

    with {:match, resource} <- run_rule(rule, :allow, resource, policy),
         {:no_match, resource} <- run_rule(rule, :deny, resource, policy) do
      {:ok, resource}
    else
      _ -> {:error, :not_authorized}
    end
  end

  defp run_rule(%Policy.Rule{} = rule, attr, resource, policy) do
    conditions = Map.fetch!(rule, attr)
    run_rule(conditions, resource, policy)
  end

  defp run_rule([condition | rest], resource, policy) do
    case condition_match(condition, resource, policy) do
      {:match, resource} -> {:match, resource}
      {:no_match, resource} -> run_rule(rest, resource, policy)
    end
  end

  defp run_rule([], resource, _policy), do: {:no_match, resource}

  defp condition_match([], resource, _policy), do: {:match, resource}

  defp condition_match([condition | rest], resource, policy) do
    case condition_match(condition, resource, policy) do
      {:match, resource} -> condition_match(rest, resource, policy)
      {:no_match, resource} -> {:no_match, resource}
    end
  end

  defp condition_match({:where, clause}, resource, policy) do
    clause_match(clause, resource, policy)
  end

  defp condition_match({:where_not, clause}, resource, policy) do
    case clause_match(clause, resource, policy) do
      {:match, resource} -> {:no_match, resource}
      {:no_match, resource} -> {:match, resource}
    end
  end

  defp condition_match({:or, condition, conditions}, resource, policy) do
    case condition_match(condition, resource, policy) do
      {:match, resource} -> {:match, resource}
      {:no_match, resource} -> condition_match(conditions, resource, policy)
    end
  end

  defp clause_match([clause | clauses], resource, policy) do
    case clause_match(clause, resource, policy) do
      {:match, resource} -> clause_match(clauses, resource, policy)
      {:no_match, resource} -> {:no_match, resource}
    end
  end

  defp clause_match([], resource, _policy), do: {:match, resource}

  defp clause_match({:__derived__, attr, action}, %schema{} = resource, policy) do
    policy
    |> Policy.rule_for(action, schema)
    |> run_rule(attr, resource, policy)
  end

  defp clause_match({field, value_or_assoc}, %schema{} = resource, policy) do
    cond do
      field in schema.__schema__(:associations) ->
        {match_or_no_match, assoc} =
          clause_match(value_or_assoc, fetch_associated!(resource, field, policy), policy)

        {match_or_no_match, Map.put(resource, field, assoc)}

      compare_field(resource, field, value_or_assoc) ->
        {:match, resource}

      true ->
        {:no_match, resource}
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

  defp fetch_associated!(resource, field, %{config: %{load_associations: true, repo: repo}})
       when not is_nil(repo) do
    resource = repo.preload(resource, field)
    Map.fetch!(resource, field)
  end

  defp fetch_associated!(resource, field, _policy) do
    case Map.fetch!(resource, field) do
      %Ecto.Association.NotLoaded{} ->
        raise ArgumentError, "field #{inspect(field)} must be preloaded on #{inspect(resource)}"

      value ->
        value
    end
  end

  @doc """
  Validates that the resource being changed is authorized both before and after applying
  changes.

  ## Options

    * `:error_key` - the key to which the error will be added if authorization fails,
      defaults to `:current_actor` or the `:validation_error_key` in your policy
      configuration (see `Janus` "Configuration" for more info)
    * `:pre_message` - the message in case the authorization check fails on the resource
      prior to applying changes, defaults to "is not authorized to change this resource"
    * `:post_message` - the message in case the authorization check fails on the resource
      after applying changes, defaults to "is not authorized to make these changes"

  ## Examples

      iex> %MyResource{}
      ...> |> MyResource.changeset(attrs)
      ...> |> MyPolicy.validate_authorized(:update, current_user)
      %Ecto.Changeset{}
  """
  @spec validate_authorized(
          Ecto.Changeset.t(Ecto.Schema.t()),
          Janus.action(),
          Policy.t(),
          keyword()
        ) ::
          Ecto.Changeset.t(Ecto.Schema.t())
  def validate_authorized(%Ecto.Changeset{} = changeset, action, policy, opts \\ []) do
    opts =
      Keyword.validate!(opts,
        error_key: :current_actor,
        pre_message: "is not authorized to change this resource",
        post_message: "is not authorized to make these changes"
      )

    with {:pre, {:ok, data}} <- {:pre, authorize(changeset.data, action, policy)},
         new_data <- Ecto.Changeset.apply_changes(changeset),
         {:post, {:ok, _data}} <- {:post, authorize(new_data, action, policy)} do
      %{changeset | data: data}
    else
      {:pre, {:error, :not_authorized}} ->
        Ecto.Changeset.add_error(changeset, opts[:error_key], opts[:pre_message], policy: policy)

      {:post, {:error, :not_authorized}} ->
        Ecto.Changeset.add_error(changeset, opts[:error_key], opts[:post_message], policy: policy)
    end
  end
end
