defmodule Janus.Policy do
  @moduledoc """
  Define composable authorization policies for actors in your system.

  A policy is a data structure created for an actor in your system that defines the
  schemas that actor can access, the actions they can take, and any restrictions to
  the set of resources that can be accessed. These policies are generally created
  implicitly for actors passed to functions defined by `Janus.Authorization`, but they
  can also be created (and cached) with `policy_for/2`.

  ## Policy modules

  While you can create a policy module with `use Janus.Policy`, you will usually invoke
  `use Janus` to create a module that implements both this and the `Janus.Authorization`
  behaviour:

      defmodule MyApp.Policy do
        use Janus

        @impl true
        def policy_for(policy, _user) do
          policy
        end
      end

  The `policy_for/2` callback is the only callback that is required in policy modules.

  ## Using `allow` and `deny`

  Permissions are primarily defined using `allow/4` and `deny/4`, which allows or
  denies an action on a resource if a set of conditions match. Both functions take the
  same arguments and options. When permissions are being checked, multiple `allow` rules
  combine using logical-or, with `deny` rules overriding `allow`.

  For example, the following policy would allow a moderator to edit their own comments
  and any comments flagged for review, but not those made by an admin.

      def policy_for(policy, %User{role: :moderator} = user) do
        policy
        |> allow(:edit, Comment, where: [user: [id: user.id]])
        |> allow(:edit, Comment, where: [flagged_for_review: true])
        |> deny(:edit, Comment, where: [user: [role: :admin]])
      end

  While set of keyword options passed to `allow` and `deny` are reminiscent of
  keyword-based Ecto queries, but since they are functions and not macros, there is no
  need to use the `^value` syntax used in Ecto. For example, the following would result
  in an error:

      allow(policy, :edit, Comment, where: [user: [id: ^user.id]])

  ### `:where` and `:where_not` conditions

  These conditions match if the associated fields are equal to each other. For instance,
  the moderation example above could also be written as:

      def policy_for(policy, %User{role: :moderator} = user) do
        policy
        |> allow(:edit, Comment, where: [user_id: user.id])
        |> allow(:edit, Comment,
          where: [flagged_for_review: true],
          where_not: [user: [role: :admin]]
        )
      end

  Multiple conditions within the same `allow`/`deny` are combined with a logical-and,
  so this might be translated to English as "allow moderators to edit comments they made
  or to edit comments flagged for review that were not made by an admin".

  ### `:or_where` conditions

  You can also use `:or_where` to combine with all previous conditions. For instance, the
  two examples above could also be written as:

      def policy_for(policy, %User{role: :moderator} = user) do
        policy
        |> allow(:edit, Comment,
          where: [flagged_for_review: true],
          where_not: [user: [role: :admin]],
          or_where: [user_id: user.id]
        )
      end

  An `:or_where` condition applies to all clauses before it. Using some pseudocode for
  demonstration, the above would read:

      # (flagged_for_review AND NOT user.role == :admin) OR user_id == user.id

  These clauses could be reordered to have a different meaning:

      policy
      |> allow(:edit, Comment,
        where: [flagged_for_review: true],
        or_where: [user_id: user.id],
        where_not: [user: [role: :admin]]
      )

      # (flagged_for_review OR user_id == user.id) AND NOT user.role == :admin

  ### Attribute checks with functions

  When equality is not a sufficient check for an attribute, a function can be supplied.

  For instance, a `published_at` field might be used to schedule posts. Users may only
  have permission to read posts where `published_at` is in the past, but we can only check
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

  ## `before_policy_for` hooks

  You can register hooks to be run prior to `c:policy_for/2` using `before_policy_for/1`.
  These hooks can be used to change the default (usually empty) policy or actor, or to
  prevent `c:policy_for/2` from being run altogether.

  See `before_policy_for/1` for more details.
  """

  alias __MODULE__
  alias __MODULE__.Rule

  @type t :: %Policy{
          rules: %{
            {Janus.schema_module(), Janus.action()} => Rule.t()
          }
        }

  defstruct rules: %{}

  @doc """
  Returns the policy for the given actor.

  This is the only callback that is required in a policy module.
  """
  @callback policy_for(t, Janus.actor()) :: t

  @janus_hooks :__janus_hooks__

  @doc false
  defmacro __using__(_opts) do
    quote location: :keep do
      @behaviour Janus.Policy
      @before_compile Janus.Policy
      Module.register_attribute(__MODULE__, unquote(@janus_hooks), accumulate: true)

      import Janus.Policy, except: [rule_for: 3]

      @doc """
      Returns the policy for the given actor.

      See `c:Janus.Policy.policy_for/2` for more information.
      """
      def policy_for(%Janus.Policy{} = policy), do: policy
      def policy_for(actor), do: policy_for(%Janus.Policy{}, actor)
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
          case Janus.Policy.run_hooks(unquote(hooks), policy, actor) do
            {:cont, policy, actor} -> super(policy, actor)
            {:halt, policy} -> policy
          end
        end
      end
    end
  end

  @doc false
  def run_hooks([hook | hooks], policy, actor) do
    case run_hook(hook, policy, actor) do
      {:cont, %Janus.Policy{} = policy, actor} -> run_hooks(hooks, policy, actor)
      {:halt, %Janus.Policy{} = policy} -> {:halt, policy}
      other -> bad_hook_result!(other, hook)
    end
  end

  def run_hooks([], policy, actor), do: {:cont, policy, actor}

  defp run_hook({module, hook}, policy, actor) when is_atom(module) do
    module.before_policy_for(hook, policy, actor)
  end

  defp run_hook(module, policy, actor) when is_atom(module) do
    module.before_policy_for(:default, policy, actor)
  end

  defp bad_hook_result!(result, hook) do
    raise ArgumentError, """
    invalid return from hook `#{inspect(hook)}`. Expected one of:

        {:cont, %Janus.Policy{}, actor}
        {:halt, %Janus.Policy{}}

    Got: #{inspect(result)}
    """
  end

  @doc """
  Registers a hook to be run prior to calling `c:policy_for/2`.

  `before_policy_for` hooks can be used to alter the default policy or actor that is
  being passed into `c:policy_for/2`. This could be used to preload required associations
  or fields, or to short-circuit the call entirely, immediately returning a policy
  without running it through `c:policy_for/2`.

  `before_policy_for` takes a module name or a tuple containing a module name and some
  term. The module is expected to define a function `before_policy_for/3`.

  The function will receive three arguments:

    * term (defaults to `:default`)
    * policy
    * actor

  and it must return one of:

    * `{:cont, policy, actor}` - run any further hooks and then `c:policy_for/2`
    * `{:halt, policy}` - skip any further hooks and `c:policy_for/2` and return `policy`

  ## Example

      defmodule Policy do
        use Janus

        before_policy_for __MODULE__
        before_policy_for {__MODULE__, :check_banned}

        def before_policy_for(:default, policy, user) do
          {:cont, policy, preload_required(user)}
        end

        def before_policy_for(:check_banned, policy, user) do
          if banned?(user) do
            {:halt, policy}
          else
            {:cont, policy, user}
          end
        end

        # ...
      end

  If desired, hooks can live in another module.

      defmodule Policy.Helpers do
        def before_policy_for(:check_banned, policy, user) do
          if User.banned?(user) do
            {:halt, policy}
          else
            {:cont, policy, user}
          end
        end
      end

      defmodule Policy do
        use Janus

        before_policy_for {Policy.Helpers, :check_banned}

        # ...
      end
  """
  defmacro before_policy_for(hook) do
    quote do
      Module.put_attribute(__MODULE__, unquote(@janus_hooks), unquote(hook))
    end
  end

  @doc """
  Allows an action on the schema if matched by conditions.

  See the section on "Using allow and deny" for a description of conditions.

  ## Examples

      policy
      |> allow(:read, FirstResource)
      |> allow(:create, SecondResource, where: [creator: [id: user.id]])
  """
  @spec allow(t, Janus.action() | [Janus.action()], Janus.schema_module(), keyword()) :: t
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
  Denies an action on the schema if matched by conditions.

  See the section on "Using allow and deny" for a description of conditions.

  ## Examples

      policy
      |> allow(:read, FirstResource)
      |> deny(:read, FirstResource, where: [scope: :private])
  """
  @spec deny(t, Janus.action(), Janus.schema_module(), keyword()) :: t
  def deny(policy, action, schema, opts \\ [])

  def deny(%Policy{} = policy, actions, schema, opts) when is_list(actions) do
    Enum.reduce(actions, policy, fn action, policy ->
      deny(policy, action, schema, opts)
    end)
  end

  def deny(%Policy{} = policy, action, schema, opts) do
    policy
    |> rule_for(action, schema)
    |> Rule.deny(opts)
    |> put_rule(policy)
  end

  @doc """
  Specifies that a condition should match if another action is allowed.

  If used as the value for an association, the condition will match if the action is
  allowed for the association.

  ## Example

  Allow users to edit any posts they can delete.

      policy
      |> allow(:delete, Post, where: [user_id: user.id])
      |> allow(:edit, Post, where: allows(:delete))

  ## Example with associations

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
  def allows(action), do: {:__derived__, :allow, action}

  @doc false
  @spec rule_for(t, Janus.action(), Janus.schema_module()) :: Rule.t()
  def rule_for(%Policy{rules: rules}, action, schema) do
    Map.get_lazy(rules, {schema, action}, fn ->
      Rule.new(schema, action)
    end)
  end

  defp put_rule(%Rule{schema: schema, action: action} = rule, policy) do
    update_in(policy.rules, &Map.put(&1, {schema, action}, rule))
  end
end
