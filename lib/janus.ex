defmodule Janus do
  @moduledoc """
  Flexible and composable authorization for resources defined by an `Ecto.Schema`.

  Janus provides an API for defining authorization policies that can be used both as
  filters in Ecto queries and to authorize actions on loaded resources with minimal to no
  duplication of authorization logic.

  Janus is split into two primary components:

    * `Janus.Policy` - functions and behaviour for defining _policy modules_, which
      describe the allowed actors, actions, and resources in your application. This is
      where you look if you're writing a policy module.
    * `Janus.Authorization` - functions and behaviour used by the rest of your
      application to authorize and load resources. This is where you look if you're using
      a policy module.

  Janus defines a Mix task to generate the basic policy module that will get you started:

      $ mix janus.gen.policy

  ## Policies

  Policy modules are created by invoking `use Janus`, which implements both the
  `Janus.Policy` and `Janus.Authorization` behaviours:

      defmodule Policy do
        use Janus

        @impl true
        def policy_for(policy, _user) do
          policy
        end
      end

  When you invoke `use Janus`, default implementations are injected for required
  callbacks, except for `c:Janus.Policy.policy_for/2`. This callback is your foundation,
  as it returns the authorization policy for an individual user of your application.

  The policy above is not very useful -- it doesn't allow anyone to do anything -- but
  that can be changed by using the `Janus.Policy` API to define actions, resources, and
  conditions that make up your authorization rules.

      def policy_for(policy, %User{role: :moderator} = mod) do
        policy
        |> allow(:read, Post)
        |> allow([:edit, :archive, :unarchive], Post, where: [user: [role: :member]])
        |> allow([:edit, :archive, :unarchive], Post, where: [user_id: mod.id])
        |> forbid(:unarchive, Post, where: [archived_by: [role: :admin]])
      end

  See the `Janus.Policy` documentation for more on defining policies.

  ## Authorization

  With our policy module defined, it can now be used to load and authorize resources.

      iex> Policy.authorize(some_post, :archive, moderator)
      {:ok, some_post}

      iex> Policy.authorize(post_archived_by_admin, :unarchive, moderator)
      :error

      iex> Policy.filter_authorized(Post, :read, moderator)
      %Ecto.Query{}

      iex> Policy.filter_authorized(Post, :read, moderator) |> Repo.all()
      [ ... posts the moderator can read ]

      iex> Policy.any_authorized?(Post, :edit, moderator)
      true # there are rules allowing moderators to edit posts

      iex> Policy.any_authorized?(Post, :delete, moderator)
      false # there are no rules that allow moderators to delete posts

  These functions make up the `Janus.Authorization` behaviour, and their definitions
  were injected by default when we invoked `use Janus`. This is the "public API" that the
  rest of your application will use to authorize resources.

  See the `Janus.Authorization` documentation for more on authorization.

  ## Integration with `Ecto`

  The primary assumption that Janus makes is that your resources are backed by an
  `Ecto.Schema`. Using Ecto's schema reflection capabilities, Janus is able to use the
  same policy to authorize a single resource and to construct a composable Ecto query
  that is aware of field types and associations.

      # This query would result in the 5 latest posts that the current
      # user is authorized to see, preloaded with the user # who made
      # the post (but only if the current user is  allowed to see that
      # user).

      Post
      |> Policy.filter_authorized(:read, current_user,
        preload_authorized: :user
      )
      |> order_by(desc: :inserted_at)
      |> limit(5)

  This integration with Ecto queries is main reason Janus exists.
  """

  require Ecto.Query

  @type action :: any()
  @type schema :: atom()
  @type actor :: any()

  @doc """
  Sets up a module to implement the `Janus.Policy` and `Janus.Authorization` behaviours.

  Invoking `use Janus` does the following:

    * invokes `use Janus.Policy` which imports functions for defining policies and
      injects wrapper definitions for `policy_for/1` and `policy_for/2` that support
      hooks (see `Janus.Policy` for more)
    * injects implementations for the `Janus.Authorization` behaviour
    * injects an overridable `__using__/1` that other modules in your application can
      use to import just the `Janus.Authorization` API.

  ## Example

      defmodule MyApp.Policy do
        use Janus

        @impl true
        def policy_for(policy, _actor) do
          policy
        end
      end

      # imports `authorize`, `filter_authorized`, and `any_authorized?`
      use MyApp.Policy
  """
  defmacro __using__(_opts) do
    quote location: :keep do
      @behaviour Janus.Authorization

      use Janus.Policy
      require Janus

      unquote(default_using())

      @impl Janus.Authorization
      def authorize(resource, action, actor, opts \\ []) do
        Janus.authorize(resource, action, policy_for(actor), opts)
      end

      @impl Janus.Authorization
      def any_authorized?(schema, action, actor) do
        Janus.any_authorized?(schema, action, policy_for(actor))
      end

      @impl Janus.Authorization
      def filter_authorized(query_or_schema, action, actor, opts \\ []) do
        Janus.filter_authorized(query_or_schema, action, policy_for(actor), opts)
      end
    end
  end

  defp default_using do
    quote unquote: false do
      @doc false
      defmacro __using__(_opts) do
        quote do
          import unquote(__MODULE__),
            only: [
              authorize: 3,
              authorize: 4,
              any_authorized?: 3,
              filter_authorized: 3,
              filter_authorized: 4
            ]
        end
      end

      defoverridable __using__: 1
    end
  end

  @doc false
  def authorize(%schema{} = object, action, policy, _opts \\ []) do
    rule = Janus.Policy.rule_for(policy, action, schema)

    false
    |> allow_if_any?(rule.allow, policy, object)
    |> forbid_if_any?(rule.forbid, policy, object)
    |> case do
      true -> {:ok, object}
      false -> :error
    end
  end

  @doc false
  def any_authorized?(schema_or_query, action, policy) do
    {_query, schema} = Janus.Utils.resolve_query_and_schema!(schema_or_query)

    case Janus.Policy.rule_for(policy, action, schema) do
      %{allow: []} -> false
      _ -> true
    end
  end

  @doc false
  def filter_authorized(query_or_schema, action, policy, opts \\ []) do
    Janus.Filter.filter(query_or_schema, action, policy, opts)
  end

  defp allow_if_any?(true, _conditions, _policy, _object), do: true

  defp allow_if_any?(_, conditions, policy, object) do
    Enum.any?(conditions, &condition_match?(&1, policy, object))
  end

  defp forbid_if_any?(false, _conditions, _policy, _object), do: false

  defp forbid_if_any?(_, conditions, policy, object) do
    !Enum.any?(conditions, &condition_match?(&1, policy, object))
  end

  defp condition_match?([], _policy, _object), do: true

  defp condition_match?(condition, policy, object) when is_list(condition) do
    Enum.all?(condition, &condition_match?(&1, policy, object))
  end

  defp condition_match?({:where, clause}, policy, object) do
    clause_match?(clause, policy, object)
  end

  defp condition_match?({:where_not, clause}, policy, object) do
    !clause_match?(clause, policy, object)
  end

  defp clause_match?(list, policy, object) when is_list(list) do
    Enum.all?(list, &clause_match?(&1, policy, object))
  end

  defp clause_match?({:__janus_derived__, action}, policy, object) do
    case authorize(object, action, policy) do
      {:ok, _} -> true
      :error -> false
    end
  end

  defp clause_match?({field, value}, policy, %schema{} = object) do
    if field in schema.__schema__(:associations) do
      clause_match?(value, policy, fetch_associated!(object, field))
    else
      compare_field(object, field, value)
    end
  end

  defp compare_field(object, field, fun) when is_function(fun, 3) do
    fun.(:boolean, object, field)
  end

  defp compare_field(_object, _field, fun) when is_function(fun) do
    raise "permission functions must have arity 3 (#{inspect(fun)})"
  end

  defp compare_field(object, field, value) do
    Map.get(object, field) == value
  end

  defp fetch_associated!(object, field) do
    case Map.fetch!(object, field) do
      %Ecto.Association.NotLoaded{} ->
        raise "field #{inspect(field)} must be pre-loaded on #{inspect(object)}"

      value ->
        value
    end
  end
end
