defmodule DSpace.Api.HttpClient do
  @moduledoc """
  Specifies the behaviour for an HTTP client to interact with the DSpace API.

  All request parameters and client configuration options are passed as a single keyword list to the `request/1` and `request!/1` functions.

  ## Client configuration
  Client defaults can be set in the `client_impl` tuple when injecting the implementation into a `DSpace.Api` struct:

  ```elixir
  %DSpace.Api{
    endpoint: "https://example.com/server",
    client_impl: {My.Http.Client, [pool_timeout: 5000]}
  }
  ```

  Options passed to individual requests are merged with these defaults, with the former taking precedence.

  ## Options
  The implementation has to support the following options:

  * `:auth` - Contains a bearer token. Implementation needs to set the correct authorization header.
  * `:base_url` - If set, implementation needs to prepend `url` with this base URL.
  * `:body` - request body
  * `:headers` - request headers
  * `:method` - verb as atom (`:get`, `:post`, etc.). Implementation must default to `:get` if none given.
  * `:url` - request URL or path
  """

  @typedoc """
  Options implementations have to support.
  """
  @type required_options :: [
          auth: {:bearer, binary()} | nil,
          base_url: binary() | URI.t() | (-> term()),
          body: iodata() | Enumerable.t() | nil,
          headers: %{optional(binary()) => [binary()]},
          method: atom(),
          url: URI.t() | binary()
        ]

  @type options :: required_options() | keyword()

  @type response :: %{
          body: binary() | term(),
          headers: %{optional(binary()) => [binary()]},
          status: non_neg_integer()
        }

  @doc """
  Executes an HTTP request and returns a response or an error.
  """
  @callback request(options()) :: {:ok, response()} | {:error, Exception.t()}

  @doc false
  def request(module, options) do
    module.request(options)
  end

  @doc """
  Executes an HTTP request and returns a response or raises on errors.
  """
  @callback request!(options()) :: response() | Exception.t()

  @doc false
  def request!(module, options) do
    module.request!(options)
  end
end
