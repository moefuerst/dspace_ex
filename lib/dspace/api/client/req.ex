defmodule DSpace.Api.Client.Req do
  @moduledoc """
  HTTP client implementation using Req library.
  """

  @behaviour DSpace.Api.Client

  @impl true
  @spec request(keyword()) :: {:ok, map()} | {:error, Exception.t()}
  def request(options) when is_list(options) do
    Req.request(options)
  end

  @impl true
  @spec request!(keyword()) :: map() | Exception.t()
  def request!(options) when is_list(options) do
    Req.request!(options)
  end
end
