defmodule Janus.Policy do
  @moduledoc """
  Define composable authorization policies for actors in your system.

  Policy modules are created by invoking `use Janus.Policy` and are responsible for
  defining policies for the actors in your system as well as the API that the rest of
  your application may use to enforce those policies.

  A policy is a data structure created for an actor in your system that defines the
  schemas that actor can access, the actions they can take, and any restrictions to
  the set of resources that can be accessed. These policies can be created explicitly by
  calling `policy_for/2`, but they are also created implicitly by any function that
  accepts an actor as an argument, e.g. `authorize/2`, `filter_authorized/4`, etc.

  ## Defining policies

  You can create a policy module yourself that invokes `use Janus.Policy`, or generate
  one to start by running `mix janus.gen.policy`. You will end up with something similar
  to this:

      defmodule MyApp.Policy do
        use Janus.Policy

        @impl true
        def policy_for(policy, _user) do
          policy
        end
      end

  The `policy_for/2` callback is the only callback that is required in policy modules.

  ### `allow` and `forbid`

  Permissions are primarily defined using `allow/4` and `forbid/4`, which allows or
  forbids an action on a resource if a set of conditions match. Both functions take the
  same arguments and options. When permissions are being checked, multiple `allow` rules
  combine using logical-or, with `forbid` rules overriding `allow`.

  For example, the following policy would allow a moderator to edit their own comments
  and any comments flagged for review, but not those made by an admin.

      def policy_for(policy, %User{role: :moderator} = user) do
        policy
        |> allow(:edit, Comment, where: [user: [id: user.id]])
        |> allow(:edit, Comment, where: [flagged_for_review: true])
        |> forbid(:edit, Comment, where: [user: [role: :admin]])
      end

  While set of keyword options passed to `allow` and `forbid` are reminiscent of
  keyword-based Ecto queries, but since they are functions and not macros, there is no
  need to use the `^value` syntax used in Ecto. For example, the following would result
  in an error:

      allow(policy, :edit, Comment, where: [user: [id: ^user.id]])

  #### `:where` and `:where_not` conditions

  These conditions match if the associated fields are equal to each other. For instance,
  the moderation example above could also be represented as:

      def policy_for(policy, %User{role: :moderator} = user) do
        policy
        |> allow(:edit, Comment, where: [user: [id: user.id]])
        |> allow(:edit, Comment,
          where: [flagged_for_review: true],
          where_not: [user: [role: :admin]]
        )
      end

  Multiple conditions within the same `allow`/`forbid` are combined with a logical-and,
  so this might be translated to English as "allow moderators to edit comments they made
  or to edit comments flagged for review that were not made by an admin".

  #### Using function "escape-hatches"

  In some cases, simple equality is not sufficient to represent a permission. For
  instance, a `published_at` field might be used to schedule posts. Users may only have
  permission to read posts where `published_at` is in the past, but we can only check
  for equality using the basic keyword syntax presented above. In these cases, you can
  defer this check using an arity-3 function:

      def policy_for(policy, user) do
        policy
        |> allow(:read, Post, where: [published_at: &in_the_past?/3])
      end

      def in_the_past?(:boolean, record, :published_at) do
        if value = Map.get(record, :published_at) do
          DateTime.compare(DateTime.utc_now(), value) == :gt
        end
      end

      def in_the_past?(:dynamic, binding, :published_at) do
        now = DateTime.utc_now()
        Ecto.Query.dynamic(^now > as(^binding).published_at)
      end

  As seen in the example above, functions must define at least two clauses based on their
  first argument, `:boolean` or `:dynamic`, so that they can handle both operations on
  a single record and operations that should compose with an Ecto query.

  ## Using policies

  Policy modules expose a minimal API that can be used to authorize and load authorized
  resources throughout the rest of your application.

    * `c:authorize/4` - authorize an individual, already-loaded resource
    * `c:filter_authorized/4` - construct an `Ecto` query for a schema that will filter
      results to only those that are authorized
    * `c:any_authorized?/3` - checks whether the given actor/policy has _any_ access to
      the given schema for the given action

  See the documentation for each callback above for additional details.

  ## How policy rules combine

  Since policy rules are used to authorize an action on an individual resource and for
  data loading, it's best to consider how the rules apply to a set of resources, then the
  case of a single resource can be thought of as a set containing only that resource.

  The conceptual algorithm in terms of set operations:

  0. Let resources be the set of objects we're starting from.
  1. Filter resources to those matched by any `allow` rule.
  2. Take the difference of 1. and resources matched by any `forbid` rule.
  """

  alias __MODULE__
  alias __MODULE__.Rule

  @type t :: %Policy{
          rules: %{
            {Janus.schema(), Janus.action()} => Rule.t()
          }
        }

  defstruct rules: %{}

  @doc """
  Returns the policy for the given actor.

  This is the only callback that is required in a policy module.
  """
  @callback policy_for(t, Janus.actor()) :: t

  @doc """
  Invoked prior to `c:policy_for/2` and may update the default policy and actor or halt.

  See `before_policy_for/1` for more info.
  """
  @callback before_policy_for(any(), t, Janus.actor()) ::
              {:cont, t, Janus.actor()} | {:halt, t, Janus.actor()}

  @doc """
  Authorizes a loaded resource.

  Returns `{:ok, resource}` if authorized, otherwise `:error`.
  """
  @callback authorize(struct(), Janus.action(), Janus.actor() | t, keyword()) ::
              {:ok, struct()} | :error

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
  """
  @callback any_authorized?(Janus.schema(), Janus.action(), Janus.actor() | t) :: boolean()

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
      associated records that are authorized.
  """
  @callback filter_authorized(
              Ecto.Query.t() | Janus.schema(),
              Janus.action(),
              Janus.actor(),
              keyword()
            ) :: Ecto.Query.t()

  @optional_callbacks before_policy_for: 3

  @janus_hooks :__janus_hooks__

  @doc false
  defmacro __using__(_opts) do
    quote location: :keep do
      @behaviour Janus.Policy
      @before_compile Janus.Policy
      Module.register_attribute(__MODULE__, unquote(@janus_hooks), accumulate: true)

      require Janus
      import Janus.Policy, except: [rule_for: 3]

      unquote(default_using())

      @doc "Returns the policy for the given actor."
      def policy_for(%Janus.Policy{} = policy), do: policy
      def policy_for(actor), do: policy_for(%Janus.Policy{}, actor)

      @impl true
      def authorize(object, action, actor, opts \\ []) do
        Janus.authorize(object, action, policy_for(actor), opts)
      end

      @impl true
      def any_authorized?(schema, action, actor) do
        Janus.any_authorized?(schema, action, policy_for(actor))
      end

      @impl true
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
          require unquote(__MODULE__)

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
  defmacro __before_compile__(env) do
    hooks =
      env.module
      |> Module.get_attribute(@janus_hooks)
      |> Enum.reverse()

    if hooks != [] do
      quote location: :keep do
        defoverridable policy_for: 2

        def policy_for(policy, actor) do
          case Janus.Policy.run_hooks(unquote(hooks), policy, actor, __MODULE__) do
            {:cont, policy, actor} -> super(policy, actor)
            {:halt, policy} -> policy
          end
        end
      end
    end
  end

  @doc false
  def run_hooks([hook | hooks], policy, actor, module) do
    case module.before_policy_for(hook, policy, actor) do
      {:cont, %Janus.Policy{} = policy, actor} -> run_hooks(hooks, policy, actor, module)
      {:halt, %Janus.Policy{} = policy} -> {:halt, policy}
      other -> bad_hook_result!(other, hook)
    end
  end

  def run_hooks([], policy, actor, _module), do: {:cont, policy, actor}

  defp bad_hook_result!(result, hook) do
    raise ArgumentError, """
    invalid return from hook `#{inspect(hook)}`. Expected one of:

        {:cont, %Janus.Policy{}, actor}
        {:halt, %Janus.Policy{}}

    Got: #{inspect(result)}
    """
  end

  @doc """
  Registers a hook to be run prior to calling `policy_for/2`.
  """
  defmacro before_policy_for(hook) do
    quote do
      Module.put_attribute(__MODULE__, unquote(@janus_hooks), unquote(hook))
    end
  end

  @doc """
  Allows an action on the schema if matched by opts.

  ## Examples

      policy
      |> allow(:read, FirstResource)
      |> allow(:create, SecondResource, where: [creator: [id: user.id]])
  """
  @spec allow(t, Janus.action() | [Janus.action()], Janus.schema(), keyword()) :: t
  def allow(policy, action, schema, opts \\ [])

  def allow(%Policy{} = policy, actions, schema, opts) when is_list(actions) do
    Enum.reduce(actions, policy, fn action, policy ->
      allow(policy, action, schema, opts)
    end)
  end

  def allow(%Policy{} = policy, action, schema, opts) do
    policy
    |> rule_for(action, schema)
    |> Rule.allow(opts)
    |> put_rule(policy)
  end

  @doc """
  Forbids an action on the schema if matched by opts.

  ## Examples

      policy
      |> allow(:read, FirstResource)
      |> forbid(:read, FirstResource, where: [scope: :private])
  """
  @spec forbid(t, Janus.action(), Janus.schema(), keyword()) :: t
  def forbid(policy, action, schema, opts \\ [])

  def forbid(%Policy{} = policy, actions, schema, opts) when is_list(actions) do
    Enum.reduce(actions, policy, fn action, policy ->
      forbid(policy, action, schema, opts)
    end)
  end

  def forbid(%Policy{} = policy, action, schema, opts) do
    policy
    |> rule_for(action, schema)
    |> Rule.forbid(opts)
    |> put_rule(policy)
  end

  @doc """
  Specifies that an association should match if the association's schema is authorized.

  This allows authorization to be "delegated" to an association.

  ## Example

  Let's say we have some posts with comments. Posts are visible unless they are archived,
  and all comments of visible posts are also visible. To start, we can duplicate the
  condition:

      policy
      |> allow(:read, Post, where: [archived: false])
      |> allow(:read, Comment, where: [post: [archived: false]])

  If we add additional clauses to the condition for posts, however, we will have to
  duplicate them for comments. We can use `allows` instead:

      policy
      |> allow(:read, Post, where: [archived: false])
      |> allow(:read, Comment, where: [post: allows(:read)])

  Now let's say we add a feature that allows for draft posts, which should not be visible
  unless a `published_at` is set. We can modify only the condition for `Post` and that
  change will propogate to comments.

      policy
      |> allow(:read, Post, where: [archived: false], where_not: [published_at: nil])
      |> allow(:read, Comment, where: [post: allows(:read)])
  """
  @spec allows(Janus.action()) :: tuple()
  def allows(action), do: {:__janus_derived__, action}

  @doc false
  @spec rule_for(t, Janus.action(), Janus.schema()) :: Rule.t()
  def rule_for(%Policy{rules: rules}, action, schema) do
    Map.get_lazy(rules, {schema, action}, fn ->
      Rule.new(schema, action)
    end)
  end

  defp put_rule(%Rule{schema: schema, action: action} = rule, policy) do
    update_in(policy.rules, &Map.put(&1, {schema, action}, rule))
  end
end
