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

      unquote(default_using())

      @doc "See `Janus.authorize/4`"
      def authorize(object, action, actor, opts \\ []) do
        Janus.authorize(object, action, __policy_for__(actor), opts)
      end

      @doc "See `Janus.authorized/4`"
      defmacro authorized(query_or_schema, action, actor, opts \\ []) do
        quote do
          require Janus

          Janus.authorized(
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

  defp default_using do
    quote unquote: false do
      @doc false
      defmacro __using__(_opts) do
        quote do
          require unquote(__MODULE__)

          import unquote(__MODULE__),
            only: [authorize: 3, authorize: 4, authorized: 3, authorized: 4]
        end
      end

      defoverridable __using__: 1
    end
  end

  @doc """
  Authorize that the given `action` is allowed for `object` based on `policy`.

  Returns `{:ok, object}` if the action is authorized and `:error` otherwise.
  """
  def authorize(%schema{} = object, action, policy, _opts \\ []) do
    rule = Janus.Policy.rule_for(policy, action, schema)

    false
    |> allow_if_any?(rule.allow, policy, object)
    |> forbid_if_any?(rule.forbid, policy, object)
    |> allow_if_any?(rule.always_allow, policy, object)
    |> case do
      true -> {:ok, object}
      false -> :error
    end
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
    case authorize(object, action, policy) do
      {:ok, _} -> true
      :error -> false
    end
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

  * `:preload_authorized` - preload associated resources on the result, but filtered to
    those that are allowed based on the action and policy.
  """
  defmacro authorized(query_or_schema, action, policy, opts \\ []) do
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
