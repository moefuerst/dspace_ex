defmodule DSpace.API.StreamBuilder do
  @moduledoc """
  Default implementation for streaming of paginated collections from the API.

  This module is usually not used directly. Streaming functionality is used through
  resource modules:

      DSpace.API.Item.list() |> DSpace.API.stream!(client)
      # Yields: [item1, item2, item3], [item4, item5, item6], ...
  """

  import DSpace.API.Utils

  alias DSpace.API

  # Public API

  @doc """
  Creates a stream for paginated API responses.

  ## Parameters
    * `client` - The `t:DSpace.API/0` client structure to use for the request.
    * `operation` - The operation to perform, configured with a transformer that returns the
      response as a tuple `{items, meta, next}` where `items` is a list of resources, `meta` is
      metadata, and `next` is the URL for the next page or `nil` if there are no more pages.
    * `options` - Request options.
  """
  @spec new(API.t(), struct(), keyword()) :: Enumerable.t()
  def new(client, operation, options) do
    Stream.resource(fn -> {operation, client, options} end, &fetch_page/1, & &1)
  end

  # Private helpers

  @spec fetch_page({struct() | nil, API.t(), keyword()}) ::
          {:halt, nil} | {list(), {struct() | nil, API.t(), keyword()}}
  defp fetch_page({nil, _client, _options}), do: {:halt, nil}

  defp fetch_page({operation, client, options}) do
    {items, _meta, next} = API.request!(operation, client, options)

    if is_nonempty_binary(next) do
      # `next` is a fully built URL, so we drop the params of the initial operation
      {items, {%{operation | path: next, params: []}, client, options}}
    else
      {items, {nil, client, options}}
    end
  end
end
