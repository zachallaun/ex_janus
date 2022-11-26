defmodule Janus.Policy.Rule do
  @moduledoc """
  Struct defining an authorization rule.

  See `Janus.Policy` for documentation on how to create and compose rules.
  """

  @type options :: keyword()

  @type t :: %__MODULE__{
          where: nil | [],
          where_not: nil | []
        }

  defstruct where: nil, where_not: nil
end

defmodule Janus.Policy do
  @moduledoc """
  TODO

  ## How policy rules combine

  Since policy rules are used to authorize an action on an individual resource and for
  data loading, it's best to consider how the rules apply to a set of resources, then the
  case of a single resource can be thought of as a set containing only that resource.

  The conceptual algorithm in terms of set operations:

  0. Let resources be the set of objects we're starting from.
  1. Filter resources to those matched by any `allow` rule.
  2. Take the difference of 1. and resources matched by any `forbid` rule.
  3. Take the union of 2. and resources matched by any `always_allow` rule.
  4. Take the difference of 3. and resources matched by any `always_forbid` rule.
  """

  alias Janus.Policy.Rule

  @type ruleset ::
          {
            allow :: [Rule.t()],
            forbid :: [Rule.t()],
            always_allow :: [Rule.t()],
            always_forbid :: [Rule.t()]
          }

  @type t :: %__MODULE__{
          subjects: %{Janus.subject() => [{Janus.action(), ruleset}, ...]}
        }

  defstruct subjects: %{}

  @callback policy_for(t, actor :: any()) :: t

  @spec allow(t, Janus.action(), Rule.options()) :: t
  def allow(policy, actor, opts) do
  end

  @spec forbid(t, Janus.action(), Rule.options()) :: t
  def forbid(policy, actor, opts) do
  end

  @spec always_allow(t, Janus.action(), Rule.options()) :: t
  def always_allow(policy, actor, opts) do
  end

  @spec always_forbid(t, Janus.action(), Rule.options()) :: t
  def always_forbid(policy, actor, opts) do
  end
end
