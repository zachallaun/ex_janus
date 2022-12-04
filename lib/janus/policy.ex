defmodule Janus.Policy.Rule do
  @moduledoc """
  Struct containing the authorization data for a struct and action.
  """

  @type t :: %__MODULE__{
          schema: Janus.schema(),
          action: Janus.action(),
          allow: [keyword()],
          forbid: [keyword()],
          always_allow: [keyword()]
        }

  defstruct [
    :schema,
    :action,
    allow: [],
    forbid: [],
    always_allow: []
  ]

  @doc false
  def new(schema, action) do
    %__MODULE__{schema: schema, action: action}
  end

  @doc false
  def allow(rule, opts) do
    if [] in rule.forbid do
      rule
    else
      Map.update(rule, :allow, [opts], &[opts | &1])
    end
  end

  @doc false
  def forbid(rule, []), do: Map.merge(rule, %{allow: [], forbid: [[]]})
  def forbid(rule, opts), do: Map.update(rule, :forbid, [opts], &[opts | &1])

  @doc false
  def always_allow(rule, []), do: Map.merge(rule, %{allow: [], forbid: [], always_allow: [[]]})
  def always_allow(rule, opts), do: Map.update(rule, :always_allow, [opts], &[opts | &1])
end

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

  @callback policy_for(t, actor :: any()) :: t

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
