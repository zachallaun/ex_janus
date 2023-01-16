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
  usually invoke `use Janus` to create a module that implements both
  this and the `Janus.Authorization` behaviour:

      defmodule MyApp.Policy do
        use Janus

        @impl true
        def build_policy(policy, _actor) do
          policy
        end
      end

  The `build_policy/2` callback is the only callback that is required in
  policy modules.

  ## Permissions with `allow` and `deny`

  Permissions are primarily defined using `allow/4` and `deny/4`, which
  allows or denies an action on a resource if a set of conditions match.
  Both functions take the same arguments and options. When permissions
  are being checked, multiple `allow` rules combine using logical-or,
  with `deny` rules overriding `allow`.

  For example, the following policy would allow a moderator to edit
  their own comments and any comments flagged for review, but not those
  made by an admin.

      def build_policy(policy, %User{role: :moderator} = user) do
        policy
        |> allow(Comment, :edit, where: [user: [id: user.id]])
        |> allow(Comment, :edit, where: [flagged_for_review: true])
        |> deny(Comment, :edit, where: [user: [role: :admin]])
      end

  While set of keyword options passed to `allow` and `deny` are
  reminiscent of keyword-based Ecto queries, but since they are
  functions and not macros, there is no need to use the `^value` syntax
  used in Ecto. For example, the following would result in an error:

      allow(policy, Comment, :edit, where: [user: [id: ^user.id]])

  ### `:where` and `:where_not` conditions

  These conditions match if the associated fields are equal to each
  other. For instance, the moderation example above could also be
  written as:

      def build_policy(policy, %User{role: :moderator} = user) do
        policy
        |> allow(Comment, :edit, where: [user_id: user.id])
        |> allow(Comment, :edit,
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

      def build_policy(policy, %User{role: :moderator} = user) do
        policy
        |> allow(Comment, :edit,
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
      |> allow(Comment, :edit,
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

  defstruct [:module, config: %{}, rules: %{}, hooks: %{}]

  @type t :: %Policy{
          module: module(),
          config: map(),
          rules: %{
            {Janus.schema_module(), Janus.action()} => Rule.t()
          },
          hooks: %{
            optional(Janus.schema_module() | :all) => keyword(hook)
          }
        }

  @type hook ::
          (Ecto.Schema.t() | Authorization.filterable(), Janus.action(), t ->
             {:cont, Ecto.Schema.t() | Authorization.filterable()} | :halt)

  @doc """
  Returns the policy for the given actor.

  This is the only callback that is required in a policy module.
  """
  @callback build_policy(t, Janus.actor()) :: t

  @doc false
  defmacro __using__(opts \\ []) do
    quote location: :keep do
      @behaviour Janus.Policy
      Module.register_attribute(__MODULE__, unquote(@config), persist: true)
      Module.put_attribute(__MODULE__, unquote(@config), unquote(opts))

      import Janus.Policy, except: [rule_for: 3, run_hooks: 4]

      @doc """
      Returns the policy for the given actor.

      See `c:Janus.Policy.build_policy/2` for more information.
      """
      def build_policy(%Janus.Policy{} = policy), do: policy

      def build_policy(actor) do
        __MODULE__
        |> Janus.Policy.new()
        |> build_policy(actor)
      end
    end
  end

  @doc false
  def new(module) do
    config =
      module.__info__(:attributes)
      |> Keyword.get(@config, [])
      |> Keyword.validate!(@config_defaults)
      |> Enum.into(%{})

    %Janus.Policy{module: module, config: config}
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
  def allow(policy, schema, action, opts \\ [])

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

  @doc """
  Denies an action on the schema if matched by conditions.

  See "Permissions with `allow` and `deny`" for a description of conditions.

  ## Examples

      policy
      |> allow(FirstResource, :read)
      |> deny(FirstResource, :read, where: [scope: :private])
  """
  @spec deny(t, Janus.schema_module(), Janus.action() | [Janus.action()], keyword()) :: t
  def deny(policy, schema, action, opts \\ [])

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
