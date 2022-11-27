defmodule Janus do
  @external_resource "README.md"
  @moduledoc "README.md"
             |> File.read!()
             |> String.split("<!-- MDOC -->")
             |> Enum.fetch!(1)

  import Ecto.Query, only: [from: 2]

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

  @as_ref :__object__

  @doc """
  Returns an `Ecto.Query` that filters records from `schema` to those that can have
  `action` performed according to the `policy`.
  """
  def filter(schema, action, policy) when is_atom(schema) do
    rule = Janus.Policy.rule_for(policy, action, schema)

    from(rule.schema, as: ^@as_ref)
  end
end
