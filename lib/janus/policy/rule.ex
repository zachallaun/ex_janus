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

  @valid_options [:where, :where_not]

  @doc false
  def new(schema, action) do
    %__MODULE__{schema: schema, action: action}
  end

  @doc false
  def allow(rule, opts) do
    opts = parse_opts!(opts)

    if [] in rule.forbid do
      rule
    else
      Map.update(rule, :allow, [opts], &[opts | &1])
    end
  end

  @doc false
  def forbid(rule, []), do: Map.merge(rule, %{allow: [], forbid: [[]]})

  def forbid(rule, opts) do
    opts = parse_opts!(opts)

    Map.update(rule, :forbid, [opts], &[opts | &1])
  end

  defp parse_opts!(opts) do
    with {:keyword, true} <- {:keyword, Keyword.keyword?(opts)},
         [] <- opts |> Keyword.keys() |> Enum.uniq() |> Kernel.--(@valid_options) do
      opts
    else
      {:keyword, false} -> invalid_opts!(opts)
      opts -> invalid_opts!(opts)
    end
  end

  defp invalid_opts!(value) do
    raise ArgumentError, "invalid options passed to `allow` or `forbid`: `#{inspect(value)}`"
  end
end
