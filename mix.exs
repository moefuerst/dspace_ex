# Copyright (C) 2025 The dspace-ex Project Contributors
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
defmodule Dspace.MixProject do
  use Mix.Project

  @version "0.0.1"
  @description "DSpace client library for Elixir"
  @source_url "https://github.com/moefuerst/dspace-ex"

  def project do
    [
      app: :dspace,
      version: @version,
      elixir: "~> 1.18",
      start_permanent: Mix.env() == :prod,
      description: @description,
      deps: deps(),
      package: package(),
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
      {:nimble_options, "~> 1.1"},
      {:bypass, "~> 2.1", only: [:dev, :test]},
      {:stream_data, "~> 0.6", only: [:dev, :test]},
      {:dialyxir, "~> 1.1", only: [:dev, :test], runtime: false},
      {:credo, "~> 1.7", only: [:dev, :test], runtime: false},
      {:ex_doc, ">= 0.19.0", only: :dev},
      {:req, "~> 0.5.0", optional: true}
    ]
  end

  defp dialyzer_config(:test),
    do: [
      plt_core_path: "_plts/",
      plt_file: {:no_warn, "_plts/dialyzer.plt"}
    ]

  defp dialyzer_config(_env), do: []

  defp package do
    [
      licenses: ["AGPL-3.0"],
      links: %{"GitHub" => @source_url}
    ]
  end
end
