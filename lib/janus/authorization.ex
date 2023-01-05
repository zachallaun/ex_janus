defmodule Janus.Authorization do
  @moduledoc """
  Authorize and load resources using policies.

  Policy modules expose a minimal API that can be used to authorize and
  load resources throughout the rest of your application.

    * `authorize/4` - authorize an individual, already-loaded resource

    * `scope/4` - construct an `Ecto` query for a schema that will
      filter results to only those that are authorized

    * `any_authorized?/3` - checks whether the given actor/policy has
      _any_ access to the given schema for the given action

  These functions will usually be called from your policy module
  directly, since wrappers that accept either a policy or an actor are
  injected when you invoke `use Janus`.  Documentation examples will
  show usage from your policy module.

  See individual function documentation for details.
  """

  alias __MODULE__.Filter

  alias Janus.Policy

  @type filterable :: Janus.schema_module() | Ecto.Query.t()

  @callback authorize(Ecto.Schema.t(), Janus.action(), Janus.actor() | Policy.t(), keyword()) ::
              {:ok, Ecto.Schema.t()} | {:error, :not_authorized}

  @callback any_authorized?(filterable, Janus.action(), Janus.actor() | Policy.t()) ::
              boolean()

  @callback scope(filterable, Janus.action(), Janus.actor() | Policy.t(), keyword()) ::
              Ecto.Query.t()

  @doc """
  Checks whether any permissions are defined for the given schema,
  action, and actor.

  This function is most useful in conjunction with `scope/4`, which
  builds an `Ecto` query that filters to only those resources the actor
  is authorized for. If you run the resulting query and receive `[]`, it
  is not possible to determine whether the result is empty because the
  actor wasn't authorized for _any_ resources or because of other
  restrictions on the query.

  For example, you might use the following pattern to load all the
  resources a user is allowed to read that were inserted in the last day:

      query = from(r in MyResource, where: r.inserted_at > from_now(-1, "day"))

      if any_authorized?(query, :read, user) do
        {:ok, scope(query, :read, user) |> Repo.all()}
      else
        {:error, :not_authorized}
      end

  This would result in `{:ok, results}` if the user is authorized to
  read any resources, even if the result set is empty, and would result
  in `{:error, :not_authorized}` if the user isn't authorized to read
  the resources at all.

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

  Like the `Ecto.Query` API, this function can accept a schema as the
  first argument or a query, in which case it will compose with that
  query. If a query is passed, the appropriate schema will be derived
  from that query's source.

      scope(MyResource, :read, user)

      query = from(r in MyResource, where: r.inserted_at > from_ago(1, "day"))
      scope(query, :read, user)

  If the query specifies the source as a string, we cannot derive the
  schema. For example, this will not work:

      # Raises an ArgumentError
      query = from(r in "my_resources", where: r.inserted_at > from_ago(1, "day"))
      scope(query, :read, user)

  ## Options

    * `:preload_authorized` - Similar to `Ecto.Query.preload/3`, but
    only preloads those associated records that are authorized. Note
    that this requires Ecto v3.9.4 or later and a database that supports
    lateral joins. See "Preloading authorized associations" for more
    information.

  ## Preloading authorized associations

  The `:preload_authorized` option can be used to preload associated
  records, but only those that are authorized for the given actor. An
  additional query can be specified for each preloaded association that
  will be run as if scoped to its parent row.

  This can simplify certain queries dramatically. For instance, imagine
  a user search interface that lists users along with their most recent
  comment. Naughty comments can be hidden by moderators, but those
  hidden comments should still be visible if a moderator is searching.
  Here's how that might be accomplished:

      iex> last_comment = from(Comment, order_by: [desc: :inserted_at], limit: 1)

      iex> User
      ...> |> search(search_params)
      ...> |> MyPolicy.scope(:read, current_user,
      ...>   preload_authorized: [comments: last_comment]
      ...> )
      ...> |> Repo.all()
      [%User{comments: [%Comment{}]}, %User{comments: [%Comment{}]}, ...]

  Some things to note about this example:

    * The `last_comment` query runs as if scoped to each user's
      comments. This means that the `:limit` applies to each user's
      comments, not the entire set of comments.

    * The comment will be the last inserted comment that is authorized
      to be read by the `current_user`. Moderators may be able to see
      hidden comments, while normal users may not.

  It is also possible to nest authorized preloads. For instance, you
  could preload comments and their associated post.

      MyPolicy.scope(User, :read, current_user,
        preload_authorized: [comments: :post]
      )

  This would load all comments. You could incorporate the `last_comment`
  query above by specifying it as the first element of a tuple, followed
  by the list of inner preloads:

      MyPolicy.scope(User, :read, current_user,
        preload_authorized: [comments: {last_comment, [:post]}]
      )

  This would load only the latest comment as well as its associated post
  (assuming it too is authorized to be read by `current_user`).

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
    case Policy.run_hooks(:scope, query_or_schema, action, policy) do
      {:cont, query_or_schema} ->
        Filter.filter(query_or_schema, action, policy, opts)

      :halt ->
        Filter.filter(query_or_schema, action, %Janus.Policy{}, opts)
    end
  end

  @doc """
  Authorizes a loaded resource.

  Expects to receive a struct, an action, and an actor or policy.

  Returns `{:ok, resource}` if authorized, otherwise `{:error, :not_authorized}`.

  ## Options

    * `:load_associations` - Whether to load associations required by
      policy authorization rules, defaults to `false` unless configured
      on your policy module

    * `:repo` - Ecto repository to use when loading required
      associations if `:load_associations` is set to `true`, defaults to
      `nil` unless configured on your policy module

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

    case Policy.run_hooks(:authorize, resource, action, policy) do
      {:cont, resource} ->
        with {:ok, resource} <- run_rule(rule, :allow, resource, policy),
             {:error, resource} <- run_rule(rule, :deny, resource, policy) do
          {:ok, resource}
        else
          _ -> {:error, :not_authorized}
        end

      :halt ->
        {:error, :not_authorized}
    end
  end

  # Conditions vs. Clauses
  #
  # When creating a policy, every call to `allow`/`deny` creates a
  # condition, and each `:where`, `:where_not`, etc. inside represents a
  # clause in that condition.
  #
  # So if we consider the following:
  #
  #     policy
  #     |> allow(:read, Thing, where: [some_field: :foo], where_not: [other_field: :bar])
  #     |> allow(:read, Thing, where: [some_field: :baz])
  #
  # This policy defines two conditions for reading Thing -- if one of
  # them matches, it allows reading. For a condition to match, all of
  # its clauses must match. The first `allow` has two clauses and the
  # second has only one.
  #
  defp run_rule(%Policy.Rule{} = rule, attr, resource, policy) do
    conditions = Map.fetch!(rule, attr)
    run_rule(conditions, resource, policy)
  end

  defp run_rule([condition | rest], resource, policy) do
    case condition_match(condition, resource, policy) do
      {:ok, resource} -> {:ok, resource}
      {:error, resource} -> run_rule(rest, resource, policy)
    end
  end

  defp run_rule([], resource, _policy), do: {:error, resource}

  defp condition_match([], resource, _policy), do: {:ok, resource}

  defp condition_match([condition | rest], resource, policy) do
    case condition_match(condition, resource, policy) do
      {:ok, resource} -> condition_match(rest, resource, policy)
      {:error, resource} -> {:error, resource}
    end
  end

  defp condition_match({:where, clause}, resource, policy) do
    clause_match(clause, resource, policy)
  end

  defp condition_match({:where_not, clause}, resource, policy) do
    case clause_match(clause, resource, policy) do
      {:ok, resource} -> {:error, resource}
      {:error, resource} -> {:ok, resource}
    end
  end

  defp condition_match({:or, condition, conditions}, resource, policy) do
    case condition_match(condition, resource, policy) do
      {:ok, resource} -> {:ok, resource}
      {:error, resource} -> condition_match(conditions, resource, policy)
    end
  end

  defp clause_match([clause | clauses], resource, policy) do
    case clause_match(clause, resource, policy) do
      {:ok, resource} -> clause_match(clauses, resource, policy)
      {:error, resource} -> {:error, resource}
    end
  end

  defp clause_match([], resource, _policy), do: {:ok, resource}

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

      field_match?(resource, field, value_or_assoc) ->
        {:ok, resource}

      true ->
        {:error, resource}
    end
  end

  defp field_match?(resource, field, fun) when is_function(fun, 3) do
    fun.(:boolean, resource, field)
  end

  defp field_match?(_resource, _field, fun) when is_function(fun) do
    raise ArgumentError, "permission functions must take 3 arguments (#{inspect(fun)})"
  end

  defp field_match?(resource, field, value) do
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
end
