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
      test_pattern: "*_test.exs"
    ]
  end

  def application do
    [
      extra_applications: [:logger, :crypto],
      mod: {Laravex.Application, []}
    ]
  end

  defp elixirc_paths(:test), do: ["lib", "app", "bootstrap", "routes", "database", "tests"]
  defp elixirc_paths(_), do: ["lib", "app", "bootstrap", "routes", "database"]

  defp deps do
    []
  end
end

