defmodule DSpace.API.Transform do
  @moduledoc false

  import DSpace.Utils, only: [is_nonempty_binary: 1]

  alias DSpace.API.HTTP.Response

  @doc """
  Extracts the body as a map from an API response structure.
  """
  @spec from_response(Response.t() | term()) :: map()
  def from_response(%Response{body: body}) when is_map(body), do: body
  def from_response(_), do: %{}

  @doc """
  Extracts a value from the response body by key.
  """
  @spec get(Response.t(), binary()) :: term()
  def get(%Response{body: body}, key, default \\ nil) when is_map(body) and is_nonempty_binary(key) do
    Map.get(body, key, default)
  end

  @doc """
  Extracts and transforms a collection of resources from a response.

  ## Parameters

    * `map` - A map or `t:DSpace.API.HTTP.Response.t/0` containing the resource(s)
    * `options` - A keyword list with the following keys:
      * `:extract` - A path to navigate to the resource(s) (defaults to `nil`)
      * `:transform` - A function to process each resource (defaults to identity)
  """
  @spec transform(Response.t() | map(), keyword()) :: list(term())
  def transform(%Response{body: body}, options) when is_map(body), do: transform(body, options)

  def transform(map, options) when is_map(map) and is_list(options) do
    transform = Keyword.get(options, :transform, &Function.identity/1)
    path = Keyword.get(options, :extract)

    map
    |> extract_resources(path)
    |> Enum.map(transform)
  end

  @doc """
  Extracts resources and metadata from a paginated collection response.

  Returns a three-element tuple `{data, meta, next}`:

    * `data`: List of transformed resources
    * `meta`: Meta information from the API response
    * `next`: URL for next page or nil if no more pages

  ## Parameters

    * `map` - A map or `t:DSpace.API.HTTP.Response.t/0` containing the resource collection
    * `options` - A keyword list with the following keys:
      * `:extract` - A path to navigate to the resources (required)
      * `:next` - A path to navigate to the continuation token
      * `:transform` - A function to process each resource (defaults to identity)
  """
  @spec transform_collection(struct() | map(), keyword()) :: {list(term()), map(), term()}
  def transform_collection(%Response{body: body}, options) when is_map(body) do
    transform_collection(body, options)
  end

  def transform_collection(map, options) when is_map(map) and is_list(options) do
    extract_path = Keyword.fetch!(options, :extract)
    next_path = Keyword.get(options, :next, ["_links", "next", "href"])
    transform = Keyword.get(options, :transform, &Function.identity/1)

    data =
      map
      |> extract_resources(extract_path)
      |> Enum.map(transform)

    next = get_in(map, next_path)

    meta = drop_extracted(map, extract_path)

    {data, meta, next}
  end

  # Private helpers

  defp extract_resources(map, nil), do: [map]
  defp extract_resources(map, path) when is_list(path), do: get_in(map, path) || []

  defp drop_extracted(map, path) when is_list(path) do
    [first_key | _rest] = path

    Map.delete(map, first_key)
  end
end
