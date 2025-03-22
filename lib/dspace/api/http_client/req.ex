defmodule DSpace.Api.HttpClient.Req do
  @moduledoc """
  HTTP client implementation using Req.
  """

  @behaviour DSpace.Api.HttpClient

  @doc """
  Executes an HTTP request and returns a response or an error.
  """
  @impl true
  @spec request(keyword()) :: {:ok, map()} | {:error, Exception.t()}
  def request(options) when is_list(options) do
    Req.request(options)
  end

  @doc """
  Executes an HTTP request and returns a response or raises on errors.
  """
  @impl true
  @spec request!(keyword()) :: map() | Exception.t()
  def request!(options) when is_list(options) do
    Req.request!(options)
  end
end
