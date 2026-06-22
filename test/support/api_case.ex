defmodule DSpace.API.Case do
  @moduledoc """
  Defines the setup for API tests that use Bypass.
  """

  use ExUnit.CaseTemplate

  using do
    quote do
      import DSpace.API.Case
      import TestHelper, only: [respond_with_json: 3, load_fixture: 1, parse_fixture: 1]

      alias DSpace.API

      setup do
        bypass = Bypass.open()

        api = %API{
          endpoint: url(bypass),
          csrf_token: "abc123",
          # Disable retry to fail fast in all tests
          http_impl: {DSpace.API.HTTP.Req, [retry: false]}
        }

        {:ok, bypass: bypass, api: api}
      end

      def url(bypass), do: "http://localhost:#{bypass.port}"
    end
  end

  @doc """
  Asserts that a core API resource has the expected structure.
  """
  def assert_valid_dspace_resource(resource, expected_type, required_fields \\ []) do
    assert Map.has_key?(resource, "uuid")
    assert Map.has_key?(resource, "type")
    assert resource["type"] == expected_type

    if Map.has_key?(resource, "_links") do
      assert is_map(resource["_links"])
    end

    Enum.each(required_fields, fn field ->
      assert Map.has_key?(resource, field), "Resource missing required field: #{field}"
    end)
  end

  @doc """
  Asserts that a paginated API response has the expected structure.
  """
  def assert_valid_paginated_response({items, metadata, next_url}) when is_list(items) do
    assert is_list(items)
    assert is_map(metadata)
    assert Map.has_key?(metadata, "page")
    assert is_binary(next_url) or is_nil(next_url)
  end

  @doc """
  Creates operations for update requests.
  """
  def test_update_operations(field, value) do
    [
      %{
        "op" => "replace",
        "path" => "/metadata/#{field}/0/value",
        "value" => %{"value" => value}
      }
    ]
  end
end
