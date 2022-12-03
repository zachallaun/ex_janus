defmodule Janus do
  @external_resource "README.md"
  @moduledoc "README.md"
             |> File.read!()
             |> String.split("<!-- MDOC -->")
             |> Enum.fetch!(1)

  require Ecto.Query

  @type action :: atom()
  @type schema :: atom()
  @type actor :: any()

  @callback policy_for(policy :: Janus.Policy.t(), actor) :: Janus.Policy.t()

  @doc false
  defmacro __using__(_opts) do
    quote do
      @behaviour Janus
      require Janus
      import Janus.Policy, except: [rule_for: 3]

      @doc "See `Janus.allows?/3`"
      def allows?(actor, action, object) do
        Janus.allows?(__policy_for__(actor), action, object)
      end

      @doc "See `Janus.forbids?/3`"
      def forbids?(actor, action, object) do
        !allows?(actor, action, object)
      end

      @doc "See `Janus.filter/4`"
      defmacro filter(query_or_schema, action, actor, opts \\ []) do
        quote do
          Janus.filter(
            unquote(query_or_schema),
            unquote(action),
            unquote(__MODULE__).__policy_for__(unquote(actor)),
            unquote(opts)
          )
        end
      end

      def __policy_for__(%Janus.Policy{} = policy), do: policy
      def __policy_for__(actor), do: policy_for(actor)
    end
  end

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
      compare_field(object, field, value)
    end
  end

  defp compare_field(object, field, fun) when is_function(fun, 3) do
    fun.(:boolean, object, field)
  end

  defp compare_field(_object, _field, fun) when is_function(fun) do
    raise "permission functions must have arity 3 (#{inspect(fun)})"
  end

  defp compare_field(object, field, value) do
    Map.get(object, field) == value
  end

  defp fetch_associated!(object, field) do
    case Map.fetch!(object, field) do
      %Ecto.Association.NotLoaded{} ->
        raise "field #{inspect(field)} must be pre-loaded on #{inspect(object)}"

      value ->
        value
    end
  end

  @doc """
  Creates an `Ecto.Query` that filters records from `schema` to those that can have
  `action` performed according to the `policy`.

  ## Options

  * `:preload_filtered` - preload associated resources on the result, but filtered to
    those that are allowed based on the action and policy.
  """
  defmacro filter(query_or_schema, action, policy, opts \\ []) do
    quote bind_quoted: [
            query_or_schema: query_or_schema,
            action: action,
            policy: policy,
            opts: Janus.Filter.prep_opts(opts)
          ] do
      Janus.Filter.filter(query_or_schema, action, policy, opts)
    end
  end
end
