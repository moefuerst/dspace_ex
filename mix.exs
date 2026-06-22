defmodule DSpace.MixProject do
  use Mix.Project

  @version "0.0.1"
  @description "DSpace client library for Elixir"
  @source_url "https://github.com/moefuerst/dspace_ex"

  def project do
    [
      app: :dspace,
      version: @version,
      elixir: "~> 1.18",
      elixirc_options: elixirc_options(),
      elixirc_paths: elixirc_paths(Mix.env()),
      start_permanent: Mix.env() == :prod,
      deps: deps(),
      description: @description,
      package: package(),
      docs: docs(),
      aliases: aliases(),
      dialyzer: dialyzer(),
      source_url: @source_url
    ]
  end

  def application do
    [
      extra_applications: [:logger]
    ]
  end

  def cli do
    [
      preferred_envs: [precommit: :test, check: :test, "test.ci": :test, dialyzer: :test]
    ]
  end

  defp elixirc_options do
    [
      no_warn_undefined: [Req]
    ]
  end

  # Specifies which paths to compile per environment.
  defp elixirc_paths(:test), do: ["lib", "test/support"]
  defp elixirc_paths(_), do: ["lib"]

  defp deps do
    [
      {:req, "~> 0.5 or ~> 1.0", optional: true},

      # Development and Testing
      {:ex_doc, ">= 0.0.0", only: :dev, runtime: false},
      {:credo, "~> 1.7", only: [:dev, :test], runtime: false},
      {:ex_slop, "~> 0.4", only: [:dev, :test], runtime: false},
      {:styler, "~> 1.4", only: [:dev, :test], runtime: false},
      {:dialyxir, "~> 1.1", only: [:dev, :test], runtime: false},
      {:muex, "~> 0.6.0", only: [:dev, :test], runtime: false},
      {:mix_audit, "~> 2.1", only: [:dev, :test], runtime: false},
      {:bypass, "~> 2.1", only: [:dev, :test]},
      {:stream_data, "~> 1.2", only: [:dev, :test]}
    ]
  end

  defp aliases do
    [
      precommit: [
        "compile --warnings-as-errors",
        "deps.unlock --unused",
        "format",
        "credo --strict",
        "dialyzer --quiet-with-result",
        "test"
      ],
      check: [
        "format --check-formatted",
        "credo --strict",
        "dialyzer --quiet-with-result",
        "deps.unlock --check-unused",
        "deps.audit",
        "hex.audit"
      ],
      "test.ci": [
        "test --raise",
        "muex --optimize --optimize-level conservative --fail-at 80"
      ]
    ]
  end

  defp dialyzer do
    [
      ignore_warnings: ".dialyzer_ignore.exs",
      plt_core_path: "_build/#{Mix.env()}/plt",
      plt_file: {:no_warn, "_build/#{Mix.env()}/plt/dialyzer.plt"},
      plt_add_apps: [:ex_unit]
    ]
  end

  defp docs do
    [
      main: "readme",
      source_ref: "v#{@version}",
      source_url: @source_url,
      extras: ["README.md", "LICENSE"]
    ]
  end

  defp package do
    [
      name: :dspace_ex,
      licenses: ["AGPL-3.0-only"],
      maintainers: ["Moritz F. Fürst"],
      source_url: @source_url,
      links: %{"GitHub" => @source_url}
    ]
  end
end
