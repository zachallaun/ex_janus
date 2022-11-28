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

    {query, where} =
      {from(rule.schema, as: ^@root_binding), false}
      |> or_where(rule.allow, schema, policy)
      |> and_where_not(rule.forbid, schema, policy)
      |> or_where(rule.always_allow, schema, policy)

    from(query, where: ^where)
  end

  defp or_where({query, where}, [condition | rest], schema, policy) do
    {query, where_condition} = apply_condition(query, condition, schema, policy)

    {query, simplify_or(where, where_condition)}
    |> or_where(rest, schema, policy)
  end

  defp or_where(acc, [], _schema, _policy), do: acc

  defp and_where_not({query, where}, [condition | rest], schema, policy) do
    {query, where_condition} = apply_condition(query, condition, schema, policy)

    {query, simplify_and(where, dynamic(not (^where_condition)))}
    |> and_where_not(rest, schema, policy)
  end

  defp and_where_not(acc, [], _schema, _policy), do: acc

  defp apply_condition(query, [], _schema, _policy) do
    {query, true}
  end

  defp apply_condition(query, [{:where, clause} | rest], schema, policy) do
    {query, where_clause, rest_where} = apply_clause_and_rest(query, clause, rest, schema, policy)

    {query, simplify_and(where_clause, rest_where)}
  end

  defp apply_condition(query, [{:where_not, clause} | rest], schema, policy) do
    {query, where_clause, rest_where} = apply_clause_and_rest(query, clause, rest, schema, policy)

    {query, simplify_and(dynamic(not (^where_clause)), rest_where)}
  end

  defp apply_clause_and_rest(query, clause, rest_conditions, schema, policy) do
    {query, where_clause} = apply_clause(query, clause, schema, policy, @root_binding)
    {query, rest_where} = apply_condition(query, rest_conditions, schema, policy)

    {query, where_clause, rest_where}
  end

  defp apply_clause(query, [clause | rest], schema, policy, binding) do
    {query, where_clause} = apply_clause(query, clause, schema, policy, binding)
    {query, rest_clause} = apply_clause(query, rest, schema, policy, binding)

    {query, simplify_and(where_clause, rest_clause)}
  end

  defp apply_clause(query, [], _schema, _policy, _binding), do: {query, nil}

  defp apply_clause(query, {:__janus_derived__, action}, schema, policy, binding) do
    subquery = filter(schema, action, policy)

    query = from(query, join: sub in subquery(subquery), on: as(^binding).id == sub.id)

    {query, nil}
  end

  defp apply_clause(query, {field, value}, schema, policy, binding) do
    if field in schema.__schema__(:associations) do
      related = schema.__schema__(:association, field).related

      query =
        Ecto.Query.with_named_binding(query, field, fn query, _ ->
          from([{^binding, x}] in query, join: y in assoc(x, ^field), as: ^field)
        end)

      apply_clause(query, value, related, policy, field)
    else
      {query, dynamic(field(as(^binding), ^field) == ^value)}
    end
  end

  defp simplify_and(false, _), do: false
  defp simplify_and(_, false), do: false
  defp simplify_and(nil, clause), do: clause
  defp simplify_and(true, clause), do: clause
  defp simplify_and(clause, nil), do: clause
  defp simplify_and(clause, true), do: clause
  defp simplify_and(clause1, clause2), do: dynamic(^clause1 and ^clause2)

  defp simplify_or(true, _), do: true
  defp simplify_or(_, true), do: true
  defp simplify_or(nil, clause), do: clause
  defp simplify_or(false, clause), do: clause
  defp simplify_or(clause, nil), do: clause
  defp simplify_or(clause, false), do: clause
  defp simplify_or(clause1, clause2), do: dynamic(^clause1 or ^clause2)
end
