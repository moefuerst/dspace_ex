defmodule DSpace.Api.MetadataTest do
  use ExUnit.Case, async: true
  use ExUnitProperties

  import StreamData
  import TestHelper, only: [parse_fixture: 1]

  alias DSpace.Api.Metadata

  doctest Metadata

  @metadata_key "dc.title"
  @bullshit_value Metadata.placeholder_value()
  @valid_languages ["en", "en_US", "de", "fr", "it", "es", "se"]
  @valid_confidence_levels [-1, 0, 100, 200, 300, 400, 500, 600]

  describe "Metadata normalization" do
    @doc """
    Property-based test for DSpace metadata normalization

    Demonstrates that metadata normalization:
    * Removes bullshit placeholder values
    * Removes empty/nil optional properties
    * Handles place values correctly (removes place: 0 when single value)
    * Maintains correct structure and required fields
    """
    @tag property: true
    test "normalizes metadata by filtering bullshit values and empty props", %{
      property: true
    } do
      check all(
              values <- list_of(metadata_value(), min_length: 2)
              # max_runs: 100
            ) do
        metadata = setup_test_metadata(values)

        normalized = Metadata.normalize(metadata)

        assert_bullshit_removal(metadata, normalized)
        assert_value_properties(normalized)
        assert_place_handling(metadata, normalized)
        assert_overall_structure(normalized)
      end
    end

    @doc """
    Tests metadata normalization with real-world data from fixture
    """
    test "normalizes metadata from real-world item fixture" do
      item = parse_fixture("get_item.json")
      original_metadata = item["metadata"]

      normalized = Metadata.normalize(original_metadata)

      assert is_map(normalized), "Normalized result should be a map"
      assert map_size(normalized) > 0, "Normalized metadata should not be empty"

      Enum.each(normalized, fn {key, _} ->
        if Map.has_key?(original_metadata, key) do
          assert_bullshit_removal(original_metadata, normalized, key)
          assert_value_properties(normalized, key)
          assert_place_handling(original_metadata, normalized, key)
        end
      end)

      assert_overall_structure(normalized)
    end

    test "handles edge cases" do
      assert %{} = Metadata.normalize(nil)
      assert %{} = Metadata.normalize(%{})
      assert %{} = Metadata.normalize("not a map")
    end

    test "normalize_with_type/1 extracts entity type correctly" do
      # Entity type
      metadata_with_type = %{
        "dc.title" => [%{"value" => "Test Title", "place" => 0}],
        "dspace.entity.type" => [%{"value" => "Publication", "place" => 0}]
      }

      {_normalized, type} = Metadata.normalize_with_type(metadata_with_type)
      assert type == "Publication", "The entity type should be extracted"

      # No entity type
      metadata_no_type = %{"dc.title" => [%{"value" => "Title Only", "place" => 0}]}
      {_, type} = Metadata.normalize_with_type(metadata_no_type)
      assert is_nil(type), "Type should be nil when no entity type is present"

      # Multiple entity types - take first
      metadata_multiple_types = %{
        "dspace.entity.type" => [
          %{"value" => "Publication", "place" => 0},
          %{"value" => "Dataset", "place" => 1}
        ]
      }

      {_, type} = Metadata.normalize_with_type(metadata_multiple_types)

      assert type == "Publication",
             "Should extract the first entity type when multiple are present"
    end
  end

  # Private Helpers

  defp assert_bullshit_removal(metadata, normalized, key \\ @metadata_key) do
    input_values = metadata[key]
    normalized_values = normalized[key]

    has_bullshit = has_bullshit_value?(input_values)

    if has_bullshit do
      assert no_bullshit_values?(normalized_values),
             "Bullshit value was not removed from normalized metadata"

      assert length(normalized_values) < length(input_values),
             "Normalized metadata should have fewer values when bullshit was removed"
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

  defp assert_value_properties(normalized, key \\ @metadata_key) do
    normalized_values = normalized[key]

    # Verify each normalized Metadata value and its props
    Enum.each(normalized_values, fn normalized_value ->
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
                 "Default confidence value of -1 not removed by normalization"

        # All other fields
        {k, v} ->
          refute is_nil(v),
                 "Field #{k} cannot have nil value if present"

          refute v == "",
                 "Field #{k} cannot have empty string value if present"
      end)
    end)
  end

  defp assert_place_handling(metadata, normalized, key \\ @metadata_key) do
    input_values = metadata[key]
    normalized_values = normalized[key]

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
      "value" =>
        one_of([
          string(:alphanumeric, min_length: 5, max_length: 50),
          constant(" "),
          constant("\t\n\r"),
          string(:printable, min_length: 1)
        ]),
      "authority" =>
        one_of([
          string(:alphanumeric, min_length: 36, max_length: 50),
          constant(nil)
        ]),
      "confidence" => one_of(Enum.map(@valid_confidence_levels, &constant/1)),
      "place" => integer(0..100),
      "language" =>
        one_of([
          member_of(@valid_languages),
          constant(""),
          constant(nil)
        ]),
      "securityLevel" =>
        one_of([
          constant(0),
          constant(1),
          constant(2),
          constant(nil)
        ])
    })
  end
end
