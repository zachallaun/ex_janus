Code.require_file("../../mix_helper.exs", __DIR__)

defmodule Mix.Tasks.Janus.Gen.PolicyTest do
  use ExUnit.Case
  import MixHelper
  alias Mix.Tasks.Janus.Gen

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
        assert file =~ "def policy_for\("
        assert file =~ "def load_and_authorize\("
        assert file =~ "def load_authorized\("
      end)
    end)
  end

  test "generates a policy module with the given name", config do
    in_tmp_project(config.test, fn ->
      Gen.Policy.run(~w(--module MyApp.Policy))

      assert_file("lib/ex_janus/policy.ex", fn file ->
        assert file =~ "defmodule MyApp.Policy do"
        assert file =~ "alias ExJanus.Repo"
        assert file =~ "def policy_for\("
        assert file =~ "def load_and_authorize\("
        assert file =~ "def load_authorized\("
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
