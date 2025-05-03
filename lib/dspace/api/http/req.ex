defmodule DSpace.Api.Http.Req do
  @moduledoc false

  # HTTP client implementation using Req.
  @behaviour DSpace.Api.Http

  # Callbacks

  @doc """
  Executes an HTTP request and returns a response or an error.
  """
  @impl true
  @spec request(keyword()) :: {:ok, map()} | {:error, Exception.t()}
  def request(options) when is_list(options) do
    Req.request(options)
  end
end
