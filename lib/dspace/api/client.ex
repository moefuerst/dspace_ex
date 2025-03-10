defmodule DSpace.Api.Client do
  @moduledoc """
  Specifies the behaviour for a HTTP client to interact with the DSpace API.


  TODO: Default implementation, this will be done using `Req`.
  """

  @typedoc """
  Required options implementations have to support.

  * `:auth` - Sets the correct authorization header
  * `:base_url` - If set, prepend the `url` with this base URL
  * `:body` - request body
  * `:headers` - request headers
  * `:method` - verb as atom (`:get`, `:post`, etc.) Implementation must default to GET request if none given.
  * `:url` - request URL / path
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
    Executes a HTTP request and returns a response or an error.
  """
  @callback request(options()) :: {:ok, response()} | {:error, Exception.t()}

  @doc """
    Executes a HTTP request and returns a response or raises on errors.
  """
  @callback request!(options()) :: response() | Exception.t()
end
