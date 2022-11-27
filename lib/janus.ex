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
        Janus.allows?(policy_for(actor), action, object)
      end

      @doc "See `Janus.forbids?/3`"
      def forbids?(actor, action, object) do
        !allows?(actor, action, object)
      end

      @doc "See `Janus.filter/3`"
      def filter(query, action, actor) do
        Janus.filter(query, action, policy_for(actor))
      end

      defoverridable allows?: 3, forbids?: 3, filter: 3
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
    |> allow_if_any?(rule.allow, policy, action, object)
    |> forbid_if_any?(rule.forbid, policy, action, object)
    |> allow_if_any?(rule.always_allow, policy, action, object)
  end

  @doc "Returns `true` if the given `policy` forbids `action` to be taken on `object`."
  def forbids?(policy, action, object) do
    !allows?(policy, action, object)
  end

  defp allow_if_any?(true, _conditions, _policy, _action, _object), do: true

  defp allow_if_any?(_, conditions, policy, action, object) do
    Enum.any?(conditions, &condition_match?(&1, policy, action, object))
  end

  defp forbid_if_any?(false, _conditions, _policy, _action, _object), do: false

  defp forbid_if_any?(_, conditions, policy, action, object) do
    !Enum.any?(conditions, &condition_match?(&1, policy, action, object))
  end

  defp condition_match?([], _policy, _action, _object), do: true

  defp condition_match?(condition, policy, action, object) when is_list(condition) do
    Enum.all?(condition, &condition_match?(&1, policy, action, object))
  end

  defp condition_match?({:where, clause}, policy, action, object) do
    clause_match?(clause, policy, action, object)
  end

  defp condition_match?({:where_not, clause}, policy, action, object) do
    !clause_match?(clause, policy, action, object)
  end

  defp clause_match?(list, policy, action, object) when is_list(list) do
    Enum.all?(list, &clause_match?(&1, policy, action, object))
  end

  defp clause_match?({attr, value}, _policy, _action, object) do
    Map.get(object, attr) == value
  end

  @as_ref :__object__

  @doc """
  Returns an `Ecto.Query` that filters records from `schema` to those that can have
  `action` performed according to the `policy`.
  """
  def filter(schema, action, policy) when is_atom(schema) do
    rule = Janus.Policy.rule_for(policy, action, schema)

    {query, where} =
      {from(rule.schema, as: ^@as_ref), false}
      |> or_where(rule.allow, schema, action, policy)
      |> and_where_not(rule.forbid, schema, action, policy)
      |> or_where(rule.always_allow, schema, action, policy)

    from(query, where: ^where)
  end

  defp or_where({query, where}, [condition | rest], schema, action, policy) do
    {query, where_condition} = apply_condition(query, condition, schema, action, policy)

    {query, dynamic(^where or ^where_condition)}
    |> or_where(rest, schema, action, policy)
  end

  defp or_where(acc, [], _schema, _action, _policy), do: acc

  defp and_where_not({query, where}, [condition | rest], schema, action, policy) do
    {query, where_condition} = apply_condition(query, condition, schema, action, policy)

    {query, dynamic(^where and not (^where_condition))}
    |> and_where_not(rest, schema, action, policy)
  end

  defp and_where_not(acc, [], _schema, _action, _policy), do: acc

  defp apply_condition(query, [], _schema, _action, _policy) do
    {query, true}
  end

  defp apply_condition(query, [{:where, clause} | rest], schema, action, policy) do
    {query, where_clause, rest_where} =
      apply_clause_and_rest(query, clause, rest, schema, action, policy)

    {query, dynamic(^where_clause and ^rest_where)}
  end

  defp apply_condition(query, [{:where_not, clause} | rest], schema, action, policy) do
    {query, where_clause, rest_where} =
      apply_clause_and_rest(query, clause, rest, schema, action, policy)

    {query, dynamic(not (^where_clause) and ^rest_where)}
  end

  defp apply_clause_and_rest(query, clause, rest_conditions, schema, action, policy) do
    {query, where_clause} = apply_clause(query, clause, schema, action, policy)
    {query, rest_where} = apply_condition(query, rest_conditions, schema, action, policy)

    {query, where_clause, rest_where}
  end

  defp apply_clause(query, [clause | rest], schema, action, policy) do
    {query, where_clause} = apply_clause(query, clause, schema, action, policy)

    case apply_clause(query, rest, schema, action, policy) do
      {query, rest_where} ->
        {query, dynamic(^where_clause and ^rest_where)}

      nil ->
        {query, where_clause}
    end
  end

  defp apply_clause(_query, [], _schema, _action, _policy), do: nil

  defp apply_clause(query, {attr, value}, _schema, _action, _policy) do
    {query, dynamic(field(as(^@as_ref), ^attr) == ^value)}
  end
end
