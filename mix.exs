defmodule Janus.MixProject do
  use Mix.Project

  @app :ex_janus
  @source_url "https://github.com/zachallaun/ex_janus"
  @version "0.1.0-dev"

  def project do
    [
      app: @app,
      version: @version,
      elixir: "~> 1.14",
      elixirc_paths: elixirc_paths(Mix.env()),
      start_permanent: Mix.env() == :prod,
      deps: deps(),
      aliases: aliases(),
      dialyzer: dialyzer(),
      test_coverage: [tool: ExCoveralls],
      preferred_cli_env: preferred_cli_env(),

      # Hex
      description: "Flexible and composable authorization for resources defined by Ecto schemas",
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

      # dev/test
      {:ex_doc, "0.29.1", only: :dev, runtime: false},
      {:excoveralls, "~> 0.15", only: :test},
      {:dialyxir, "~> 1.2", only: [:dev, :test], runtime: false},
      {:ecto_sql, "~> 3.9", only: [:dev, :test]},
      {:jason, "~> 1.4", only: [:dev, :test]},
      {:postgrex, "~> 0.16", only: :test}
    ]
  end

  defp elixirc_paths(:test), do: ["lib", "test/support"]
  defp elixirc_paths(_), do: ["lib"]

  defp aliases do
    [
      t: "coveralls",
      setup: [
        "ecto.drop",
        "ecto.create",
        "ecto.migrate --migrations-path test/support/janus_test/migrations"
      ]
    ]
  end

  defp preferred_cli_env do
    test_tasks = [
      :t,
      :setup,
      :coveralls,
      :"coveralls.detail",
      :"coveralls.post",
      :"coveralls.html",
      :"ecto.gen.migration",
      :"ecto.migrate",
      :"ecto.rollback",
      :"ecto.create"
    ]

    for task <- test_tasks, do: {task, :test}
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
        "guides/cheatsheet.cheatmd"
      ]
    ]
  end

  defp dialyzer do
    [
      plt_file: {:no_warn, "priv/plts/dialyzer.plt"},
      plt_add_apps: [:mix],
      flags: [
        :underspecs,
        :extra_return,
        :missing_return
      ]
    ]
  end
end
