Code.require_file("../../mix_helper.exs", __DIR__)

defmodule Mix.Tasks.Janus.Gen.PolicyTest do
  use Janus.DataCase

  import MixHelper
  import Janus.Policy
  alias Mix.Tasks.Janus.Gen

  setup_all do
    project = "janus.gen.policy_test"

    tmp_dir =
      in_project(project, fn ->
        Gen.Policy.run(~w(--module #{__MODULE__}.TestPolicy --app JanusTest --path lib/policy.ex))
      end)

    on_exit(fn -> File.rm_rf!(tmp_dir) end)

    [{module, _}] =
      [tmp_dir, project, "lib/policy.ex"]
      |> Path.join()
      |> Code.compile_file()

    [module: module]
  end

  describe "mix janus.gen.policy" do
    setup do
      Mix.Task.clear()
      :ok
    end

    test "invalid arguments", config do
      in_tmp_project(config.test, fn ->
        assert_raise Mix.Error, ~r/Module name `Janus.Policy` is already taken/, fn ->
          Gen.Policy.run(~w(--module Janus.Policy))
        end
      end)

      in_tmp_project(config.test, fn ->
        message = "Module name `policy` is invalid. Expected an alias, e.g. `MyApp.Policy`"

        assert_raise Mix.Error, message, fn ->
          Gen.Policy.run(~w(--module policy))
        end
      end)
    end

    test "generates a policy module based on app name", config do
      in_tmp_project(config.test, fn ->
        Gen.Policy.run(~w())

        assert_file("lib/ex_janus/policy.ex", fn file ->
          assert file =~ "defmodule ExJanus.Policy do"
          assert file =~ "alias ExJanus.Repo"
        end)
      end)
    end

    test "generates a policy module with the given name", config do
      in_tmp_project(config.test, fn ->
        Gen.Policy.run(~w(--module MyApp.Policy))

        assert_file("lib/ex_janus/policy.ex", fn file ->
          assert file =~ "defmodule MyApp.Policy do"
          assert file =~ "alias ExJanus.Repo"
        end)
      end)
    end

    test "generates a policy module at a custom path", config do
      in_tmp_project(config.test, fn ->
        Gen.Policy.run(~w(--module MyApp.Policy --path lib/myapp/policy.ex))

        assert_file("lib/myapp/policy.ex")
        refute_file("lib/ex_janus/policy.ex")
      end)
    end
  end

  describe "generated helpers" do
    setup do
      user = user_fixture()
      thread = thread_fixture(%{creator_id: user.id})

      policy =
        %Janus.Policy{}
        |> allow([:insert, :update, :delete], Thread,
          where: [creator_id: user.id, archived: false]
        )

      [thread: thread, user: user, policy: policy]
    end

    test "validate_authorized/4 shouldn't add error if change is authorized", %{
      module: module,
      policy: policy,
      thread: thread
    } do
      allowed =
        thread
        |> Thread.changeset(%{title: "new title"})
        |> module.validate_authorized(:update, policy)

      assert %Ecto.Changeset{valid?: true} = allowed
    end

    test "validate_authorized/4 should add error if action not allowed by policy", %{
      module: module,
      policy: policy,
      thread: thread
    } do
      denied =
        thread
        |> Thread.changeset(%{title: "new title"})
        |> module.validate_authorized(:super_update, policy)

      assert %Ecto.Changeset{valid?: false} = denied

      assert [current_user: {"is not authorized to change this resource", _}] = denied.errors
    end

    test "validate_authorized/4 should accept custom :error_key", %{
      module: module,
      policy: policy,
      thread: thread
    } do
      denied =
        %{thread | archived: true}
        |> Thread.changeset(%{title: "new title"})
        |> module.validate_authorized(:update, policy, error_key: :custom_key)

      assert [custom_key: {_, _}] = denied.errors
    end

    test "validate_authorized/4 should accept custom :message", %{
      module: module,
      policy: policy,
      thread: thread
    } do
      denied =
        %{thread | archived: true}
        |> Thread.changeset(%{title: "new title"})
        |> module.validate_authorized(:update, policy, message: "custom message")

      assert [current_user: {"custom message", _}] = denied.errors
    end

    test "authorized_fetch_by/3", %{module: module, policy: policy, thread: thread} do
      opts = [authorize: {:update, policy}]
      %{id: id} = thread
      %{id: t2_id} = thread_fixture()

      assert {:ok, %Thread{id: ^id}} = module.authorized_fetch_by(Thread, [id: id], opts)

      assert {:error, :not_authorized} = module.authorized_fetch_by(Thread, [id: t2_id], opts)

      assert {:ok, %Thread{id: ^t2_id}} =
               module.authorized_fetch_by(Thread, [id: t2_id], authorize: false)

      assert {:error, :not_found} = module.authorized_fetch_by(Thread, [id: 0], opts)
    end

    test "authorized_fetch_all/3", %{module: module, policy: policy, thread: thread} do
      opts = [authorize: {:update, policy}]
      %{id: id} = thread
      _ = thread_fixture()

      assert {:ok, [%Thread{id: ^id, posts: %Ecto.Association.NotLoaded{}}]} =
               module.authorized_fetch_all(Thread, opts)

      assert {:ok, [%Thread{id: ^id, posts: []}]} =
               module.authorized_fetch_all(Thread, opts ++ [preload_authorized: :posts])
    end

    test "authorized_insert/3", %{module: module, policy: policy, user: user} do
      opts = [authorize: {:insert, policy}]

      assert {:ok, %Thread{}} =
               %Thread{}
               |> Thread.changeset(%{creator_id: user.id, title: "title"})
               |> module.authorized_insert(opts)

      user2 = user_fixture()

      assert {:error, %Ecto.Changeset{errors: errors}} =
               %Thread{}
               |> Thread.changeset(%{creator_id: user2.id, title: "title"})
               |> module.authorized_insert(opts)

      assert [current_user: {"is not authorized to make these changes", []}] = errors
    end

    test "authorized_update/3", %{module: module, policy: policy, thread: thread} do
      opts = [authorize: {:update, policy}]
      thread2 = thread_fixture()

      assert {:ok, %Thread{}} =
               thread |> Thread.changeset(%{title: "new"}) |> module.authorized_update(opts)

      assert {:error, %Ecto.Changeset{errors: errors}} =
               thread2 |> Thread.changeset(%{title: "new"}) |> module.authorized_update(opts)

      assert [current_user: {"is not authorized to change this resource", []}] = errors
    end

    test "authorized_delete/3", %{module: module, policy: policy, thread: thread} do
      opts = [authorize: {:delete, policy}]
      thread2 = thread_fixture()

      assert {:ok, %Thread{}} = module.authorized_delete(thread, opts)
      assert {:error, %Ecto.Changeset{errors: errors}} = module.authorized_delete(thread2, opts)
      assert [current_user: {"is not authorized to delete this resource", []}] = errors
    end
  end
end
