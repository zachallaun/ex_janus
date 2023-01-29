Code.require_file("../../mix_helper.exs", __DIR__)

defmodule Mix.Tasks.Janus.Gen.AuthzTest do
  use Janus.DataCase

  import MixHelper
  import Janus.Policy
  alias Mix.Tasks.Janus.Gen

  setup_all do
    project = "janus.gen.authz_test"

    tmp_dir =
      in_project(project, fn ->
        Gen.Authz.run(~w(--app JanusTest))
      end)

    on_exit(fn -> File.rm_rf!(tmp_dir) end)

    [[{policy, _}], [{authz, _}]] =
      for file <- ["authz/policy.ex", "authz.ex"] do
        [tmp_dir, project, "lib/janus_test", file]
        |> Path.join()
        |> Code.compile_file()
      end

    [authz_module: authz, policy_module: policy]
  end

  describe "mix janus.gen.authz" do
    setup do
      Mix.Task.clear()
      :ok
    end

    test "generates authz modules with defaults", config do
      in_tmp_project(config.test, fn ->
        Gen.Authz.run(~w())

        assert_file("lib/ex_janus/authz.ex", fn file ->
          assert file =~ "defmodule ExJanus.Authz do"
          assert file =~ "use Janus.Authorization"
        end)

        assert_file("lib/ex_janus/authz/policy.ex", fn file ->
          assert file =~ "defmodule ExJanus.Authz.Policy do"
          assert file =~ "use Janus.Policy"
        end)
      end)
    end

    test "generates authz modules with given names", config do
      in_tmp_project(config.test, fn ->
        Gen.Authz.run(~w(--app MyApp --authz MyAuthz --policy MyPolicy))

        assert_file("lib/my_app/my_authz.ex", fn file ->
          assert file =~ "defmodule MyApp.MyAuthz do"
          assert file =~ "use Janus.Authorization"
          assert file =~ "policy: MyApp.MyAuthz.MyPolicy"
        end)

        assert_file("lib/my_app/my_authz/my_policy.ex", fn file ->
          assert file =~ "defmodule MyApp.MyAuthz.MyPolicy do"
          assert file =~ "use Janus.Policy"
        end)
      end)
    end
  end

  describe "generated helpers" do
    setup do
      user = user_fixture()
      thread = thread_fixture(%{creator_id: user.id})

      policy =
        %Janus.Policy{}
        |> allow(Thread, [:insert, :update, :delete],
          where: [creator_id: user.id, archived: false]
        )

      [thread: thread, user: user, policy: policy]
    end

    test "validate_authorized/4 shouldn't add error if change is authorized", %{
      authz_module: module,
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
      authz_module: module,
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
      authz_module: module,
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
      authz_module: module,
      policy: policy,
      thread: thread
    } do
      denied =
        %{thread | archived: true}
        |> Thread.changeset(%{title: "new title"})
        |> module.validate_authorized(:update, policy, message: "custom message")

      assert [current_user: {"custom message", _}] = denied.errors
    end

    test "authorized_fetch_by/3", %{authz_module: module, policy: policy, thread: thread} do
      opts = [authorize: {:update, policy}]
      %{id: id} = thread
      %{id: t2_id} = thread_fixture()

      assert {:ok, %Thread{id: ^id}} = module.authorized_fetch_by(Thread, [id: id], opts)

      assert {:error, :not_authorized} = module.authorized_fetch_by(Thread, [id: t2_id], opts)

      assert {:ok, %Thread{id: ^t2_id}} =
               module.authorized_fetch_by(Thread, [id: t2_id], authorize: false)

      assert {:error, :not_found} = module.authorized_fetch_by(Thread, [id: 0], opts)
    end

    test "authorized_fetch_all/3", %{authz_module: module, policy: policy, thread: thread} do
      opts = [authorize: {:update, policy}]
      %{id: id} = thread
      _ = thread_fixture()

      assert {:ok, [%Thread{id: ^id, posts: %Ecto.Association.NotLoaded{}}]} =
               module.authorized_fetch_all(Thread, opts)

      assert {:ok, [%Thread{id: ^id, posts: []}]} =
               module.authorized_fetch_all(Thread, opts ++ [preload_authorized: :posts])
    end

    test "authorized_insert/3", %{authz_module: module, policy: policy, user: user} do
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

    test "authorized_update/3", %{authz_module: module, policy: policy, thread: thread} do
      opts = [authorize: {:update, policy}]
      thread2 = thread_fixture()

      assert {:ok, %Thread{}} =
               thread |> Thread.changeset(%{title: "new"}) |> module.authorized_update(opts)

      assert {:error, %Ecto.Changeset{errors: errors}} =
               thread2 |> Thread.changeset(%{title: "new"}) |> module.authorized_update(opts)

      assert [current_user: {"is not authorized to change this resource", []}] = errors
    end

    test "authorized_delete/3", %{authz_module: module, policy: policy, thread: thread} do
      opts = [authorize: {:delete, policy}]
      thread2 = thread_fixture()

      assert {:ok, %Thread{}} = module.authorized_delete(thread, opts)
      assert {:error, %Ecto.Changeset{errors: errors}} = module.authorized_delete(thread2, opts)
      assert [current_user: {"is not authorized to delete this resource", []}] = errors
    end
  end
end
