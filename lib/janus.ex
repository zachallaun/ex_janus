defmodule Janus do
  @external_resource "README.md"
  @moduledoc "README.md"
             |> File.read!()
             |> String.split("<!-- MDOC -->")
             |> Enum.fetch!(1)

  @type action :: atom()
  @type subject :: atom()
end
