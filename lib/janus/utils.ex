defmodule Janus.Utils do
  @moduledoc false

  @doc """
  Resolves a query or a schema to a `{query, schema}` pair.

  If an `%Ecto.Query{}` is passed, the schema will be resolved from its `:from` field.

  If a schema is passed, the query will be resolved using `Ecto.Queryable.to_query/1`.
  """
  def resolve_query_and_schema!(%Ecto.Query{} = query) do
    {query, resolve_schema!(query)}
  end

  def resolve_query_and_schema!({%Ecto.Query{} = query, schema}) do
    {query, resolve_schema!(schema)}
  end

  def resolve_query_and_schema!(schema) when is_atom(schema) do
    schema = resolve_schema!(schema)
    {Ecto.Queryable.to_query(schema), schema}
  end

  def resolve_query_and_schema!(query_or_schema) do
    raise ArgumentError, "could not resolve query and schema from #{inspect(query_or_schema)}"
  end

  defp resolve_schema!(%Ecto.Query{from: from}), do: resolve_schema!(from.source)
  defp resolve_schema!(%Ecto.SubQuery{query: query}), do: resolve_schema!(query)
  defp resolve_schema!({_, schema}), do: resolve_schema!(schema)
  defp resolve_schema!(schema) when is_atom(schema) and not is_nil(schema), do: schema
end
