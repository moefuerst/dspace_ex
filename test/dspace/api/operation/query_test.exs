defmodule DSpace.API.Operation.QueryTest do
  use ExUnit.Case, async: true

  alias DSpace.API
  alias DSpace.API.Operation
  alias DSpace.API.Operation.Query

  setup do
    client = %API{
      endpoint: "https://example.com/server",
      http_impl: {TestHelper.HTTP, []}
    }

    {:ok, client: client}
  end

  describe "version override integration" do
    test "applies version overrides during perform/3", %{client: client} do
      client = API.put_api_version(client, "7.5.0")

      operation =
        Query.new(
          path: "/api/test",
          version_overrides: [{">= 7.5.0", [http_method: :post]}]
        )

      result = Operation.perform(operation, client, [])

      assert_received {:http_request, options}
      assert options[:method] == :post
      assert {:ok, response} = result
      assert response == %{"response" => "ok"}
    end

    test "does not apply overrides when version doesn't match", %{client: client} do
      client = API.put_api_version(client, "7.4.0")

      operation =
        Query.new(
          path: "/api/test",
          version_overrides: [{">= 7.5.0", [http_method: :post]}]
        )

      result = Operation.perform(operation, client, [])

      assert_received {:http_request, options}
      refute options[:method] == :post
      assert {:ok, response} = result
      assert response == %{"response" => "ok"}
    end

    test "applies path override based on version", %{client: client} do
      client = API.put_api_version(client, "7.6.2")

      operation =
        Query.new(
          path: "/api/old/endpoint",
          version_overrides: [{">= 7.6.2", [path: "/api/new/endpoint"]}]
        )

      result = Operation.perform(operation, client, [])

      assert_received {:http_request, options}
      assert options[:url].path == "/server/api/new/endpoint"
      assert {:ok, response} = result
      assert response == %{"response" => "ok"}
    end

    test "applies headers override based on version", %{client: client} do
      client = API.put_api_version(client, "8.0.0")

      operation =
        Query.new(
          path: "/api/test",
          headers: %{"existing" => ["value"]},
          version_overrides: [
            {">= 8.0.0", [headers: %{"content-type" => ["application/vnd.dspace.v2+json"]}]}
          ]
        )

      result = Operation.perform(operation, client, [])

      assert_received {:http_request, options}
      assert options[:headers]["content-type"] == ["application/vnd.dspace.v2+json"]
      refute Map.has_key?(options[:headers], "existing")
      assert {:ok, response} = result
      assert response == %{"response" => "ok"}
    end
  end
end
