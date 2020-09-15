defmodule Poker.MixProject do
  use Mix.Project

  def project do
    [
      app: :poker,
      version: "0.1.0",
      elixir: "~> 1.10",
      start_permanent: Mix.env() == :prod,
      deps: deps(),

      preferred_cli_env: [espec: :test],
      test_coverage: [tool: Coverex.Task],
    ]
  end

  def application do
    [
      mod: {Poker.Application, []},
      extra_applications: [:logger],
    ]
  end

  defp deps do
    [
      {:cowboy, "~> 2.0"},
      {:jason, "~> 1.0"},
      {:jsonrfc, "~> 0.0"},
      {:plug_cowboy, "~> 2.0"},

      {:coverex, "~> 1.0", only: :test},
      {:espec, "~> 1.0", only: :test},
      {:ex_doc, "~> 0.22", only: :dev, runtime: false},
      {:dialyxir, "~> 1.0", only: :dev, runtime: false},
    ]
  end
end
