defmodule DSpace.Api.Metadata.Schema do
  @moduledoc """
  Defines and validates the DSpace API metadata schema.

  Provides runtime validation of metadata values according to DSpace's constraints.
  """
  @schema NimbleOptions.new!(
            key: [
              type: :string,
              required: true
            ],
            values: [
              type: {:list, :map},
              required: true,
              keys: [
                value: [
                  type: :string,
                  required: true,
                  doc: "The metadata value content"
                ],
                language: [
                  type: :string,
                  doc: "Language code"
                ],
                authority: [
                  type: :string,
                  doc: "Authority key (UUID or other ID)"
                ],
                confidence: [
                  type: {:in, [-1, 0, 100, 200, 300, 400, 500, 600]},
                  default: -1,
                  doc: "Authority confidence level"
                ],
                place: [
                  type: :non_neg_integer,
                  doc: "Position in multi-value fields"
                ],
                # sic! camelcase
                securityLevel: [
                  type: {:in, [0, 1, 2]},
                  doc: "Access restriction level"
                ]
              ]
            ]
          )

  # Public API

  @doc "Metadata Schema:\n#{NimbleOptions.docs(@schema)}"
  @spec schema() :: NimbleOptions.t() | NimbleOptions.ValidationError.t()
  def schema, do: @schema

  @doc """
  Validates a metadata map against the schema.

  ## Examples

  iex> Schema.validate(%{
  ...>   key: "dc.title",
  ...>   values: [%{value: "Test Title", language: "en"}]
  ...> })
  {:ok, %{key: "dc.title", values: [%{value: "Test Title", language: "en", confidence: -1}]}}

  iex> Schema.validate(%{key: "dc.title", values: [%{language: "en"}]})
  {:error, "required :value option not found, received options: [:language]"}
  """
  @spec validate(map()) :: {:ok, map()} | {:error, NimbleOptions.ValidationError.t()}
  def validate(metadata) when is_map(metadata) do
    NimbleOptions.validate(metadata, @schema)
  end

  @spec validate!(map()) :: map() | NimbleOptions.ValidationError.t()
  def validate!(metadata) when is_map(metadata) do
    NimbleOptions.validate!(metadata, @schema)
  end
end
