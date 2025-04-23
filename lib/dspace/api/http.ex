defmodule DSpace.Api.Http do
  @moduledoc """
  Specifies the behaviour for an HTTP client.

  An implementation comes with batteries included (JSON de/serialization, retry, connection pooling, timeouts, etc.) with sensible defaults provided. All request parameters and client configuration options are passed as a single keyword list to the `request/1` function.

  ## Client configuration

  Client defaults can be set in the `client_impl` tuple when injecting the implementation into a `DSpace.Api` struct:

      %DSpace.Api{
        endpoint: "https://example.com/server",
        client_impl: {My.Http.Client, [pool_timeout: 5000]}
      }

  Options passed to individual requests are merged with these defaults, with the former taking precedence.

  ## Options passed to requests

  An implementation supports the following options:
  * `:auth` - Contains a bearer token. Implementation needs to set the correct authorization header.
  * `:base_url` - If set, implementation needs to prepend `url` with this base URL.
  * `:body` - request body
  * `:headers` - request headers
  * `:json` - If set, implementation needs to
    * if `true`, set appropriate accept header
    * if data, encode it, set it as body, and set appropriate content-type and accept headers
  * `:method` - verb as atom (`:get`, `:post`, etc.). Implementation must default to `GET` request if none given.
  * `:url` - request URL or path

  ## Response

  An implementation returns the response as a map with the keys:
  * `:status` - HTTP status code as integer
  * `:headers` - HTTP response headers as a map
  * `:body` - response body is already parsed and decoded into a map
  * `:trailers` - HTTP response trailers as a map
  """

  @typedoc """
  Options implementations have to support.
  """
  @type required_options :: [
          auth: {:bearer, binary()} | nil,
          base_url: binary() | URI.t() | (-> term()),
          body: iodata() | Enumerable.t() | nil,
          headers: %{optional(binary()) => [binary()]},
          json: map() | boolean() | nil,
          method: atom(),
          url: URI.t() | binary()
        ]

  @typedoc false
  @type options :: required_options() | keyword()

  @typedoc """
  Response fields implementations have to support.
  """
  @type required_response ::
          %{
            status: non_neg_integer(),
            headers: %{optional(binary()) => [binary()]},
            body: map(),
            trailers: %{optional(binary()) => [binary()]}
          }

  @typedoc false
  @type response :: required_response() | map()

  @doc """
  Executes an HTTP request and returns a response or an error.
  """
  @callback request(options()) :: {:ok, response()} | {:error, Exception.t()}

  # API for internal library use

  @doc false
  @spec request(module(), options()) :: {:ok, response()} | {:error, Exception.t()}
  def request(module, options) do
    module.request(options)
  end

  @doc false
  @spec request!(module(), options()) :: response() | Exception.t()
  def request!(module, options) do
    case module.request(options) do
      {:ok, response} -> response
      {:error, error} -> raise error
    end
  end
end
