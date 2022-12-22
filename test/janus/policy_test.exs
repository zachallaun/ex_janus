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
      assert :error = Auth.authorize(t2, :read, p1)
      assert [%Thread{id: ^t1_id}] = Auth.filter_authorized(Thread, :read, p1) |> Repo.all()

      # archived or not t2
      p2 =
        %Janus.Policy{}
        |> allow(:read, Thread)
        |> deny(:read, Thread, where: [archived: false], or_where: [id: t2_id])

      assert {:ok, ^t1} = Auth.authorize(t1, :read, p2)
      assert :error = Auth.authorize(t2, :read, p2)
      assert [%Thread{id: ^t1_id}] = Auth.filter_authorized(Thread, :read, p2) |> Repo.all()

      # not archived or t1
      p3 =
        %Janus.Policy{}
        |> allow(:read, Thread, where_not: [archived: true], or_where: [id: t1_id])

      assert {:ok, ^t1} = Auth.authorize(t1, :read, p3)
      assert :error = Auth.authorize(t2, :read, p3)
      assert [%Thread{id: ^t1_id}] = Auth.filter_authorized(Thread, :read, p3) |> Repo.all()

      # (not archived or t1) and not t1
      p4 =
        %Janus.Policy{}
        |> allow(:read, Thread,
          where: [archived: false],
          or_where: [id: t1_id],
          where_not: [id: t1_id]
        )

      assert :error = Auth.authorize(t1, :read, p4)
      assert :error = Auth.authorize(t2, :read, p4)
      assert [] = Auth.filter_authorized(Thread, :read, p4) |> Repo.all()

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
      assert [%Thread{}, %Thread{}] = Auth.filter_authorized(Thread, :read, p5) |> Repo.all()

      # (not archived and not t1) or t1
      p6 =
        %Janus.Policy{}
        |> allow(:read, Thread,
          where: [archived: false],
          where_not: [id: t1_id],
          or_where: [id: t1_id]
        )

      assert {:ok, ^t1} = Auth.authorize(t1, :read, p6)
      assert :error = Auth.authorize(t2, :read, p6)
      assert [%Thread{id: ^t1_id}] = Auth.filter_authorized(Thread, :read, p6) |> Repo.all()
    end

    test "should accept a list of actions" do
      policy =
        %Janus.Policy{}
        |> allow([:read, :create], Thread)
        |> deny([:read, :edit], Thread, where: [title: "denied"])

      %{id: thread_id} = thread = thread_fixture()

      assert {:ok, ^thread} = Auth.authorize(thread, :read, policy)
      assert {:ok, _thread} = Auth.authorize(%Thread{}, :create, policy)

      assert [%Thread{id: ^thread_id}] =
               Auth.filter_authorized(Thread, :read, policy) |> Repo.all()

      denied = thread_fixture(%{title: "denied"})

      assert :error = Auth.authorize(denied, :read, policy)
      assert :error = Auth.authorize(denied, :edit, policy)

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
