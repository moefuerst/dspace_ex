defmodule DSpace.Api.ResponseTest do
  use ExUnit.Case, async: true

  alias DSpace.Api.Error
  alias DSpace.Api.Response

  describe "normalize/1" do
    test "passes through successful responses" do
      successful_response = {:ok, %{status: 200, body: %{"data" => "value"}}}

      assert successful_response == Response.normalize(successful_response),
             "Expected successful response to pass through unchanged"
    end

    test "transforms error responses to structured Error types" do
      error_response = {:ok, %{status: 404, body: %{"message" => "Not found"}}}

      assert {:error, %Error{}} = Response.normalize(error_response),
             "Expected error response to be transformed to Error struct"

      {:error, error} = Response.normalize(error_response)

      assert error.type == :not_found,
             "Expected error type to be :not_found for 404 response"

      assert error.message == "Not found",
             "Expected error message to be parsed from response body"
    end

    test "handles timeout errors" do
      timeout_error = {:error, %{reason: :timeout}}

      assert {:error, %Error{}} = Response.normalize(timeout_error),
             "Expected timeout error to be transformed to Error struct"

      {:error, error} = Response.normalize(timeout_error)

      assert error.type == :api_timeout,
             "Expected error type to be :api_timeout for timeout error"
    end

    test "handles connection errors" do
      conn_error = {:error, %{reason: :econnrefused}}

      assert {:error, %Error{}} = Response.normalize(conn_error),
             "Expected connection error to be transformed to Error struct"

      {:error, error} = Response.normalize(conn_error)

      assert error.type == :api_connection,
             "Expected error type to be :api_connection for connection error"
    end

    # Bubble up other errors
    test "passes through ArgumentError" do
      error = {:error, %ArgumentError{message: "Invalid argument"}}

      assert error == Response.normalize(error),
             "Expected ArgumentError to pass through unchanged"
    end
  end

  # TODO: Test resource extraction (with fixtures)

  describe "extract_csrf/1" do
    test "extracts CSRF token from response headers" do
      response = %{
        headers: %{
          "dspace-xsrf-token" => "token123"
        }
      }

      assert Response.extract_csrf(response) == "token123",
             "Expected CSRF token to be extracted from headers"
    end

    test "returns nil when no CSRF token in headers" do
      response = %{headers: %{}}

      assert Response.extract_csrf(response) == nil,
             "Expected nil when no CSRF token in headers"
    end
  end

  describe "transform_resource and transform_collection" do
    test "transforms a single resource using provided function" do
      resource = %{"id" => "1", "name" => "Test"}
      transformer = fn r -> Map.put(r, "transformed", true) end

      transformed = Response.transform_resource(resource, transformer)

      assert transformed["transformed"] == true,
             "Expected resource to be transformed with the transformer function"
    end

    test "transforms multiple resources using provided function" do
      resources = [
        %{"id" => "1"},
        %{"id" => "2"}
      ]

      transformer = fn r -> Map.put(r, "transformed", true) end

      transformed = Response.transform_collection(resources, transformer)

      assert length(transformed) == 2,
             "Expected collection to maintain the same length after transformation"

      assert Enum.all?(transformed, fn r -> r["transformed"] == true end),
             "Expected all resources in collection to be transformed"
    end
  end
end
