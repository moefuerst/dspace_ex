defmodule Dspace.MixProject do
  use Mix.Project

  def project do
    [
      app: :dspace,
      version: "0.1.0",
      elixir: "~> 1.18",
      start_permanent: Mix.env() == :prod,
      deps: deps(),
      dialyzer: [ignore_warnings: ".dialyzer_ignore.exs"] ++ dialyzer_config(Mix.env())
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
      {:dialyxir, "~> 1.1", only: [:dev, :test], runtime: false}
    ]
  end

  defp dialyzer_config(:test),
    do: [
      plt_core_path: "_plts/",
      plt_file: {:no_warn, "_plts/dialyzer.plt"}
    ]

  defp dialyzer_config(_env), do: []
end
