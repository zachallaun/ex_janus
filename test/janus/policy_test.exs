defmodule Janus.PolicyTest do
  use Janus.DataCase

  import Janus.Policy
  alias Janus.Authorization, as: Auth

  describe "allow/4 and deny/4" do
    test "raises on unknown conditions" do
      message = "invalid options passed to `allow` or `deny`: `[:foo]`"

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

    test ":or_where combines with prior conditions" do
      [%{id: t1_id} = t1, %{id: t2_id} = t2] =
        for _ <- 1..2, do: thread_fixture(%{archived: true})

      # not archived or t1
      p1 =
        %Janus.Policy{}
        |> allow(:read, Thread, where: [archived: false], or_where: [id: t1_id])

      assert {:ok, ^t1} = Auth.authorize(t1, :read, p1)
      assert {:error, :not_authorized} = Auth.authorize(t2, :read, p1)
      assert [%Thread{id: ^t1_id}] = Auth.scope(Thread, :read, p1) |> Repo.all()

      # archived or not t2
      p2 =
        %Janus.Policy{}
        |> allow(:read, Thread)
        |> deny(:read, Thread, where: [archived: false], or_where: [id: t2_id])

      assert {:ok, ^t1} = Auth.authorize(t1, :read, p2)
      assert {:error, :not_authorized} = Auth.authorize(t2, :read, p2)
      assert [%Thread{id: ^t1_id}] = Auth.scope(Thread, :read, p2) |> Repo.all()

      # not archived or t1
      p3 =
        %Janus.Policy{}
        |> allow(:read, Thread, where_not: [archived: true], or_where: [id: t1_id])

      assert {:ok, ^t1} = Auth.authorize(t1, :read, p3)
      assert {:error, :not_authorized} = Auth.authorize(t2, :read, p3)
      assert [%Thread{id: ^t1_id}] = Auth.scope(Thread, :read, p3) |> Repo.all()

      # (not archived or t1) and not t1
      p4 =
        %Janus.Policy{}
        |> allow(:read, Thread,
          where: [archived: false],
          or_where: [id: t1_id],
          where_not: [id: t1_id]
        )

      assert {:error, :not_authorized} = Auth.authorize(t1, :read, p4)
      assert {:error, :not_authorized} = Auth.authorize(t2, :read, p4)
      assert [] = Auth.scope(Thread, :read, p4) |> Repo.all()

      # (not archived or t1) or t2
      p5 =
        %Janus.Policy{}
        |> allow(:read, Thread,
          where: [archived: false],
          or_where: [id: t1_id],
          or_where: [id: t2_id]
        )

      assert {:ok, ^t1} = Auth.authorize(t1, :read, p5)
      assert {:ok, ^t2} = Auth.authorize(t2, :read, p5)
      assert [%Thread{}, %Thread{}] = Auth.scope(Thread, :read, p5) |> Repo.all()

      # (not archived and not t1) or t1
      p6 =
        %Janus.Policy{}
        |> allow(:read, Thread,
          where: [archived: false],
          where_not: [id: t1_id],
          or_where: [id: t1_id]
        )

      assert {:ok, ^t1} = Auth.authorize(t1, :read, p6)
      assert {:error, :not_authorized} = Auth.authorize(t2, :read, p6)
      assert [%Thread{id: ^t1_id}] = Auth.scope(Thread, :read, p6) |> Repo.all()
    end

    test "should accept a list of actions" do
      policy =
        %Janus.Policy{}
        |> allow([:read, :create], Thread)
        |> deny([:read, :edit], Thread, where: [title: "denied"])

      %{id: thread_id} = thread = thread_fixture()

      assert {:ok, ^thread} = Auth.authorize(thread, :read, policy)
      assert {:ok, _thread} = Auth.authorize(%Thread{}, :create, policy)

      assert [%Thread{id: ^thread_id}] = Auth.scope(Thread, :read, policy) |> Repo.all()

      denied = thread_fixture(%{title: "denied"})

      assert {:error, :not_authorized} = Auth.authorize(denied, :read, policy)
      assert {:error, :not_authorized} = Auth.authorize(denied, :edit, policy)

      assert [%Thread{id: ^thread_id}] = Auth.scope(Thread, :read, policy) |> Repo.all()
    end

    test "should combine multiple option clauses as a logical-and" do
      [%{id: t1_id} = t1, %{id: t2_id} = t2] = [thread_fixture(), thread_fixture()]

      p1 =
        %Janus.Policy{}
        |> allow(:edit, Thread, where: [archived: false], where: [creator_id: t1.creator_id])

      assert {:ok, ^t1} = Auth.authorize(t1, :edit, p1)
      assert {:error, :not_authorized} = Auth.authorize(t2, :edit, p1)
      assert [%{id: ^t1_id}] = Auth.scope(Thread, :edit, p1) |> Repo.all()

      p2 =
        %Janus.Policy{}
        |> allow(:edit, Thread, where: [archived: false], where_not: [creator_id: t1.creator_id])

      assert {:error, :not_authorized} = Auth.authorize(t1, :edit, p2)
      assert {:ok, ^t2} = Auth.authorize(t2, :edit, p2)
      assert [%{id: ^t2_id}] = Auth.scope(Thread, :edit, p2) |> Repo.all()
    end
  end

  describe "hooks" do
    test "should be added with attach_hook/4" do
      policy =
        %Janus.Policy{}
        |> attach_hook(:my_hook_1, fn _, resource, _ -> {:cont, resource} end)
        |> attach_hook(:my_hook_2, fn _, resource, _ -> {:cont, resource} end)
        |> attach_hook(:my_hook_1, Thread, fn _, resource, _ -> {:cont, resource} end)
        |> attach_hook(:my_hook_2, Thread, fn _, resource, _ -> {:cont, resource} end)

      assert %{
               Thread => [my_hook_1: _, my_hook_2: _],
               all: [my_hook_1: _, my_hook_2: _]
             } = policy.hooks
    end

    test "should be removed with detach_hook/3" do
      policy =
        %Janus.Policy{}
        |> attach_hook(:my_hook_1, fn _, query, _ -> {:cont, query} end)
        |> attach_hook(:my_hook_2, fn _, query, _ -> {:cont, query} end)
        |> attach_hook(:my_hook_1, Thread, fn _, query, _ -> {:cont, query} end)
        |> attach_hook(:my_hook_2, Thread, fn _, query, _ -> {:cont, query} end)
        |> detach_hook(:my_hook_1)
        |> detach_hook(:my_hook_1, Thread)

      assert %{
               Thread => [my_hook_2: _],
               all: [my_hook_2: _]
             } = policy.hooks
    end

    test "should be added with attach_new_hook/4 if name doesn't exist for stage" do
      policy =
        %Janus.Policy{}
        |> attach_hook(:my_hook_1, fn _, resource, _ -> {:cont, resource} end)
        |> attach_new_hook(:my_hook_1, fn _, resource, _ -> {:cont, resource} end)
        |> attach_new_hook(:my_hook_2, fn _, resource, _ -> {:cont, resource} end)
        |> attach_hook(:my_hook_1, Thread, fn _, resource, _ -> {:cont, resource} end)
        |> attach_new_hook(:my_hook_1, Thread, fn _, resource, _ -> {:cont, resource} end)
        |> attach_new_hook(:my_hook_2, Thread, fn _, resource, _ -> {:cont, resource} end)

      assert %{
               Thread => [my_hook_1: _, my_hook_2: _],
               all: [my_hook_1: _, my_hook_2: _]
             } = policy.hooks
    end

    test "raise if attach_hook/5 uses an existing name" do
      message = "hook :my_hook for :all already exists"

      assert_raise ArgumentError, message, fn ->
        %Janus.Policy{}
        |> attach_hook(:my_hook, fn _, resource, _ -> {:cont, resource} end)
        |> attach_hook(:my_hook, fn _, resource, _ -> {:cont, resource} end)
      end

      message = "hook :my_hook for JanusTest.Schemas.Thread already exists"

      assert_raise ArgumentError, message, fn ->
        %Janus.Policy{}
        |> attach_hook(:my_hook, Thread, fn _, resource, _ -> {:cont, resource} end)
        |> attach_hook(:my_hook, Thread, fn _, resource, _ -> {:cont, resource} end)
      end
    end

    test "raise if attach_hook/5 passed an invalid hook" do
      message = ~r"received invalid hook :my_hook for :all"

      assert_raise ArgumentError, message, fn ->
        %Janus.Policy{}
        |> attach_hook(:my_hook, fn -> nil end)
      end

      assert_raise ArgumentError, message, fn ->
        %Janus.Policy{}
        |> attach_hook(:my_hook, :not_a_function)
      end

      message = ~r"received invalid hook :my_hook for JanusTest.Schemas.Thread"

      assert_raise ArgumentError, message, fn ->
        %Janus.Policy{}
        |> attach_hook(:my_hook, Thread, fn -> nil end)
      end

      assert_raise ArgumentError, message, fn ->
        %Janus.Policy{}
        |> attach_hook(:my_hook, Thread, :not_a_function)
      end
    end
  end
end
