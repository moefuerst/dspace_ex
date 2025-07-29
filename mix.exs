# Copyright (C) 2025 The dspace-ex Project Contributors
# Copyright (C) 2025 Moritz F. Fürst
#
# dspace-ex is free software: you can redistribute it and/or modify
# it under the terms of the GNU Affero General Public License as
# published by the Free Software Foundation, either version 3 of
# the License, or (at your option) any later version.
#
# This program is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.
# See the GNU Affero General Public License for more details.
#
# You should have received a copy of the GNU Affero General Public License
# along with this program. If not, see <https://www.gnu.org/licenses/>.
defmodule DSpace.MixProject do
  use Mix.Project

  @version "0.0.1"
  @description "DSpace client library for Elixir"
  @source_url "https://github.com/moefuerst/dspace-ex"

  def project do
    [
      app: :dspace,
      version: @version,
      elixir: "~> 1.18",
      elixirc_paths: elixirc_paths(Mix.env()),
      start_permanent: Mix.env() == :prod,
      deps: deps(),
      description: @description,
      package: package(),
      docs: docs(),
      aliases: aliases(),
      dialyzer: dialyzer(),
      preferred_cli_env: preferred_cli_env(),
      source_url: @source_url
    ]
  end

  # Run "mix help compile.app" to learn about applications.
  def application do
    [
      extra_applications: [:logger]
    ]
  end

  # Specifies which paths to compile per environment.
  defp elixirc_paths(:test), do: ["lib", "test/support"]
  defp elixirc_paths(_), do: ["lib"]

  # Run "mix help deps" to learn about dependencies.
  defp deps do
    [
      {:nimble_options, "~> 1.1"},
      {:req, "~> 0.5", optional: true},

      # Dev and Test dependencies
      {:ex_doc, ">= 0.0.0", only: :dev, runtime: false},
      {:credo, "~> 1.7", only: [:dev, :test], runtime: false},
      {:styler, "~> 1.4", only: [:dev, :test], runtime: false},
      {:dialyxir, "~> 1.1", only: [:dev, :test], runtime: false},
      {:mix_audit, "~> 2.1", only: [:dev, :test], runtime: false},
      {:bypass, "~> 2.1", only: [:dev, :test]},
      {:stream_data, "~> 1.2", only: [:dev, :test]}
    ]
  end

  defp aliases do
    [
      check: [
        "format --check-formatted",
        "credo --strict",
        "dialyzer --quiet-with-result"
      ],
      "check.ci": [
        "format --check-formatted",
        "deps.unlock --check-unused",
        "hex.audit",
        "deps.audit",
        "credo --strict",
        "dialyzer --quiet-with-result"
      ],
      "test.ci": [
        "test --raise"
      ]
    ]
  end

  defp preferred_cli_env do
    [
      "check.ci": :test,
      "test.ci": :test
    ]
  end

  defp dialyzer do
    [
      ignore_warnings: ".dialyzer_ignore.exs",
      plt_core_path: "_build/#{Mix.env()}/plt",
      plt_file: {:no_warn, "_build/#{Mix.env()}/plt/dialyzer.plt"}
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
      licenses: ["AGPL-3.0-or-later"],
      maintainers: ["Moritz F. Fürst"],
      links: %{"GitHub" => @source_url}
    ]
  end
end
