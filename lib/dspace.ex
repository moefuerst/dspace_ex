defmodule DSpace do
  @moduledoc """
  DSpace provides a client library for interacting with with DSpace(-CRIS) 7+ repositories.

  ## Getting started
  To get started, create a new API client with the base URL of your DSpace server:

  ```elixir
  api = %DSpace.Api{
    base_url: "https://example.com/server",
    access_token: "your-access-token",
    csrf_token: "your-csrf-token"
  }

  # Alternatively use the `DSpace.Api.new/3` function
  api = DSpace.Api.new("https://example.com/server")

  # Include authentication tokens if you need them
  api = DSpace.Api.new("https://example.com/server", "your-access-token", "your-csrf-token")

  # Fetch an item by UUID
  {:ok, item} = DSpace.Api.new("https://example.com/server")
                |> DSpace.Api.Item.fetch("01234567-89ab-cdef-0123-456789abcdef")

  # Make a request to any endpoint where no higher-level abstraction is available
  {:ok, response} = DSpace.Api.new("https://example.com/server", "your-access-token")
                   |> DSpace.Api.request(method: :get, url: "/actuator/info")
  ```

  ## Bring your own HTTP client
  By default, DSpace uses Req as the HTTP client for interacting with the DSpace REST API. If your project uses another client, you can implement the `DSpace.Api.HttpClient` contract and pass the implementation as an option to the `DSpace.Api` module. For more details, see the `DSpace.Api.HttpClient` documentation.
  """
end
