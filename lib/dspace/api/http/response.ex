defmodule DSpace.API.HTTP.Response do
  @moduledoc """
  Response structure used by HTTP adapters.
  """

  defstruct request_url: %URI{},
            status: 200,
            headers: %{},
            body: ""

  @type t :: %__MODULE__{
          request_url: URI.t(),
          status: non_neg_integer(),
          headers: %{optional(binary()) => [binary()]},
          body: map() | binary() | term()
        }

  # Public API

  @spec format(t()) :: binary()
  def format(response) do
    [request_url, _] =
      response.request_url
      |> URI.to_string()
      |> String.split("?", parts: 2)

    """
    Requested endpoint: #{request_url}
    Response status: #{response.status}

    Response headers:
    #{Enum.map_join(response.headers, "\n", fn {k, v} -> "#{k}: #{v}" end)}


    Response body:
    #{inspect(response.body, pretty: true)}
    """
  end
end
