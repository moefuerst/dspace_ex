defmodule DSpace.MixProject do
  use Mix.Project

  @version "0.1.0-alpha2"
  @description "DSpace client library for Elixir"
  @source_url "https://github.com/moefuerst/dspace_ex"

  def project do
    [
      app: :dspace_ex,
      name: :dspace_ex,
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
      {:muex, "~> 0.8.0", only: [:dev, :test], runtime: false},
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
        "hex.audit",
        "deps.unlock --check-unused",
        "deps.audit",
        "format --check-formatted",
        "credo --strict",
        "dialyzer --quiet-with-result"
      ],
      "test.ci": [
        "test --raise",
        "muex --optimize --optimize-level conservative --fail-at 80"
      ]
    ]
  end

  defp docs do
    [
      main: "readme",
      source_ref: "v#{@version}",
      source_url: @source_url,
      extras: extras(),
      groups_for_modules: groups_for_modules(),
      skip_undefined_reference_warnings_on: ["CHANGELOG.md"]
    ]
  end

  defp extras do
    [
      "README.md",
      "CHANGELOG.md",
      "LICENSE"
    ]
  end

  defp groups_for_modules do
    [
      Client: [
        DSpace.API,
        DSpace.API.Error,
        DSpace.API.HTTP.Error,
        DSpace.API.Metadata.Value,
        DSpace.API.Resource
      ],
      "Core Resources": [
        DSpace.API.Collection,
        DSpace.API.Community,
        DSpace.API.File,
        DSpace.API.Item,
        DSpace.API.User
      ],
      Access: [
        DSpace.API.Auth
      ],
      Search: [
        DSpace.API.Search,
        DSpace.API.PID
      ],
      Integrations: [
        DSpace.API.Source
      ],
      "Repository Management": [
        DSpace.API.File.FormatRegistry,
        DSpace.API.Metadata,
        DSpace.API.Monitor
      ],
      "Advanced Customization": [
        DSpace.API.HTTP,
        DSpace.API.HTTP.Req,
        DSpace.API.HTTP.Response,
        DSpace.API.Operation,
        DSpace.API.Operation.JSON,
        DSpace.API.Operation.Chain,
        DSpace.API.StreamBuilder,
        DSpace.API.Transform
      ]
    ]
  end

  defp dialyzer do
    [
      ignore_warnings: ".dialyzer_ignore.exs",
      plt_core_path: "priv/plts",
      plt_file: {:no_warn, "priv/plts/project.plt"},
      plt_add_apps: [:ex_unit]
    ]
  end

  defp package do
    [
      name: :dspace_ex,
      files: ~w(lib .formatter.exs mix.exs README* LICENSE* CHANGELOG*),
      maintainers: ["Moritz F. Fürst"],
      licenses: ["AGPL-3.0-only"],
      source_url: @source_url,
      links: %{
        "Changelog" => "#{@source_url}/blob/master/CHANGELOG.md",
        "GitHub" => @source_url
      }
    ]
  end
end
