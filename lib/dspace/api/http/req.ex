defmodule DSpace.Api.Http.Req do
  @moduledoc false
  # HTTP adapter implementation using Req.

  @behaviour DSpace.Api.Http

  alias DSpace.Api.Http

  # Callbacks

  @impl true
  @spec request(keyword()) :: {:ok, Http.Response.t()} | {:error, Http.Error.t()}
  def request(options) when is_list(options) do
    options
    |> Req.request()
    |> transform_response()
  end

  # Private helpers

  defp transform_response({:ok, %Req.Response{} = response}) do
    {:ok, %Http.Response{status: response.status, headers: response.headers, body: response.body}}
  end

  defp transform_response({:error, reason}), do: {:error, Http.Error.exception(reason: reason)}
end
