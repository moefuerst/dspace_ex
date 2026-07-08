defmodule DSpace.APIExternalTest do
  use DSpace.ExternalCase

  alias DSpace.API
  alias DSpace.API.Item
  alias DSpace.API.Monitor

  describe "basic connection" do
    test "connects to DSpace API", %{endpoint: endpoint} do
      client = dspace_test_api()
      assert client.endpoint == endpoint

      case API.request(Monitor.health(), client) do
        {:ok, response} ->
          status = Map.fetch!(response, "status")

          assert is_binary(status),
                 "Expected health status response from monitor endpoint, got #{inspect(response)}"

        {:error, error} ->
          flunk("Failed to connect to external DSpace API: #{inspect(error)}")
      end
    end
  end

  describe "basic credentialed connection with admin privileges" do
    @describetag :requires_auth
    setup do
      client = dspace_test_api(authenticate: true)

      {:ok, client: client}
    end

    test "authenticates with DSpace API", %{client: client} do
      assert API.authenticated?(client)
    end

    test "can access monitoring info", %{client: client} do
      info = API.request!(Monitor.info(), client)

      assert map_size(info) > 0,
             "Expected application information from monitor endpoint, got #{inspect(info)}"
    end

    test "lists items", %{client: client} do
      items =
        Item.list()
        |> API.stream!(client)
        |> Stream.take(3)

      for result <- items do
        assert Map.has_key?(result, "uuid")
        assert Map.fetch!(result, "type") == "item"
      end
    end
  end
end
