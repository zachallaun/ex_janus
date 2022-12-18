defmodule Janus.MixProject do
  use Mix.Project

  def project do
    [
      app: :janus,
      version: "0.1.0",
      elixir: "~> 1.14",
      elixirc_paths: elixirc_paths(Mix.env()),
      start_permanent: Mix.env() == :prod,
      deps: deps(),
      aliases: aliases(),
      preferred_cli_env: [
        "ecto.setup": :test,
        "ecto.gen.migration": :test,
        "ecto.migrate": :test,
        "ecto.rollback": :test,
        "ecto.create": :test
      ]
    ]
  end

  # Run "mix help compile.app" to learn about applications.
  def application do
    [
      extra_applications: [:logger]
    ]
  end

  # Run "mix help deps" to learn about dependencies.
  defp deps do
    [
      {:ecto, github: "elixir-ecto/ecto", override: true},
      {:ecto_sql, "~> 3.9", only: [:test, :dev]},
      {:postgrex, "~> 0.16", only: :test},
      {:jason, "~> 1.4", only: :test}
    ]
  end

  defp elixirc_paths(:test), do: ["lib", "test/support"]
  defp elixirc_paths(_), do: ["lib"]

  defp aliases do
    [
      "ecto.setup": [
        "ecto.drop",
        "ecto.create",
        "ecto.migrate --migrations-path test/support/janus_test/migrations"
      ]
    ]
  end
end
