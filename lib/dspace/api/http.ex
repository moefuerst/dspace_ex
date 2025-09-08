defmodule DSpace.API.HTTP do
  @moduledoc """
  HTTP adapter helper module.

  Facilitates HTTP requests using the configured adapter and normalizes responses.

  This module also specifies the expected behavior of an HTTP adapter. The behavior basically
  aligns with Req's API, so alternative implementations need to come with batteries included
  (e.g., JSON parsing) and sensible defaults provided. All request parameters and adapter
  configuration options are passed as a single keyword list to the `request/1` function.

  ## Setting an adapter and the adapter default configuration

  Default options for the adapter are set in the `http_impl` tuple when injecting the
  implementation into a `t:DSpace.API.t/0` structure by passing a list of options:

      %DSpace.API{
        endpoint: "https://example.com/server",
        http_impl: {MyApp.HTTPAdapter, [pool_timeout: 5000]}
      }

  Options passed to individual requests are merged with these defaults, with the former taking
  precedence.

  ## Request options

  An adapter implementation supports the following options:

    * `:url` - request URL
    * `:method` - verb as atom (`:get`, `:post`, etc.). If not set, adapter defaults to `GET`
      request
    * `:headers` - request headers
    * `:params` - if set, appends parameters to the request query string
    * `:json` - if map data, adapter will encode it, set it as body, and set appropriate
      content-type header
    * `:form` - if map data, adapter will URL-encode it, set it as body, and set appropriate
      content-type header
    * `:form_multipart` - if map data, adapter will encode as multipart/form-data, set it as body,
      and set appropriate content-type header
    * `:body` - request body
    * `:decode_body` - if `false`, the adapter will not decode the *response* body

  ## Response

  An adapter implementation returns the response as a `t:DSpace.API.HTTP.Response.t/0` with the fields:

    * `:status` - HTTP status code as integer
    * `:headers` - HTTP response headers as a map
    * `:body` - response body, already decoded into a map
  """

  alias DSpace.API.HTTP

  @typedoc """
  Options supported by HTTP adapters.
  """
  @type options :: [
          url: URI.t() | binary(),
          method: :get | :head | :post | :put | :patch | :delete,
          headers: %{optional(binary() | atom()) => [binary()]},
          params: keyword(),
          json: map() | nil,
          form: map() | nil,
          form_multipart: map() | nil,
          body: iodata() | Enumerable.t() | nil,
          decode_body: boolean() | nil
        ]

  @typedoc """
  Response format returned by HTTP adapters.
  """
  @type response :: {:ok, HTTP.Response.t()} | {:error, HTTP.Error.t()}

  @doc """
  Executes an HTTP request and returns a response or an error.
  """
  @callback request(options()) :: response()

  # API for internal use

  @doc false
  @spec request(module(), keyword()) :: {:ok, HTTP.Response.t()} | {:error, Exception.t()}
  def request(module, options) do
    requested_endpoint =
      options
      |> Keyword.fetch!(:url)
      |> URI.parse()

    {expected_status, other_options} = Keyword.pop(options, :expected_status)

    other_options
    |> module.request()
    |> handle_adapter_result(requested_endpoint, expected_status)
  end

  @doc false
  @spec request!(module(), keyword()) :: HTTP.Response.t()
  def request!(module, options) do
    case request(module, options) do
      {:ok, response} -> response
      {:error, exception} -> raise exception
    end
  end

  # Private helpers

  defp handle_adapter_result({:ok, %HTTP.Response{} = response}, requested_endpoint, nil) do
    {:ok, %{response | request_url: requested_endpoint}}
  end

  defp handle_adapter_result({:ok, %HTTP.Response{} = response}, requested_endpoint, expected_status) do
    response = %{response | request_url: requested_endpoint}

    if response.status in expected_status do
      {:ok, response}
    else
      {:error, DSpace.API.Error.from_response(response)}
    end
  end

  defp handle_adapter_result({:error, %HTTP.Error{} = error}, requested_endpoint, _expected_status) do
    {:error, %{error | request_url: requested_endpoint}}
  end
end
