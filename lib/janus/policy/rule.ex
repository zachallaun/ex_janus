defmodule Janus.Policy.Rule do
  @moduledoc """
  Defines a rule for an individual schema and action.
  """

  @type t :: %__MODULE__{
          schema: Janus.schema_module(),
          action: Janus.action(),
          allow: [keyword() | boolean()],
          deny: [keyword() | boolean()]
        }

  defstruct [
    :schema,
    :action,
    allow: [],
    deny: []
  ]

  @valid_options [:where, :where_not, :or_where]

  @doc false
  def new(schema, action) do
    %__MODULE__{schema: schema, action: action}
  end

  @doc false
  def allow(rule, opts) do
    opts = parse_opts!(opts)

    if [] in rule.deny do
      rule
    else
      Map.update(rule, :allow, [opts], &[opts | &1])
    end
  end

  @doc false
  def deny(rule, []), do: Map.merge(rule, %{allow: [], deny: [[]]})

  def deny(rule, opts) do
    opts = parse_opts!(opts)

    Map.update(rule, :deny, [opts], &[opts | &1])
  end

  defp parse_opts!(opts) do
    with {:keyword, true} <- {:keyword, Keyword.keyword?(opts)},
         [] <- opts |> Keyword.keys() |> Enum.uniq() |> Kernel.--(@valid_options) do
      combine(opts)
    else
      {:keyword, false} -> invalid_opts!(opts)
      opts -> invalid_opts!(opts)
    end
  end

  defp invalid_opts!(value) do
    raise ArgumentError, "invalid options passed to `allow` or `deny`: `#{inspect(value)}`"
  end

  defp combine(opts, acc \\ [])

  defp combine([{:or_where, or_clause} | opts], acc) do
    combine(opts, [{:or, {:where, or_clause}, acc}])
  end

  defp combine([clause | opts], acc) do
    combine(opts, [clause | acc])
  end

  defp combine([], acc), do: Enum.reverse(acc)
end
