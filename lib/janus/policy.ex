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

  The `policy_for/2` callback

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
  3. Take the union of 2. and resources matched by any `always_allow` rule.
  """

  alias __MODULE__
  alias __MODULE__.Rule

  @type t :: %Policy{
          rules: %{
            {Janus.schema(), Janus.action()} => Rule.t()
          }
        }

  defstruct rules: %{}

  @callback policy_for(t, Janus.actor()) :: t

  @callback before_policy_for(any(), t, Janus.actor()) ::
              {:cont, t, Janus.actor()} | {:halt, t, Janus.actor()}

  @callback authorize(any(), Janus.action(), Janus.actor(), keyword()) :: {:ok, any()} | :error

  @callback any_authorized?(Janus.schema(), Janus.action(), Janus.actor()) :: boolean()

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

  @doc "TODO"
  @spec allow(t, Janus.action(), Janus.schema(), keyword()) :: t
  def allow(%Policy{} = policy, action, schema, opts \\ []) do
    policy
    |> rule_for(action, schema)
    |> Rule.allow(opts)
    |> put_rule(policy)
  end

  @doc "TODO"
  @spec forbid(t, Janus.action(), Janus.schema(), keyword()) :: t
  def forbid(%Policy{} = policy, action, schema, opts \\ []) do
    policy
    |> rule_for(action, schema)
    |> Rule.forbid(opts)
    |> put_rule(policy)
  end

  @doc "TODO"
  @spec always_allow(t, Janus.action(), Janus.schema(), keyword()) :: t
  def always_allow(%Policy{} = policy, action, schema, opts \\ []) do
    policy
    |> rule_for(action, schema)
    |> Rule.always_allow(opts)
    |> put_rule(policy)
  end

  @doc "TODO (derived permissions)"
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
