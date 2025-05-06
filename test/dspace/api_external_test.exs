defmodule DSpace.ApiExternalTest do
  use DSpace.ExternalCase

  test "can connect to DSpace API", %{endpoint: endpoint} do
    client = DSpace.ExternalCase.dspace_test_api()
    assert client.endpoint == endpoint

    case DSpace.Api.request(client, url: "/actuator/health", json: false) do
      {:ok, response} ->
        assert response.status in 200..299,
               "Expected a successful status code from health endpoint"

        assert is_map(response.body), "Expected a JSON response from health endpoint"

      {:error, error} ->
        flunk("Failed to connect to DSpace API: #{inspect(error)}")
    end
  end

  @tag :requires_auth
  test "can authenticate with DSpace API" do
    client = DSpace.ExternalCase.dspace_test_api(true)

    assert DSpace.Api.authenticated?(client),
           "Expected client to be authenticated with DSpace API"
  end
end
