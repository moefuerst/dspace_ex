defmodule DSpace.API.Transform do
  @moduledoc false

  import DSpace.API.Utils

  alias DSpace.API.HTTP.Response

  @doc """
  Extracts the body as a map from an API response structure.
  """
  @spec from_response(Response.t() | any()) :: map()
  def from_response(%Response{body: body}) when is_map(body), do: body
  def from_response(_), do: %{}

  @doc """
  Extracts a value from the response body by key.
  """
  @spec get(Response.t(), binary()) :: term()
  def get(%Response{body: body}, key, default \\ nil) when is_map(body) and is_nonempty_binary(key) do
    Map.get(body, key, default)
  end
end
