defmodule JanusTest do
  use ExUnit.Case
  doctest Janus

  test "greets the world" do
    assert Janus.hello() == :world
  end
end
