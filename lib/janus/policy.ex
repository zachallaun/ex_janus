defmodule Janus.Policy do
  @moduledoc """
  TODO

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

  @callback policy_for(t, actor :: Janus.actor()) :: t

  @callback authorize(any(), Janus.action(), Janus.actor(), keyword()) :: {:ok, any()} | :error

  @callback any_authorized?(Janus.schema(), Janus.action(), Janus.actor()) :: boolean()

  @callback filter_authorized(
              Ecto.Query.t() | Janus.schema(),
              Janus.action(),
              Janus.actor(),
              keyword()
            ) :: Ecto.Query.t()

  @doc false
  defmacro __using__(_opts) do
    quote do
      @behaviour Janus.Policy
      require Janus
      import Janus.Policy, except: [rule_for: 3]

      unquote(default_using())

      @doc "Returns the policy for the given actor."
      def policy_for(%Janus.Policy{} = policy), do: policy
      def policy_for(actor), do: policy_for(%Janus.Policy{}, actor)

      @doc "See `Janus.authorize/4`"
      @impl true
      def authorize(object, action, actor, opts \\ []) do
        Janus.authorize(object, action, policy_for(actor), opts)
      end

      @doc "See `Janus.any_authorized?/3`"
      @impl true
      def any_authorized?(schema, action, actor) do
        Janus.any_authorized?(schema, action, policy_for(actor))
      end

      @doc "See `Janus.filter_authorized/4`"
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
