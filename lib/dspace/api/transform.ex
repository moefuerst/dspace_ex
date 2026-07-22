defmodule DSpace.API.Transform do
  @moduledoc """
  Functions for transforming API responses.
  """

  import DSpace.Utils, only: [is_nonempty_binary: 1]

  alias DSpace.API.Error
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
    * `options` - Keyword list of options

  ## Options

    * `:extract` - A path to navigate to the resource(s) (defaults to `nil`)
    * `:transform` - A function to process each resource (defaults to identity)
  """
  @spec transform(Response.t() | map(), keyword()) :: list(term())
  def transform(%Response{body: body}, options) when is_map(body) do
    transform(body, options)
  end

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

    * `data` - List of transformed resources
    * `meta` - Meta information from the API response
    * `next` - URL for next page or nil if no more pages

  ## Parameters

    * `map` - A map or `t:DSpace.API.HTTP.Response.t/0` containing the resource collection
    * `options` - Keyword list of options

  ## Options

    * `:extract` - A path to navigate to the resources (required)
    * `:next` - A path to navigate to the continuation token
        (defaults to `["_links", "next", "href"]`)
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

  @doc """
  Returns a `:not_found` error when the response status is 204 (No Content).

  Some endpoints that conceptually fetch a single resource are implemented as searches
  (e.g. `/api/eperson/epersons/search/byEmail`). When no match is found, the API returns 204
  reflecting an "empty search result" rather than a missing resource.

  From the caller's perspective, however, these are unique-key lookups: an email uniquely
  identifies at most one user (this is enforced by DSpace), so an absent result is semantically
  a missing resource, not an empty collection. This function can be used to normalize that
  behaviour by converting 204 responses into a `:not_found` error, giving callers a consistent
  signal.
  """
  @spec not_found_on_no_content(Response.t(), binary()) :: map() | Error.t()
  def not_found_on_no_content(response, message \\ "Resource not found")

  def not_found_on_no_content(%Response{status: 204} = response, message) do
    Error.exception(type: :not_found, status: 404, message: message, response: response)
  end

  def not_found_on_no_content(response, _message), do: from_response(response)

  @doc """
  Extracts the access token and CSRF token from an API response.

  Returns the tokens or an error.
  """
  @spec tokens_from_response(Response.t()) :: {:ok, {binary(), binary()}} | {:error, Error.t()}
  def tokens_from_response(%Response{} = response) do
    with {:ok, auth_token} <- extract_access_token(response),
         {:ok, csrf_token} <- extract_csrf(response) do
      {:ok, {auth_token, csrf_token}}
    else
      _error -> {:error, Error.response_validation_error(response)}
    end
  end

  @doc """
  Extracts the access token from an API response.

  Returns the token or an error.
  """
  @spec access_token_from_response(Response.t()) :: {:ok, binary()} | {:error, Error.t()}
  def access_token_from_response(%Response{} = response) do
    case extract_access_token(response) do
      {:ok, token} -> {:ok, token}
      {:error, :access_token_missing} -> {:error, Error.response_validation_error(response)}
    end
  end

  @doc """
  Extracts the CSRF token from an API response.

  Returns the token or an error.
  """
  @spec csrf_token_from_response(Response.t()) :: {:ok, binary()} | {:error, Error.t()}
  def csrf_token_from_response(%Response{} = response) do
    case extract_csrf(response) do
      {:ok, token} -> {:ok, token}
      {:error, :csrf_token_missing} -> {:error, Error.response_validation_error(response)}
    end
  end

  @doc """
  Extracts a token from an API response.

  Returns the token or an error.
  """
  def token_from_response(%Response{} = response) do
    case extract_token_from_body(response) do
      {:ok, token} -> {:ok, token}
      {:error, :token_missing} -> {:error, Error.response_validation_error(response)}
    end
  end

  # Private helpers

  defp extract_resources(map, nil), do: [map]
  defp extract_resources(map, path) when is_list(path), do: get_in(map, path) || []

  defp drop_extracted(map, path) when is_list(path) do
    [first_key | _rest] = path

    Map.delete(map, first_key)
  end

  defp extract_csrf(%{headers: %{"dspace-xsrf-token" => [token | _]}}) when is_nonempty_binary(token) do
    {:ok, token}
  end

  defp extract_csrf(%{headers: %{"set-cookie" => cookies}}) do
    token =
      cookies
      |> Enum.flat_map(&String.split(&1, ";"))
      |> Enum.map(&String.trim/1)
      |> Enum.find_value(fn
        "DSPACE-XSRF-COOKIE=" <> token -> token
        _ -> nil
      end)

    case token do
      nil -> {:error, :csrf_token_missing}
      token -> {:ok, token}
    end
  end

  defp extract_csrf(_response), do: {:error, :csrf_token_missing}

  # DSpace returns the access token in an `authorization` response header. This differs from the
  # standard OAuth token response (RFC 6749-style flow), which typically places tokens in the
  # response body.
  defp extract_access_token(%{headers: %{"authorization" => ["Bearer " <> token | _]}}) when is_nonempty_binary(token) do
    {:ok, token}
  end

  defp extract_access_token(_response), do: {:error, :access_token_missing}

  defp extract_token_from_body(%{body: %{"token" => token}} = _response) when is_nonempty_binary(token) do
    {:ok, token}
  end

  defp extract_token_from_body(_response), do: {:error, :token_missing}
end
