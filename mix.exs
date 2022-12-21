defmodule Janus.MixProject do
  use Mix.Project

  @source_url "https://github.com/zachallaun/ex_janus"
  @version "0.1.0-dev"

  def project do
    [
      app: :janus,
      version: @version,
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
      ],

      # Hex
      description: "Authorization for Ecto schemas",
      package: package(),

      # Docs
      name: "Janus",
      docs: docs()
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
      {:ecto, "~> 3.9"},
      {:ecto_sql, "~> 3.9", only: [:test, :dev]},
      {:postgrex, "~> 0.16", only: :test},
      {:jason, "~> 1.4", only: :test},
      {:ex_doc, "0.29.1", only: :dev, runtime: false}
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

  defp package do
    [
      name: "ex_janus",
      licenses: ["MIT"],
      links: %{"GitHub" => @source_url}
    ]
  end

  defp docs do
    [
      main: "readme",
      source_url: @source_url,
      extra_section: "GUIDES",
      extras: [
        "README.md",
        "cheatsheets/defining_policies.cheatmd"
      ],
      groups_for_extras: [
        Cheatsheets: ~r/cheatsheets\/.?/
      ]
    ]
  end
end
