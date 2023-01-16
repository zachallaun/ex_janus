defmodule Janus.Policy do
  @moduledoc """
  Define composable authorization policies for actors in your system.

  A policy is a data structure created for an actor in your system that
  defines the schemas that actor can access, the actions they can take,
  and any restrictions to the set of resources that can be accessed.
  These policies are generally created implicitly for actors passed to
  functions defined by `Janus.Authorization`, but they can also be
  created with `c:build_policy/2`.

  ## Creating a policy modules

  While you can create a policy module with `use Janus.Policy`, you will
  usually invoke `use Janus` and implement `c:build_policy/2`:

      defmodule MyApp.Policy do
        use Janus

        @impl true
        def build_policy(policy, _actor) do
          policy
        end
      end

  An implementation for `c:build_policy/1` is injected into the policy
  module.

  Policy modules can now be used to generate policy structs explicitly
  (though they will usually be created implicitly when calling functions
  defined by `Janus.Authorization`).

      iex> policy = MyApp.Policy.build_policy(:my_user)
      %Janus.Policy{actor: :my_user, rules: %{...}}

      iex> MyApp.SecondaryPolicy.build_policy(policy)
      %Janus.Policy{actor: :my_user, rules: %{...}}

  ## Permissions with `allow` and `deny`

  Permissions are primarily defined using `allow/4` and `deny/4`, which
  allows or denies an action on a resource if a set of conditions match.
  Both functions take the same arguments and options. When permissions
  are being checked, multiple `allow` rules combine using logical-or,
  with `deny` rules overriding `allow`.

  For example, the following policy would allow a moderator to edit
  their own comments and any comments flagged for review, but not those
  made by an admin.

      @impl true
      def build_policy(policy, %User{role: :moderator} = user) do
        policy
        |> allow(Comment, :update, where: [user: [id: user.id]])
        |> allow(Comment, :update, where: [flagged_for_review: true])
        |> deny(Comment, :update, where: [user: [role: :admin]])
      end

  While set of keyword options passed to `allow` and `deny` are
  reminiscent of keyword-based Ecto queries, but since they are
  functions and not macros, there is no need to use the `^value` syntax
  used in Ecto. For example, the following would result in an error:

      allow(policy, Comment, :update, where: [user: [id: ^user.id]])

  ### `:where` and `:where_not` conditions

  These conditions match if the associated fields are equal to each
  other. For instance, the moderation example above could also be
  written as:

      @impl true
      def build_policy(policy, %User{role: :moderator} = user) do
        policy
        |> allow(Comment, :update, where: [user_id: user.id])
        |> allow(Comment, :update,
          where: [flagged_for_review: true],
          where_not: [user: [role: :admin]]
        )
      end

  Multiple conditions within the same `allow`/`deny` are combined with a
  logical-and, so this might be translated to English as "allow
  moderators to edit comments they made or to edit comments flagged for
  review that were not made by an admin".

  ### `:or_where` conditions

  You can also use `:or_where` to combine with all previous conditions.
  For instance, the two examples above could also be written as:

      @impl true
      def build_policy(policy, %User{role: :moderator} = user) do
        policy
        |> allow(Comment, :update,
          where: [flagged_for_review: true],
          where_not: [user: [role: :admin]],
          or_where: [user_id: user.id]
        )
      end

  An `:or_where` condition applies to all clauses before it. Using some
  pseudocode for demonstration, the above would read:

      # (flagged_for_review AND NOT user.role == :admin) OR user_id == user.id

  These clauses could be reordered to have a different meaning:

      policy
      |> allow(Comment, :update,
        where: [flagged_for_review: true],
        or_where: [user_id: user.id],
        where_not: [user: [role: :admin]]
      )

      # (flagged_for_review OR user_id == user.id) AND NOT user.role == :admin

  ### Attribute checks with functions

  When equality is not a sufficient check for an attribute, a function
  can be supplied.

  For instance, a `published_at` field might be used to schedule posts.
  Users may only have permission to read posts where `published_at` is
  in the past, but we can only check for equality using the basic
  keyword syntax presented above. In these cases, you can defer this
  check using an arity-3 function:

      @impl true
      def build_policy(policy, _actor) do
        policy
        |> allow(Comment, :read, where: [published_at: &in_the_past?/3])
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

  As seen in the example above, functions must define at least two
  clauses based on their first argument, `:boolean` or `:dynamic`, so
  that they can handle both operations on a single record and operations
  that should compose with an Ecto query.

  ## Working with rulesets

  Policies can also be defined by attaching rulesets created using
  `allow/3` and `deny/3`. Instead of taking a policy as a first argument,
  these functions take a schema (or a ruleset).

  Rulesets are specific to an individual schema and can be attached to
  a policy using `attach/2`. For example:

      @impl true
      def build_policy(policy, actor) do
        policy
        |> attach(rules_for(Thread, actor))
        |> attach(rules_for(Post, actor))
      end

      defp rules_for(Thread, %User{id: user_id}) do
        Thread
        |> allow(:read, where: [archived: false])
        |> allow([:create, :update], where: [creator_id: user_id])
      end

      defp rules_for(Thread, nil) do
        Thread
        |> allow(:read, where: [archived: false, visibility: :public])
      end

      defp rules_for(Post, _actor) do
        Post
        |> allow(:read, where: [thread: allows(:read)])
      end

  Depending on your specific needs, rulesets may allow you to organize
  policies in a way that is easier to maintain. In the above example,
  delegating to a private `rules_for/2` function that returns a ruleset
  allows us to pattern-match on a `nil` user where it matters and share
  a ruleset where it doesn't.

  This pattern has tradeoffs, however. You would need to ensure that the
  pattern-matching for each schema is exhaustive, for instance, otherwise
  a `FunctionClauseError` might be raised.

  ## Hooks

  Functions can be registered as hooks that run prior to authorization
  calls. See `attach_hook/4` for more information.
  """

  alias __MODULE__
  alias __MODULE__.Rule

  alias Janus.Authorization

  @config :__janus_policy_config__

  @config_defaults [
    repo: nil,
    load_associations: false
  ]

  defstruct [:actor, config: %{}, rules: %{}, hooks: %{}]

  @type t :: %Policy{
          actor: Janus.actor(),
          config: map(),
          rules: %{
            {Janus.schema_module(), Janus.action()} => Rule.t()
          },
          hooks: %{
            optional(Janus.schema_module() | :all) => keyword(hook)
          }
        }

  @type ruleset :: %{schema: Janus.schema_module(), rules: %{Janus.action() => Rule.t()}}

  @type hook ::
          (Ecto.Schema.t() | Authorization.filterable(), Janus.action(), t ->
             {:cont, Ecto.Schema.t() | Authorization.filterable()} | :halt)

  @doc """
  Builds an authorization policy, delegating to `c:build_policy/2`.

  If given a policy, calls `c:build_policy/2` with the policy and the
  actor associated with the policy. If given an actor, creates an empty
  policy associated with that actor and passes it to `c:build_policy/2`.

  An implementation for this callback is injected into modules invoking
  either `use Janus` or `use Janus.Policy`.
  """
  @callback build_policy(t | Janus.actor()) :: t

  @doc """
  Builds an authorization policy containing rules for the given actor.

  See `Janus.Policy` for API documentation on building policies.
  """
  @callback build_policy(t, Janus.actor()) :: t

  @doc false
  defmacro __using__(opts \\ []) do
    quote location: :keep do
      @behaviour Janus.Policy
      Module.register_attribute(__MODULE__, unquote(@config), persist: true)
      Module.put_attribute(__MODULE__, unquote(@config), unquote(opts))

      import Janus.Policy, except: [rule_for: 3, run_hooks: 4]

      @impl true
      def build_policy(%Janus.Policy{actor: actor} = policy) do
        build_policy(policy, actor)
      end

      def build_policy(actor) do
        policy = Janus.Policy.new(__MODULE__, actor)
        build_policy(policy, actor)
      end
    end
  end

  @doc false
  def new(module, actor) do
    config =
      module.__info__(:attributes)
      |> Keyword.get(@config, [])
      |> Keyword.validate!(@config_defaults)
      |> Enum.into(%{})

    %Janus.Policy{actor: actor, config: config}
  end

  @doc false
  def merge_config(%Policy{} = policy, []), do: policy

  def merge_config(%Policy{} = policy, config) do
    config =
      config
      |> Keyword.new()
      |> Keyword.validate!(Keyword.keys(@config_defaults))
      |> Enum.into(policy.config || %{})

    %{policy | config: config}
  end

  @doc """
  Allows an action on the schema if matched by conditions.

  See "Permissions with `allow` and `deny`" for a description of conditions.

  ## Examples

      policy
      |> allow(FirstResource, :read)
      |> allow(SecondResource, :create, where: [creator: [id: user.id]])
  """
  @spec allow(t, Janus.schema_module(), Janus.action() | [Janus.action()], keyword()) :: t
  def allow(%Policy{} = policy, schema, actions, opts) when is_list(actions) do
    Enum.reduce(actions, policy, fn action, policy ->
      allow(policy, schema, action, opts)
    end)
  end

  def allow(%Policy{} = policy, schema, action, opts) do
    validate_schema!(schema)

    policy
    |> rule_for(action, schema)
    |> Rule.allow(opts)
    |> put_rule(policy)
  end

  @doc false
  def allow(%Policy{} = policy, schema, action) do
    allow(policy, schema, action, [])
  end

  @doc """
  Creates or updates a ruleset for a schema to allow an action if matched
  by conditions.

  Must be attached to a policy using `attach/2`.

  See "Permissions with `allow` and `deny`" for a description of conditions.

  ## Examples

      thread_rules =
        Thread
        |> allow(:read)
        |> allow(:create, where: [creator_id: user.id])

      attach(policy, thread_rules)
  """
  @spec allow(Janus.schema_module() | ruleset, Janus.action() | [Janus.action()], keyword()) ::
          ruleset
  def allow(schema_or_ruleset, actions, opts) when is_list(actions) do
    Enum.reduce(actions, schema_or_ruleset, fn action, schema_or_ruleset ->
      allow(schema_or_ruleset, action, opts)
    end)
  end

  def allow(%{schema: schema} = ruleset, action, opts) do
    ruleset
    |> rule_for(action, schema)
    |> Rule.allow(opts)
    |> put_rule(ruleset)
  end

  def allow(schema, action, opts) do
    validate_schema!(schema)
    allow(%{schema: schema, rules: %{}}, action, opts)
  end

  @doc false
  def allow(schema_or_ruleset, action) do
    allow(schema_or_ruleset, action, [])
  end

  @doc """
  Denies an action on the schema if matched by conditions.

  See "Permissions with `allow` and `deny`" for a description of conditions.

  ## Examples

      policy
      |> allow(FirstResource, :read)
      |> deny(FirstResource, :read, where: [scope: :private])
  """
  @spec deny(t, Janus.schema_module(), Janus.action() | [Janus.action()], keyword()) :: t
  def deny(%Policy{} = policy, schema, actions, opts) when is_list(actions) do
    Enum.reduce(actions, policy, fn action, policy ->
      deny(policy, schema, action, opts)
    end)
  end

  def deny(%Policy{} = policy, schema, action, opts) do
    validate_schema!(schema)

    policy
    |> rule_for(action, schema)
    |> Rule.deny(opts)
    |> put_rule(policy)
  end

  @doc false
  def deny(%Policy{} = policy, schema, action) do
    deny(policy, schema, action, [])
  end

  @doc """
  Creates or updates a ruleset for a schema to deny an action if matched
  by conditions.

  Must be attached to a policy using `attach/2`.

  See "Permissions with `allow` and `deny`" for a description of conditions.

  ## Examples

      thread_rules =
        Thread
        |> allow(:read)
        |> deny(:read, where: [scope: :private])

      attach(policy, thread_rules)
  """
  @spec deny(Janus.schema_module() | ruleset, Janus.action() | [Janus.action()], keyword()) ::
          ruleset
  def deny(schema_or_ruleset, actions, opts) when is_list(actions) do
    Enum.reduce(actions, schema_or_ruleset, fn action, schema_or_ruleset ->
      deny(schema_or_ruleset, action, opts)
    end)
  end

  def deny(%{schema: schema} = ruleset, action, opts) do
    ruleset
    |> rule_for(action, schema)
    |> Rule.deny(opts)
    |> put_rule(ruleset)
  end

  def deny(schema, action, opts) do
    validate_schema!(schema)
    deny(%{schema: schema, rules: %{}}, action, opts)
  end

  @doc false
  def deny(schema_or_ruleset, action) do
    deny(schema_or_ruleset, action, [])
  end

  defp validate_schema!(schema) when is_atom(schema) do
    function_exported?(schema, :__schema__, 1) || invalid_schema!(schema)
  end

  defp validate_schema!(other), do: invalid_schema!(other)

  defp invalid_schema!(invalid) do
    raise ArgumentError,
          "received invalid module #{inspect(invalid)}, expected a module defined using Ecto.Schema"
  end

  @doc """
  Specifies that a condition should match if another action is allowed.

  If used as the value for an association, the condition will match if
  the action is allowed for the association.

  ## Examples

  Allow users to edit any posts they can delete.

      policy
      |> allow(Post, :edit, where: allows(:delete))
      |> allow(Post, :delete, where: [user_id: user.id])

  Don't allow users to edit posts they can't read.

      policy
      |> allow(Post, :read, where: [archived: false])
      |> allow(Post, :edit, where: [user_id: user.id])
      |> deny(Post, :edit, where_not: allows(:read))

  ## Example with associations

  Let's say we have some posts with comments. Posts are visible unless
  they are archived, and all comments of visible posts are also visible.
  To start, we can duplicate the condition:

      policy
      |> allow(Post, :read, where: [archived: false])
      |> allow(Comment, :read, where: [post: [archived: false]])

  If we add additional clauses to the condition for posts, however, we
  will have to duplicate them for comments. We can use `allows` instead:

      policy
      |> allow(Post, :read, where: [archived: false])
      |> allow(Comment, :read, where: [post: allows(:read)])

  Now let's say we add a feature that allows for draft posts, which
  should not be visible unless a `published_at` is set. We can modify
  only the condition for `Post` and that change will propogate to
  comments.

      policy
      |> allow(Post, :read, where: [archived: false], where_not: [published_at: nil])
      |> allow(Comment, :read, where: [post: allows(:read)])
  """
  def allows(action), do: {:__derived__, :allow, action}

  @doc """
  Attach a ruleset created using `allow/3` and `deny/3` to a policy.
  """
  @spec attach(policy :: t, ruleset) :: t
  def attach(%Policy{} = policy, %{rules: rules}) do
    Enum.reduce(rules, policy, fn {{schema, action}, rule}, policy ->
      policy
      |> rule_for(action, schema)
      |> Rule.merge(rule)
      |> put_rule(policy)
    end)
  end

  @doc false
  def rule_for(%{rules: rules}, action, schema) do
    Map.get_lazy(rules, {schema, action}, fn ->
      Rule.new(schema, action)
    end)
  end

  defp put_rule(%Rule{schema: schema, action: action} = rule, policy_or_ruleset) do
    update_in(policy_or_ruleset.rules, &Map.put(&1, {schema, action}, rule))
  end

  @doc """
  Attach a hook to the policy.

  Expects the following arguments:

    * `policy` - the `%Janus.Policy{}` struct to attach to
    * `name` - an atom identifying the hook
    * `schema` (default `:all`) - an Ecto schema module identifying the
      resource or query source that the hook should be applied to
    * `fun` - the hook function, see "Hooks" below

  If the given `name` is already present, an error will be raised. If
  you wish to replace a hook, you can use `detach_hook/3` before
  re-attaching the hook. If you only wish to add a hook if it is hasn't
  already been added, use `attach_new_hook/4` instead.

  Hooks will be run in the order that they are attached.

  ## Hooks

  Hooks are anonymous or captured functions that accept three arguments:

    * `operation` - one of `:authorize` or `:scope`
    * `object` - either a struct (for `:authorize`) or a queryable (for
      `:scope`) that is being authorized
    * `action` - the action being authorized

  Hooks must return one of the following:

    * `{:cont, object}` - additional hooks and authorization continue
    * `:halt` - halt authorization, running no additional hooks and
      returning `{:error, :not_authorized}` for an `:authorize`
      operation and an empty query for a `:scope` operation

  ## Examples

  When writing hooks, you must ensure that all possible arguments are
  handled. This can be done using a "catch-all" clause. For example:

      policy
      |> attach_hook(:preload_user, fn
        :authorize, %Post{} = resource, _action ->
          {:cont, Repo.preload(resource, :user)}

        _operation, object, _action ->
          {:cont, object}
      end)

      policy
      |> attach_hook(:preload_user, Post, fn
        :authorize, resource, _action ->
          {:cont, Repo.preload(resource, :user)}

        _operation, object, _action ->
          {:cont, object}
      end)

  Hooks can also be captured functions. For example:

      policy
      |> attach_hook(:preload_user, Post, &preload_user/3)

      # elsewhere in your module

      defp preload_user(:authorize, resource, _action) do
        {:cont, Repo.preload(resource, :user)}
      end

      defp preload_user(:scope, query, _action) do
        {:cont, from(query, preload: :user)}
      end

  If `:halt` is returned from a hook, no further hooks will be run and
  nothing will be authorized. This could be used to perform a check on
  banned users, for example:

      @impl true
      def build_policy(policy, user) do
        policy
        |> attach_hook(:ensure_unbanned, fn _op, object, _action ->
          if Accounts.banned?(user.id) do
            :halt
          else
            {:cont, object}
          end
        end)
      end

  This may be required if policies are being cached, since the hook runs
  every time the authorization call happens, instead of only once when
  the policy is built.
  """
  @spec attach_hook(t, atom(), :all | Janus.schema_module(), hook) :: t
  def attach_hook(%Policy{hooks: hooks} = policy, name, schema \\ :all, fun)
      when is_atom(name) and is_atom(schema) do
    validate_hook!(name, schema, fun)
    %{policy | hooks: put_hook!(hooks, schema, name, fun)}
  end

  @doc """
  Attach a new hook to the policy.

  Like `attach_hook/4`, except it only attaches the hook if the `name`
  isn't present for the given schema.
  """
  @spec attach_new_hook(t, atom(), :all | Janus.schema_module(), hook) :: t
  def attach_new_hook(%Policy{hooks: hooks} = policy, name, schema \\ :all, fun)
      when is_atom(name) and is_atom(schema) do
    validate_hook!(name, schema, fun)
    %{policy | hooks: put_new_hook(hooks, schema, name, fun)}
  end

  @doc """
  Detach a hook from the policy.
  """
  @spec detach_hook(t, atom(), :all | Janus.schema_module()) :: t
  def detach_hook(%Policy{hooks: hooks} = policy, name, schema \\ :all) do
    %{policy | hooks: delete_hook(hooks, schema, name)}
  end

  defp validate_hook!(_name, _schema, fun) when is_function(fun, 3), do: :ok

  defp validate_hook!(name, schema, _other) do
    raise ArgumentError,
          "received invalid hook #{inspect(name)} for #{inspect(schema)}, " <>
            "must be a function that accepts 3 arguments"
  end

  defp put_hook!(hooks, key, name, fun) do
    Map.update(hooks, key, [{name, fun}], fn kw ->
      Keyword.update(kw, name, fun, fn _ ->
        raise ArgumentError, "hook #{inspect(name)} for #{inspect(key)} already exists"
      end)
    end)
  end

  defp put_new_hook(hooks, key, name, fun) do
    Map.update(hooks, key, [{name, fun}], fn kw ->
      Keyword.update(kw, name, fun, &Function.identity/1)
    end)
  end

  defp delete_hook(hooks, key, name) do
    Map.update(hooks, key, [], &Keyword.delete(&1, name))
  end

  @doc false
  def run_hooks(stage, object, action, %Policy{hooks: hooks}) do
    schema = resolve_schema_for_stage(stage, object)
    funs = Map.get(hooks, :all, []) ++ Map.get(hooks, schema, [])

    Enum.reduce_while(funs, {:cont, object}, fn {name, fun}, {:cont, object} ->
      case fun.(stage, object, action) do
        {:cont, object} ->
          {:cont, {:cont, object}}

        :halt ->
          {:halt, :halt}

        other ->
          raise ArgumentError, """
          hook #{inspect(name)} returned an invalid result.
          Valid results are:"

            * {:cont, resource_or_query}
            * :halt

          Got: #{inspect(other)}
          """
      end
    end)
  end

  defp resolve_schema_for_stage(:authorize, %schema{}), do: schema

  defp resolve_schema_for_stage(:scope, query) do
    {_query, schema} = Janus.Utils.resolve_query_and_schema!(query)
    schema
  end
end
