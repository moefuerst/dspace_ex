defmodule DSpace.API.HTTP.Req do
  @moduledoc """
  HTTP adapter implementation using Req.

  ## Observability

  Passing a `:plugins` list as part of the adapter options lets the consuming application attach
  custom Req steps for telemetry, logging, etc. that participate in the full request/response
  pipeline:

      %DSpace.API{
        endpoint: "https://example.com/server",
        http_impl: {DSpace.API.HTTP.Req, [plugins: [&MyApp.ReqTelemetry.attach/1]]}
      }
  """

  @behaviour DSpace.API.HTTP

  alias DSpace.API.HTTP

  # Callbacks

  @spec request(keyword()) :: {:ok, HTTP.Response.t()} | {:error, HTTP.Error.t()}
  @impl HTTP
  def request(options) when is_list(options) do
    options
    |> Req.request()
    |> transform_response()
  end

  # Private helpers

  defp transform_response({:ok, response}) do
    {:ok, %HTTP.Response{status: response.status, headers: response.headers, body: response.body}}
  end

  defp transform_response({:error, reason}), do: {:error, HTTP.Error.exception(reason: reason)}
end
