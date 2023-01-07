defmodule Janus.Authorization.Filter do
  @moduledoc false

  import Ecto.Query

  alias __MODULE__

  @root_binding :__object__

  defstruct [:policy, :action, :schema, :binding, :dynamic, joins: []]

  @type t :: %Filter{
          policy: Janus.Policy.t(),
          action: Janus.action(),
          schema: Janus.schema_module(),
          binding: atom(),
          dynamic: Ecto.Query.dynamic(),
          joins: keyword()
        }

  @doc """
  Filters a queryable to those authorized by the policy.

  ## Options

  * `:preload_authorized` - preload associated resources, filtering them
    using the same policy and action present on the filter
  """
  def filter_query(queryable, action, policy, opts \\ []) do
    {query, schema} = Janus.Utils.resolve_query_and_schema!(queryable)
    rule = Janus.Policy.rule_for(policy, action, schema)

    root_filter = %Filter{
      dynamic: false,
      binding: @root_binding,
      policy: policy,
      action: action,
      schema: schema
    }

    allowed = combine_all(root_filter, :or, rule.allow, &apply_condition/2)
    denied = combine_all(root_filter, :or, rule.deny, &apply_condition/2)
    filter = combine(allowed, :and_not, denied)

    from(query, as: ^filter.binding, where: ^filter.dynamic)
    |> with_joins(filter)
    |> with_preloads(filter, opts[:preload_authorized])
  end

  defp combine_all(filter, op, items, fun) do
    Enum.reduce(items, filter, fn item, filter ->
      combine(filter, op, fun.(filter, item))
    end)
  end

  defp combine(f1, op, f2) do
    dynamic =
      case op do
        :and -> dynamic_and(f1.dynamic, f2.dynamic)
        :or -> dynamic_or(f1.dynamic, f2.dynamic)
        :and_not -> dynamic_and(f1.dynamic, dynamic_not(f2.dynamic))
      end

    f1
    |> Map.put(:dynamic, dynamic)
    |> Map.put(:joins, Enum.uniq(f1.joins ++ f2.joins))
  end

  defp apply_condition(filter, conditions) when is_list(conditions) do
    combine_all(%{filter | dynamic: true}, :and, conditions, &apply_condition/2)
  end

  defp apply_condition(filter, {:where, clause}) do
    apply_filter_clause(filter, clause)
  end

  defp apply_condition(filter, {:where_not, clause}) do
    filter
    |> apply_filter_clause(clause)
    |> Map.update!(:dynamic, &dynamic_not/1)
  end

  defp apply_condition(filter, {:or, first, second}) do
    combine(apply_condition(filter, first), :or, apply_condition(filter, second))
  end

  defp apply_filter_clause(filter, clauses) when is_list(clauses) do
    combine_all(filter, :and, clauses, &apply_filter_clause/2)
  end

  defp apply_filter_clause(filter, {:__derived__, :allow, action}) do
    subquery = filter_query(filter.schema, action, filter.policy)
    %{filter | joins: filter.joins ++ [__subquery__: {subquery, filter.binding}]}
  end

  defp apply_filter_clause(filter, {field, value}) do
    if schema = association_schema(filter, field) do
      inner = %{filter | schema: schema, binding: field, joins: [{field, filter.binding}]}
      apply_filter_clause(inner, value)
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

  defp association_schema(%Filter{schema: schema}, field) do
    case schema.__schema__(:association, field) do
      nil -> nil
      assoc -> assoc.related
    end
  end

  defp dynamic_and(false, _), do: false
  defp dynamic_and(_, false), do: false
  defp dynamic_and(true, clause), do: clause
  defp dynamic_and(clause, true), do: clause
  defp dynamic_and(clause1, clause2), do: dynamic(^clause1 and ^clause2)

  defp dynamic_or(true, _), do: true
  defp dynamic_or(_, true), do: true
  defp dynamic_or(false, clause), do: clause
  defp dynamic_or(clause, false), do: clause
  defp dynamic_or(clause1, clause2), do: dynamic(^clause1 or ^clause2)

  defp dynamic_not(true), do: false
  defp dynamic_not(false), do: true
  defp dynamic_not(clause), do: dynamic(not (^clause))

  defp with_joins(query, %Filter{joins: joins}) do
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

  defp with_preloads(query, _filter, nil), do: query

  defp with_preloads(query, filter, preload_opt) do
    %{schema: schema, action: action, policy: policy, binding: binding} = filter
    {preloads, preload_opt} = calc_preloads(preload_opt, {schema, action, policy, binding})

    preloads
    |> Enum.reduce(query, fn preload, query ->
      lateral_query =
        from(
          a in preload.related_filtered,
          where:
            field(a, ^preload.related_key) ==
              field(parent_as(^preload.owner_as), ^preload.owner_key),
          select: %{id: a.id}
        )

      from([{^preload.owner_as, r}] in query,
        left_lateral_join: lateral in subquery(lateral_query),
        left_join: a in assoc(r, ^preload.assoc),
        as: ^preload.related_as,
        on: a.id == lateral.id
      )
    end)
    |> from(preload: ^preload_opt)
  end

  defp calc_preloads(assoc, filter_info) when is_atom(assoc) do
    preload_spec(assoc, filter_info, nil)
  end

  defp calc_preloads({assoc, %Ecto.Query{} = query}, filter_info) do
    preload_spec(assoc, filter_info, query)
  end

  defp calc_preloads({assoc, {%Ecto.Query{} = query, rest}}, filter_info) do
    nested_preload_spec({assoc, rest}, filter_info, query)
  end

  defp calc_preloads({assoc, rest}, filter_info) do
    nested_preload_spec({assoc, rest}, filter_info, nil)
  end

  defp calc_preloads(preloads, filter_info) when is_list(preloads) do
    {preloads, preload_opts} =
      preloads
      |> Enum.map(&calc_preloads(&1, filter_info))
      |> Enum.unzip()

    {Enum.concat(preloads), Enum.concat(preload_opts)}
  end

  defp nested_preload_spec({assoc, rest}, {schema, action, policy, binding}, related_query) do
    related_schema = schema.__schema__(:association, assoc).related

    {[preload], [{assoc, dynamic}]} =
      preload_spec(assoc, {schema, action, policy, binding}, related_query)

    {rest_preloads, rest_preload_opt} =
      calc_preloads(rest, {related_schema, action, policy, preload.related_as})

    {[preload | rest_preloads], [{assoc, {dynamic, rest_preload_opt}}]}
  end

  defp preload_spec(assoc, {schema, action, policy, binding}, related_query) do
    association = schema.__schema__(:association, assoc)
    related_as = :"#{assoc}_preload"

    preload = %{
      assoc: assoc,
      owner_as: binding,
      owner_key: association.owner_key,
      related_filtered: filter_query(related_query || association.queryable, action, policy),
      related_as: related_as,
      related_key: association.related_key
    }

    {[preload], [{assoc, dynamic([{^related_as, a}], a)}]}
  end
end
