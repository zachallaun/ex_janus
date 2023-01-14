defmodule JanusTest do
  use Janus.DataCase
  import Ecto.Query
  import Janus.Policy

  describe "basic policy modules" do
    defmodule ExamplePolicy do
      use Janus

      @impl true
      def build_policy(policy, _) do
        policy
        |> allow(Thread, :read)
      end
    end

    test "define authorize/3" do
      thread = thread_fixture()
      assert {:ok, ^thread} = ExamplePolicy.authorize(thread, :read, :user)
    end

    test "define any_authorized?/3" do
      assert ExamplePolicy.any_authorized?(Thread, :read, :user)
    end

    test "define scope/3 accepting a first-argument schema" do
      _ = [thread_fixture(), thread_fixture(), thread_fixture()]
      query = ExamplePolicy.scope(Thread, :read, :user)

      assert %Ecto.Query{} = query
      assert [_, _, _] = Repo.all(query)
    end

    test "define scope/3 accepting a first-argument query" do
      _ = [thread_fixture(), thread_fixture(), thread_fixture()]

      query =
        Thread
        |> limit(1)
        |> ExamplePolicy.scope(:read, :user)

      assert [_] = Repo.all(query)
    end

    test "set default config options" do
      assert %Janus.Policy{
               config: %{
                 repo: nil,
                 load_associations: false
               }
             } = ExamplePolicy.build_policy(:user)
    end
  end

  describe "policy modules with config" do
    test "should accept options when defining the module" do
      [{module, _}] =
        quote do
          defmodule AllConfigOptions do
            use Janus,
              repo: Example.Repo,
              load_associations: true

            @impl true
            def build_policy(policy, _actor), do: policy
          end
        end
        |> Code.compile_quoted()

      assert %Janus.Policy{config: config} = module.build_policy(:user)

      assert %{repo: Example.Repo, load_associations: true} = config
    end

    test "raise when given an invalid key" do
      [{module, _}] =
        quote do
          defmodule InvalidOptions do
            use Janus, not_valid: true

            @impl true
            def build_policy(policy, _actor), do: policy
          end
        end
        |> Code.compile_quoted()

      assert_raise ArgumentError, ~r/unknown keys \[:not_valid\]/, fn ->
        module.build_policy(:user)
      end
    end
  end
end
