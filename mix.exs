defmodule Laravex.MixProject do
  use Mix.Project

  def project do
    [
      app: :laravex,
      version: "0.1.0",
      elixir: "~> 1.17",
      elixirc_paths: elixirc_paths(Mix.env()),
      start_permanent: Mix.env() == :prod,
      deps: deps(),
      test_paths: ["tests"],
      test_pattern: "*_test.exs",
      dialyzer: [
        plt_add_apps: [:mix, :ex_unit, :logger, :crypto, :inets, :ssl],
        flags: [:error_handling, :unmatched_returns]
      ]
    ]
  end

  def application do
    [
      extra_applications: [:logger, :crypto, :inets, :ssl],
      mod: {Laravex.Application, []}
    ]
  end

  defp elixirc_paths(:test), do: ["lib", "app", "bootstrap", "routes", "database", "tests"]
  defp elixirc_paths(_), do: ["lib", "app", "bootstrap", "routes", "database"]

  defp deps do
    [
      {:dialyxir, "~> 1.4", only: [:dev, :test], runtime: false}
    ]
  end
end

