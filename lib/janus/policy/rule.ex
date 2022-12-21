defmodule Janus.Policy.Rule do
  @moduledoc """
  Defines a rule for an individual schema and action.
  """

  @type t :: %__MODULE__{
          schema: Janus.schema_module(),
          action: Janus.action(),
          allow: [keyword() | boolean()],
          forbid: [keyword() | boolean()]
        }

  defstruct [
    :schema,
    :action,
    allow: [],
    forbid: []
  ]

  @doc false
  def new(schema, action) do
    %__MODULE__{schema: schema, action: action}
  end

  @doc false
  def allow(rule, opts) do
    if [] in rule.forbid do
      rule
    else
      Map.update(rule, :allow, [opts], &[opts | &1])
    end
  end

  @doc false
  def forbid(rule, []), do: Map.merge(rule, %{allow: [], forbid: [[]]})
  def forbid(rule, opts), do: Map.update(rule, :forbid, [opts], &[opts | &1])
end
