defmodule Janus do
  @external_resource "README.md"
  @moduledoc "README.md"
             |> File.read!()
             |> String.split("<!-- MDOC -->")
             |> Enum.fetch!(1)

  import Ecto.Query, only: [from: 2, dynamic: 1, dynamic: 2], warn: false

  @type action :: atom()
  @type schema :: atom()
  @type actor :: any()

  @callback policy_for(policy :: Janus.Policy.t(), actor) :: Janus.Policy.t()

  @doc false
  defmacro __using__(_opts) do
    quote do
      @behaviour Janus
      import Janus.Policy, except: [rule_for: 3]

      @doc "See `Janus.allows?/3`"
      def allows?(actor, action, object) do
        Janus.allows?(__policy_for__(actor), action, object)
      end

      @doc "See `Janus.forbids?/3`"
      def forbids?(actor, action, object) do
        !allows?(actor, action, object)
      end

      @doc "See `Janus.filter/3`"
      def filter(query, action, actor) do
        Janus.filter(query, action, __policy_for__(actor))
      end

      defoverridable allows?: 3, forbids?: 3, filter: 3

      defp __policy_for__(%Janus.Policy{} = policy), do: policy
      defp __policy_for__(actor), do: policy_for(actor)
    end
  end

  # TODO
  # Detect cyclic rules, e.g.
  #   policy
  #   |> allow(:read, Thing, where: allows(:read, Thang))
  #   |> allow(:read, Thang, where: allows(:read, Thing))

  @doc "Returns `true` if the given `policy` allows `action` to be taken on `object`."
  def allows?(policy, action, %schema{} = object) do
    rule = Janus.Policy.rule_for(policy, action, schema)

    false
    |> allow_if_any?(rule.allow, policy, object)
    |> forbid_if_any?(rule.forbid, policy, object)
    |> allow_if_any?(rule.always_allow, policy, object)
  end

  @doc "Returns `true` if the given `policy` forbids `action` to be taken on `object`."
  def forbids?(policy, action, object) do
    !allows?(policy, action, object)
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
    allows?(policy, action, object)
  end

  defp clause_match?({field, value}, policy, %schema{} = object) do
    if field in schema.__schema__(:associations) do
      clause_match?(value, policy, fetch_associated!(object, field))
    else
      Map.get(object, field) == value
    end
  end

  defp fetch_associated!(object, field) do
    case Map.fetch!(object, field) do
      %Ecto.Association.NotLoaded{} ->
        raise "field #{inspect(field)} must be pre-loaded on #{inspect(object)}"

      value ->
        value
    end
  end

  @root_binding :__object__

  @doc """
  Returns an `Ecto.Query` that filters records from `schema` to those that can have
  `action` performed according to the `policy`.
  """
  def filter(schema, action, policy) when is_atom(schema) do
    rule = Janus.Policy.rule_for(policy, action, schema)

    Janus.Filter.new(policy, schema, @root_binding, false)
    |> or_where(rule.allow)
    |> and_where_not(rule.forbid)
    |> or_where(rule.always_allow)
    |> Ecto.Queryable.to_query()
  end

  defp or_where(filter, []), do: filter

  defp or_where(filter, conditions) do
    f = Janus.Filter.with_conditions(filter, conditions)
    Janus.Filter.combine(filter, :or, f)
  end

  defp and_where_not(filter, []), do: filter

  defp and_where_not(filter, conditions) do
    f = Janus.Filter.with_conditions(filter, conditions)
    Janus.Filter.combine(filter, :and_not, f)
  end
end
