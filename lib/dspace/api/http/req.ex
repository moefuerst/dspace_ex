if Code.ensure_loaded?(Req) do
  defmodule DSpace.API.HTTP.Req do
    @moduledoc """
    Default HTTP adapter implementation using Req.

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
      {plugins, other_options} = Keyword.pop(options, :plugins, [])

      other_options
      |> Req.new()
      |> then(&Enum.reduce(plugins, &1, fn plugin, req -> plugin.(req) end))
      |> Req.run()
      |> transform_result()
    end

    # Private helpers

    defp transform_result({req, %Req.Response{} = response}) do
      {:ok,
       %HTTP.Response{
         request_url: req.url,
         status: response.status,
         headers: response.headers,
         body: response.body
       }}
    end

    defp transform_result({_req, exception}) do
      {:error, HTTP.Error.exception(reason: exception)}
    end
  end
end
