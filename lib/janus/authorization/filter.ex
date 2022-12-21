defmodule Janus.Authorization.Filter do
  @moduledoc false

  import Ecto.Query
  alias __MODULE__

  @root_binding :__object__

  @type t :: %Filter{
          policy: Janus.Policy.t(),
          action: Janus.action(),
          schema: Janus.schema_module(),
          binding: atom(),
          parent_binding: atom(),
          dynamic: Ecto.Query.dynamic(),
          joins: keyword()
        }

  defstruct [:policy, :action, :schema, :binding, :parent_binding, :dynamic, joins: []]

  defimpl Ecto.Queryable do
    def to_query(filter), do: Filter.to_query(filter)
  end

  @doc """
  Converts a `%Filter{}` struct into an `%Ecto.Query{}`

  ## Options

  * `:query` - initial query to build off of (defaults to `filter.struct`)
  * `:preload_authorized` - preload associated resources, filtering them using the same
    policy and action present on the filter
  """
  def to_query(%Filter{} = filter, opts \\ []) do
    %{
      schema: schema,
      binding: binding,
      dynamic: dynamic,
      joins: joins
    } = filter

    initial_query = Keyword.get(opts, :query, schema)

    from(initial_query, as: ^binding, where: ^dynamic)
    |> with_joins(joins)
    |> with_preload_authorized(filter, opts[:preload_authorized])
  end

  @doc """
  Filters a query using action and policy.

  Note that opts must have been processed using `prep_opts/1` at macro time.
  """
  def filter(query_or_schema, action, policy, opts \\ []) do
    {query, schema} = Janus.Utils.resolve_query_and_schema!(query_or_schema)
    rule = Janus.Policy.rule_for(policy, action, schema)

    base_filter = %Filter{
      policy: policy,
      action: action,
      schema: schema,
      dynamic: false,
      binding: @root_binding
    }

    allowed = with_conditions(base_filter, rule.allow)
    forbidden = with_conditions(base_filter, rule.forbid)

    combine(allowed, :and_not, forbidden)
    |> to_query(Keyword.put(opts, :query, query))
  end

  defp with_conditions(filter, conditions) do
    for condition <- conditions, reduce: filter do
      filter ->
        f = apply_condition(condition, filter)
        combine(filter, :or, f)
    end
  end

  defp combine(f1, op, f2) do
    f1
    |> Map.put(:dynamic, combine_dynamic(f1.dynamic, op, f2.dynamic))
    |> Map.put(:joins, merge_joins(f1.joins, f2.joins))
  end

  defp with_joins(query, joins) do
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

  defp combine_dynamic(d1, :and, d2), do: simplify_and(d1, d2)
  defp combine_dynamic(d1, :or, d2), do: simplify_or(d1, d2)
  defp combine_dynamic(d1, :and_not, d2), do: simplify_and(d1, simplify_not(d2))

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

  defp apply_clause({:__derived_allow__, action}, filter) do
    subquery = filter(filter.schema, action, filter.policy)
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
      %{filter | dynamic: dynamic_compare(filter, field, value)}
    end
  end

  defp dynamic_compare(filter, field, fun) when is_function(fun, 3) do
    fun.(:dynamic, filter.binding, field)
  end

  defp dynamic_compare(_filter, _field, fun) when is_function(fun) do
    raise ArgumentError, "permission functions must take 3 arguments (#{inspect(fun)})"
  end

  defp dynamic_compare(filter, field, nil) do
    dynamic(as(^filter.binding) |> field(^field) |> is_nil())
  end

  defp dynamic_compare(filter, field, value) do
    type_info = filter.schema.__schema__(:type, field)
    dumped_value = dump!(type_info, value)

    dynamic(field(as(^filter.binding), ^field) == ^dumped_value)
  end

  defp dump!(type_info, value) do
    case dump(type_info, value) do
      {:ok, dumped} -> dumped
      _ -> raise ArgumentError, "could not dump #{inspect(value)} to type #{inspect(type_info)}"
    end
  end

  defp dump({:parameterized, type, params}, value) do
    type.dump(value, nil, params)
  end

  defp dump(type, value) when is_atom(type) do
    Ecto.Type.dump(type, value)
  end

  defp associated_schema(%Filter{} = filter, field) do
    associated_schema(filter.schema, field)
  end

  defp associated_schema(schema, field) when is_atom(schema) do
    case schema.__schema__(:association, field) do
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

  defp simplify_not(true), do: false
  defp simplify_not(false), do: true
  defp simplify_not(clause), do: dynamic(not (^clause))

  defp with_preload_authorized(query, _filter, nil), do: query

  defp with_preload_authorized(query, filter, preload_opt) do
    {preloads, preload_opt} = calc_preloads(preload_opt, filter.schema, filter.binding, filter)

    query =
      for preload <- preloads, reduce: query do
        query ->
          from([{^preload.owner_as, r}] in query,
            left_lateral_join:
              lateral in subquery(
                from(
                  a in preload.related_filtered,
                  where:
                    field(a, ^preload.related_key) ==
                      field(parent_as(^preload.owner_as), ^preload.owner_key),
                  select: %{id: a.id, lateral_selected: true}
                )
              ),
            left_join: a in assoc(r, ^preload.assoc),
            as: ^preload.related_as,
            on: a.id == lateral.id
          )
      end

    from(query, preload: ^preload_opt)
  end

  defp calc_preloads(assoc, schema, binding, filter) when is_atom(assoc) do
    {preload, preload_opt} = preload_spec(assoc, schema, binding, filter)
    {[preload], preload_opt}
  end

  defp calc_preloads({assoc, %Ecto.Query{} = query}, schema, binding, filter) do
    {preload, preload_opt} = preload_spec(assoc, schema, binding, filter, query)
    {[preload], preload_opt}
  end

  defp calc_preloads({assoc, {%Ecto.Query{} = query, rest}}, schema, binding, filter) do
    nested_preload_spec({assoc, rest}, schema, binding, filter, query)
  end

  defp calc_preloads({assoc, rest}, schema, binding, filter) do
    nested_preload_spec({assoc, rest}, schema, binding, filter, nil)
  end

  defp calc_preloads(preloads, schema, binding, filter) when is_list(preloads) do
    {preloads, preload_opts} =
      preloads
      |> Enum.map(&calc_preloads(&1, schema, binding, filter))
      |> Enum.unzip()

    {Enum.concat(preloads), Enum.concat(preload_opts)}
  end

  defp nested_preload_spec({assoc, rest}, schema, binding, filter, related_query) do
    related_schema = schema.__schema__(:association, assoc).related

    {preload, [{assoc, dynamic}]} = preload_spec(assoc, schema, binding, filter, related_query)

    {rest_preloads, rest_preload_opt} =
      calc_preloads(rest, related_schema, preload.related_as, filter)

    {[preload | rest_preloads], [{assoc, {dynamic, rest_preload_opt}}]}
  end

  defp preload_spec(assoc, schema, binding, filter, related_query \\ nil) do
    association = schema.__schema__(:association, assoc)
    related_query = related_query || association.queryable
    related_as = :"#{assoc}_preload"

    preload = %{
      assoc: assoc,
      owner_as: binding,
      owner_key: association.owner_key,
      related_filtered: filter(related_query, filter.action, filter.policy),
      related_as: related_as,
      related_key: association.related_key
    }

    {preload, [{assoc, dynamic([{^related_as, a}], a)}]}
  end
end
