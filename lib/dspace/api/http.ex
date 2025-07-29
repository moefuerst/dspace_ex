defmodule DSpace.Api.Http do
  @moduledoc """
  HTTP adapter helper module.

  Facilitates HTTP requests using the configured adapter and normalizes responses.

  This module specifies the expected behavior of an HTTP adapter.

  ## Response

  An implementation returns the response as a `t:DSpace.Api.Http.Response/0` with the fields:
    * `:status` - HTTP status code as integer
    * `:headers` - HTTP response headers as a map
    * `:body` - response body, already decoded into a map
  """

  alias DSpace.Api.Http

  @typedoc """
  Options supported by HTTP adapters.
  """
  @type options :: keyword()

  @typedoc """
  Response format returned by HTTP adapters.
  """
  @type response :: {:ok, Http.Response.t()} | {:error, Http.Error.t()}

  @doc """
  Executes an HTTP request and returns a response or an error.
  """
  @callback request(options()) :: response()
end
