defmodule DSpace.Api.MetadataTest do
  use ExUnit.Case, async: true
  use ExUnitProperties

  import StreamData

  doctest DSpace.Api.Metadata

  @metadata_key "dc.title"
  @bullshit_value "#PLACEHOLDER_PARENT_METADATA_VALUE#"
  @valid_languages ["en", "en_US", "de", "fr", "it", "es", "se"]
  @valid_confidence_levels [-1, 0, 100, 200, 300, 400, 500, 600]

  @doc """
  Tests that metadata normalization:
  - Removes bullshit placeholder values
  - Removes empty/nil optional properties
  - Handles place values correctly (removes place: 0 when single value)
  - Maintains correct structure and required fields
  """
  @tag property: true
  test "normalizes DSpace metadata by filtering bullshit values and empty props", %{
    property: true
  } do
    check all(
            values <- list_of(metadata_value(), min_length: 2)
            # max_runs: 2
          ) do
      metadata = setup_test_metadata(values)
      # IO.puts("\nTest run with:")
      # IO.inspect(metadata, label: "Input metadata", pretty: true)

      normalized = DSpace.Api.Metadata.normalize(metadata)
      # IO.inspect(normalized, label: "Normalized output", pretty: true)

      assert_bullshit_removal(metadata, normalized)
      assert_value_properties(normalized)
      assert_place_handling(metadata, normalized)
      assert_overall_structure(normalized)
    end
  end

  # Private Helpers

  defp assert_bullshit_removal(metadata, normalized) do
    input_values = metadata[@metadata_key]
    normalized_values = normalized[@metadata_key]

    has_bullshit = has_bullshit_value?(input_values)

    if has_bullshit do
      assert no_bullshit_values?(normalized_values),
             "Bullshit value was not removed from normalized metadata"

      assert length(normalized_values) == length(input_values) - 1,
             "Normalized metadata should have one less value when bullshit was removed"
    else
      assert length(normalized_values) == length(input_values),
             "Normalized metadata should have same number of values when no bullshit present"
    end
  end

  defp has_bullshit_value?(values) do
    Enum.any?(values, &match?(%{"value" => @bullshit_value}, &1))
  end

  defp no_bullshit_values?(values) do
    not Enum.any?(values, &match?(%{value: @bullshit_value}, &1))
  end

  defp assert_value_properties(normalized) do
    normalized_values = normalized[@metadata_key]

    # Verify each normalized Metadata value and its props
    Enum.each(normalized_values, fn normalized_value ->
      # Must ALWAYS have a value
      assert Map.has_key?(normalized_value, :value),
             "Normalized metadata value must have a :value field"

      refute normalized_value.value == "",
             "Normalized metadata value cannot be an empty string"

      refute is_nil(normalized_value.value),
             "Normalized metadata value cannot be nil"

      # All fields must have non-empty values if present
      Enum.each(normalized_value, fn
        # Special case for confidence where we remove the default
        {:confidence, v} ->
          refute v == -1,
                 "Default confidence value of -1 should have been removed"

        # All other fields
        {k, v} ->
          refute is_nil(v),
                 "Field #{k} cannot have nil value if present"

          refute v == "",
                 "Field #{k} cannot have empty string value if present"
      end)
    end)
  end

  defp assert_place_handling(metadata, normalized) do
    input_values = metadata[@metadata_key]
    normalized_values = normalized[@metadata_key]

    # Place removal
    if length(normalized_values) == 1 and match?([%{"place" => 0}], input_values) do
      refute Map.has_key?(hd(normalized_values), :place),
             "Place field should be removed when it's the only value and place is 0"
    else
      assert Enum.all?(normalized_values, &Map.has_key?(&1, :place)),
             "Place field must be present when there are multiple values or place is not 0"
    end
  end

  defp assert_overall_structure(normalized) do
    if map_size(normalized) > 0 do
      assert Enum.all?(normalized, fn {_, vals} -> is_list(vals) end),
             "Metadata values must be stored in lists"

      assert Enum.all?(normalized, fn {_, vals} -> Enum.all?(vals, &is_map/1) end),
             "Each metadata value must be a map"

      assert Enum.all?(normalized, fn {_, vals} ->
               Enum.all?(vals, &Map.has_key?(&1, :value))
             end),
             "Every metadata must have a :value field"
    end
  end

  defp setup_test_metadata(values) do
    %{@metadata_key => maybe_add_bullshit(values)}
  end

  defp maybe_add_bullshit(values) do
    bullshit = %{
      "value" => @bullshit_value,
      "language" => nil,
      "authority" => nil,
      "confidence" => -1,
      "place" => length(values)
    }

    if :rand.uniform() > 0.5, do: values ++ [bullshit], else: values
  end

  defp metadata_value do
    fixed_map(%{
      "value" => string(:alphanumeric, min_length: 5, max_length: 50),
      "authority" =>
        one_of([string(:alphanumeric, min_length: 36, max_length: 50), constant(nil)]),
      "confidence" => one_of(Enum.map(@valid_confidence_levels, &constant/1)),
      "place" => integer(-1..100),
      "language" => one_of([constant(nil), constant(""), member_of(@valid_languages)])
    })
  end
end
