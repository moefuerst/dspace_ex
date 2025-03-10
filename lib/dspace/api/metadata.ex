defmodule DSpace.Api.Metadata do
  @moduledoc """
  Represents DSpace API metadata as a map of keys to metadata values.

  DSpace metadata consists of qualified key-value pairs, where each key has the actual value and additional properties.

  ## Example

  %{
    "dc.title" => [
      %{
        value: "Making reliable distributed systems in the presence of software errors",
        language: "en"
      }
    ],
    "dc.contributor.author" => [
      %{
        value: "Armstrong, Joe",
        authority: "550e8400-e29b-41d4-a716-446655440000",
        confidence: 600
      }
    ]
  }
  """

  @type t :: %{binary() => [%{binary() => binary() | integer() | nil}]}

  @bullshit "#PLACEHOLDER_PARENT_METADATA_VALUE#"

  # TODO: "Virtual" metadata *sigh*
  # @virtual_metadata_prefix "virtual::"

  # TODO: Deal with item reference resolution values
  # @item_reference_prefix "will be referenced::"

  # Public API

  @doc """
  Normalizes DSpace API metadata by:
  * Removing bullshit placeholder values
  * Removing empty metadata value props
  * Removing place: 0 when it's the only place prop

  ## Examples

  iex> DSpace.Api.Metadata.normalize(%{
  ...>   "dc.contributor.author" => [
  ...>     %{"value" => "Armstrong, Joe", "language" => nil, "authority" => "550e8400-e29b-41d4-a716-446655440000", "confidence" => 600, "place" => 0},
  ...>     %{"value" => "Armstrong, Neil", "language" => nil, "authority" => nil, "confidence" => -1, "place" => 1},
  ...>     %{"value" => "#PLACEHOLDER_PARENT_METADATA_VALUE#", "language" => nil, "authority" => nil, "confidence" => -1, "place" => 2}
  ...>   ]
  ...> })
  %{"dc.contributor.author" => [
      %{value: "Armstrong, Joe", authority: "550e8400-e29b-41d4-a716-446655440000", confidence: 600, place: 0},
      %{value: "Armstrong, Neil", place: 1}
    ]}

  iex> DSpace.Api.Metadata.normalize(%{
  ...>   "oairecerif.author.affiliation" => [
  ...>     %{"value" => "Telefonaktiebolaget LM Ericsson", "language" => nil, "authority" => nil, "confidence" => -1, "place" => 0},
  ...>     %{"value" => "#PLACEHOLDER_PARENT_METADATA_VALUE#", "language" => nil, "authority" => nil, "confidence" => -1, "place" => 1},
  ...>     %{"value" => "#PLACEHOLDER_PARENT_METADATA_VALUE#", "language" => nil, "authority" => nil, "confidence" => -1, "place" => 2}
  ...>   ]
  ...> })
  %{"oairecerif.author.affiliation" => [
      %{value: "Telefonaktiebolaget LM Ericsson"}
    ]}

  iex> DSpace.Api.Metadata.normalize(%{
  ...>   "dc.title" => [
  ...>     %{"value" => "Reliable systems", "language" => nil, "authority" => nil, "confidence" => nil, "place" => 0, "security_level" => nil,}]
  ...> })
  %{"dc.title" => [
      %{value: "Reliable systems"}
    ]}
  """
  @spec normalize(map()) :: t()
  def normalize(metadata) when is_map(metadata) do
    metadata
    |> Enum.map(&normalize_field/1)
    |> Enum.reject(&match?({_, []}, &1))
    |> Map.new()
  end

  def normalize(_), do: %{}

  @doc """
  Normalizes DSpace API metadata and extracts the DSpace-CRIS entity type. Returns both in a tuple.
  """
  @spec normalize_with_type(map()) :: {t(), binary() | nil}
  def normalize_with_type(metadata) when is_map(metadata) do
    normalized = normalize(metadata)

    {normalized,
     Map.get(normalized, "dspace.entity.type", [])
     |> List.first()
     |> then(& &1[:value])}
  end

  def normalize_with_type(_), do: {%{}, nil}

  # Private Helpers

  defp normalize_field({key, values}) do
    {key,
     values
     |> Enum.reject(fn %{"value" => value} -> value == @bullshit end)
     |> Enum.map(&normalize_value/1)
     |> maybe_strip_places()}
  end

  defp normalize_value(%{"value" => value} = raw) do
    %{value: value}
    |> maybe_add(:language, raw["language"])
    |> maybe_add(:authority, raw["authority"])
    |> maybe_add(:confidence, raw["confidence"])
    |> maybe_add(:place, raw["place"])
    |> maybe_add(:security_level, raw["security_level"])
  end

  defp maybe_add(map, :confidence, -1), do: map
  defp maybe_add(map, _key, nil), do: map
  defp maybe_add(map, _key, ""), do: map

  defp maybe_add(map, key, value), do: Map.put(map, key, value)

  defp maybe_strip_places([%{place: 0} = value]) do
    [Map.delete(value, :place)]
  end

  defp maybe_strip_places(values), do: values
end
