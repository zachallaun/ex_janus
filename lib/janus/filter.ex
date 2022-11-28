defmodule Janus.Filter do
  @moduledoc false
  alias __MODULE__
  import Ecto.Query

  @type t :: %Filter{
          policy: Janus.Policy.t(),
          schema: Janus.schema(),
          binding: atom(),
          parent_binding: atom(),
          dynamic: Ecto.Query.dynamic(),
          joins: keyword()
        }

  defstruct [:policy, :schema, :binding, :parent_binding, :dynamic, joins: []]

  defimpl Ecto.Queryable do
    def to_query(filter), do: Janus.Filter.to_query(filter)
  end

  @doc "Convert a `%Filter{}` to an `%Ecto.Query{}`."
  def to_query(%Filter{} = filter) do
    %{
      schema: schema,
      binding: binding,
      dynamic: dynamic,
      joins: joins
    } = filter

    query = from(schema, as: ^binding, where: ^dynamic)

    for join <- joins, reduce: query do
      query ->
        case join do
          {:__subquery__, {subquery, binding}} ->
            from(query, join: s in subquery(subquery), on: as(^binding).id == s.id)

          {assoc, binding} ->
            from([{^binding, x}] in query, join: assoc(x, ^assoc), as: ^assoc)
        end
    end
  end

  @doc "Create a new filter."
  def new(policy, schema, binding, dynamic \\ nil) do
    %Filter{
      policy: policy,
      schema: schema,
      binding: binding,
      parent_binding: binding,
      dynamic: dynamic
    }
  end

  @doc """
  Create a new filter using `filter` that filters to resources that match one of the
  given `conditions`.
  """
  def with_conditions(%Filter{} = filter, conditions) do
    for condition <- conditions, reduce: filter do
      filter ->
        f = apply_condition(condition, filter)
        combine(filter, :or, f)
    end
  end

  @doc "Combine two filters using the given logical operation."
  def combine(f1, op, f2) do
    f1
    |> Map.put(:dynamic, combine_dynamic(f1.dynamic, op, f2.dynamic))
    |> Map.put(:joins, merge_joins(f1.joins, f2.joins))
  end

  defp combine_dynamic(d1, :and, d2), do: simplify_and(d1, d2)
  defp combine_dynamic(d1, :or, d2), do: simplify_or(d1, d2)
  defp combine_dynamic(d1, :and_not, d2), do: simplify_and(d1, dynamic(not (^d2)))

  defp merge_joins(j1, j2), do: Enum.uniq(j1 ++ j2)

  defp apply_condition({:where, clause}, filter) do
    apply_clause(clause, filter)
  end

  defp apply_condition({:where_not, clause}, filter) do
    %{dynamic: dynamic} = filter = apply_clause(clause, filter)
    %{filter | dynamic: dynamic(not (^dynamic))}
  end

  defp apply_condition([], filter) do
    %{filter | dynamic: true}
  end

  defp apply_condition(conditions, filter) when is_list(conditions) do
    for condition <- conditions, reduce: %{filter | dynamic: true} do
      filter ->
        f = apply_condition(condition, filter)
        combine(filter, :and, f)
    end
  end

  defp apply_clause(clauses, filter) when is_list(clauses) do
    for clause <- clauses, reduce: filter do
      filter ->
        f = apply_clause(clause, filter)
        combine(filter, :and, f)
    end
  end

  defp apply_clause({:__janus_derived__, action}, filter) do
    subquery = Janus.filter(filter.schema, action, filter.policy)
    %{filter | joins: merge_joins(filter.joins, __subquery__: {subquery, filter.binding})}
  end

  defp apply_clause({field, value}, filter) do
    if schema = associated_schema(filter, field) do
      apply_clause(value, %{
        filter
        | schema: schema,
          binding: field,
          parent_binding: filter.binding,
          joins: [{field, filter.binding}]
      })
    else
      dynamic = dynamic(field(as(^filter.binding), ^field) == ^value)
      %{filter | dynamic: dynamic}
    end
  end

  defp associated_schema(filter, field) do
    case filter.schema.__schema__(:association, field) do
      nil -> nil
      assoc -> assoc.related
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
