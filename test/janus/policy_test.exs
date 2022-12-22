defmodule Janus.PolicyTest do
  use Janus.DataCase

  import Janus.Policy
  alias Janus.Authorization, as: Auth

  describe "allow/4 and forbid/4" do
    test "raises on unknown conditions" do
      message = "invalid options passed to `allow` or `forbid`: `[:foo]`"

      assert_raise ArgumentError, message, fn ->
        allow(%Janus.Policy{}, :read, Thread, foo: :bar)
      end

      assert_raise ArgumentError, message, fn ->
        allow(%Janus.Policy{}, :read, Thread, where: [archived: false], foo: :bar)
      end

      assert_raise ArgumentError, message, fn ->
        allow(%Janus.Policy{}, :read, Thread, [:foo])
      end
    end

    test "should accept a list of actions" do
      policy =
        %Janus.Policy{}
        |> allow([:read, :create], Thread)
        |> forbid([:read, :edit], Thread, where: [title: "forbidden"])

      %{id: thread_id} = thread = thread_fixture()

      assert {:ok, ^thread} = Auth.authorize(thread, :read, policy)
      assert {:ok, _thread} = Auth.authorize(%Thread{}, :create, policy)

      assert [%Thread{id: ^thread_id}] =
               Auth.filter_authorized(Thread, :read, policy) |> Repo.all()

      forbidden = thread_fixture(%{title: "forbidden"})

      assert :error = Auth.authorize(forbidden, :read, policy)
      assert :error = Auth.authorize(forbidden, :edit, policy)

      assert [%Thread{id: ^thread_id}] =
               Auth.filter_authorized(Thread, :read, policy) |> Repo.all()
    end

    test "should combine multiple option clauses as a logical-and" do
      [%{id: t1_id} = t1, %{id: t2_id} = t2] = [thread_fixture(), thread_fixture()]

      p1 =
        %Janus.Policy{}
        |> allow(:edit, Thread, where: [archived: false], where: [creator_id: t1.creator_id])

      assert {:ok, ^t1} = Auth.authorize(t1, :edit, p1)
      assert :error = Auth.authorize(t2, :edit, p1)
      assert [%{id: ^t1_id}] = Auth.filter_authorized(Thread, :edit, p1) |> Repo.all()

      p2 =
        %Janus.Policy{}
        |> allow(:edit, Thread, where: [archived: false], where_not: [creator_id: t1.creator_id])

      assert :error = Auth.authorize(t1, :edit, p2)
      assert {:ok, ^t2} = Auth.authorize(t2, :edit, p2)
      assert [%{id: ^t2_id}] = Auth.filter_authorized(Thread, :edit, p2) |> Repo.all()
    end
  end
end
