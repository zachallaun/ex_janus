defmodule JanusTest do
  use Janus.DataCase
  import Ecto.Query
  import Janus.Policy

  describe "basic policy module" do
    defmodule ExamplePolicy do
      use Janus

      @impl true
      def policy_for(policy, _) do
        policy
        |> allow(:read, Thread)
      end
    end

    test "defines authorize/3" do
      thread = thread_fixture()
      assert {:ok, ^thread} = ExamplePolicy.authorize(thread, :read, :user)
    end

    test "defines any_authorized?/3" do
      assert ExamplePolicy.any_authorized?(Thread, :read, :user)
    end

    test "defines scope/3 accepting a first-argument schema" do
      _ = [thread_fixture(), thread_fixture(), thread_fixture()]
      query = ExamplePolicy.scope(Thread, :read, :user)

      assert %Ecto.Query{} = query
      assert [_, _, _] = Repo.all(query)
    end

    test "defines scope/3 accepting a first-argument query" do
      _ = [thread_fixture(), thread_fixture(), thread_fixture()]

      query =
        Thread
        |> limit(1)
        |> ExamplePolicy.scope(:read, :user)

      assert [_] = Repo.all(query)
    end
  end

  describe "policy module with hooks" do
    defmodule ExamplePolicyWithHooks do
      use Janus

      before_policy_for __MODULE__
      before_policy_for {__MODULE__, :wrap_if_1}
      before_policy_for {__MODULE__, :halt_if_2}
      before_policy_for {__MODULE__, :shouldnt_run_after_halt_if_2}
      before_policy_for {__MODULE__, :invalid_if_3}

      def before_policy_for(:default, policy, 0) do
        {:cont, policy, {:default, 0}}
      end

      def before_policy_for(:default, policy, actor), do: {:cont, policy, actor}

      def before_policy_for(:wrap_if_1, policy, 1) do
        {:cont, policy, {:wrapped, 1}}
      end

      def before_policy_for(:wrap_if_1, policy, actor), do: {:cont, policy, actor}

      def before_policy_for(:halt_if_2, policy, 2) do
        {:halt, policy}
      end

      def before_policy_for(:halt_if_2, policy, actor), do: {:cont, policy, actor}

      def before_policy_for(:shouldnt_run_after_halt_if_2, policy, 2) do
        send(self(), :shouldnt_run_after_halt_if_2)
        {:cont, policy, 2}
      end

      def before_policy_for(:shouldnt_run_after_halt_if_2, policy, actor) do
        {:cont, policy, actor}
      end

      def before_policy_for(:invalid_if_3, _policy, 3) do
        :invalid
      end

      def before_policy_for(:invalid_if_3, policy, actor), do: {:cont, policy, actor}

      @impl true
      def policy_for(policy, actor) do
        send(self(), {:policy_for, policy, actor})
        policy
      end
    end

    test "should run callback with :default if only module is given" do
      assert %Janus.Policy{} = ExamplePolicyWithHooks.policy_for(0)
      assert_received {:policy_for, %Janus.Policy{}, {:default, 0}}
    end

    test "should continue with modified policy/actor if :cont tuple returned" do
      assert %Janus.Policy{} = ExamplePolicyWithHooks.policy_for(1)
      assert_received {:policy_for, %Janus.Policy{}, {:wrapped, 1}}
    end

    test "shouldn't run later hooks or policy_for if :halt tuple returned" do
      assert %Janus.Policy{} = ExamplePolicyWithHooks.policy_for(2)
      refute_received :shouldnt_run_after_halt_if_2
      refute_received {:policy_for, _, _}
    end

    test "raises on invalid return from hook" do
      message = ~r"invalid return from hook `"

      assert_raise(ArgumentError, message, fn ->
        ExamplePolicyWithHooks.policy_for(3)
      end)
    end
  end
end
