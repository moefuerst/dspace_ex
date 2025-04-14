defmodule DSpace.Api do
  @moduledoc """
  Represents a DSpace API client.

  Provides credentials and connection details for making requests to the API.
  """

  # DSpace 7.6.1
  @api_version "7.6.1"

  @derive {Inspect, except: [:access_token, :csrf_token]}
  defstruct endpoint: nil,
            access_token: nil,
            csrf_token: nil,
            api_version: @api_version,
            client_impl: {DSpace.Api.Http.Req, [json: true]}

  @typedoc """
  The DSpace API client struct.

  * `:endpoint` - The DSpace REST endpoint, e.g. https://example.com/server
  * `:access_token` - API key or login token used for authentication
  * `:csrf_token` - CSRF token. Needed for all modifying requests
  * `:api_version` - DSpace API version
  * `:client_impl` - HTTP client implementation and options as {module, options}
  """
  @type t :: %__MODULE__{
          endpoint: binary() | nil,
          access_token: binary() | nil,
          csrf_token: binary() | nil,
          api_version: binary(),
          client_impl: {module(), keyword()}
        }

  # Public API

  @doc """
  Creates a new client with optional credentials.
  """
  @spec new(endpoint :: binary(), access_token :: binary() | nil, csrf_token :: binary() | nil) ::
          t()
  def new(endpoint, access_token \\ nil, csrf_token \\ nil) do
    %__MODULE__{
      endpoint: endpoint,
      access_token: access_token,
      csrf_token: csrf_token
    }
  end

  @doc """
  Updates the API endpoint.
  """
  @spec with_endpoint(api :: t(), endpoint :: binary()) :: t()
  def with_endpoint(%__MODULE__{} = api, endpoint) when is_binary(endpoint) do
    %{api | endpoint: endpoint}
  end

  @doc """
  Updates the Access token.
  """
  @spec with_access_token(api :: t(), access_token :: binary()) :: t()
  def with_access_token(%__MODULE__{} = api, access_token) when is_binary(access_token) do
    %{api | access_token: access_token}
  end

  @doc """
  Updates the CSRF token.
  """
  @spec with_csrf_token(api :: t(), csrf_token :: binary()) :: t()
  def with_csrf_token(%__MODULE__{} = api, csrf_token) when is_binary(csrf_token) do
    %{api | csrf_token: csrf_token}
  end

  @doc """
  Updates the CSRF token from an API response if present.
  """
  @spec with_token_from_response(api :: t(), response :: map()) :: t()
  def with_token_from_response(api, response) do
    case DSpace.Api.Response.extract_csrf(response) do
      nil -> api
      token -> with_csrf_token(api, token)
    end
  end

  @doc """
  Updates the HTTP client implementation.
  """
  @spec with_client_impl(api :: t(), client_impl :: {module(), keyword()}) :: t()
  def with_client_impl(%__MODULE__{} = api, {module, options} = client_impl)
      when is_atom(module) and is_list(options) do
    %{api | client_impl: client_impl}
  end

  @doc """
  Makes a request to the API.

  Generally intended to be used internally, but can be used by end-users to work around missing endpoints/functionality.
  """
  @spec request(api :: t(), options :: keyword()) :: {:ok, map()} | {:error, DSpace.Api.Error.t()}
  def request(%__MODULE__{endpoint: endpoint} = api, options) when is_list(options) do
    {client_impl, client_options} = api.client_impl

    request_options =
      [base_url: endpoint]
      |> Keyword.merge(client_options)
      |> maybe_add_auth(api.access_token)
      |> maybe_add_csrf(api.csrf_token)
      |> Keyword.merge(options)
      |> unsafe_methods_need_csrf!()

    DSpace.Api.Http.request(client_impl, request_options)
    |> DSpace.Api.Response.normalize()
  end

  @doc """
  Streams paginated results from a collection endpoint.

  ## Parameters
  * `api` - The DSpace API client
  * `options` - Initial request options
  * `extract_fn` - Function that extracts resources from a response
  * `transform_fn` - Function that transforms each resource (optional)

  Generally intended to be used internally.
  """
  @spec stream(
          api :: t(),
          options :: keyword(),
          extract_fn :: (map() -> list()),
          transform_fn :: (any() -> any())
        ) :: Enumerable.t()
  def stream(api, options, extract_fn, transform_fn \\ & &1) do
    Stream.resource(
      fn -> {api, options} end,
      fn
        nil ->
          {:halt, nil}

        {current_api, request_options} ->
          case request(current_api, request_options) do
            {:ok, response} ->
              resources = extract_fn.(response.body)
              transformed = Enum.map(resources, transform_fn)

              updated_api = with_token_from_response(current_api, response)
              next_options = DSpace.Api.Response.Page.next(response, request_options)

              {transformed, {updated_api, next_options}}

            {:error, _} ->
              {:halt, nil}
          end
      end,
      fn _ -> :ok end
    )
  end

  @doc """
  Authenticates with the DSpace API using the provided credentials.

  Returns a client with updated tokens or an error.
  """
  @spec login(api :: t(), username :: binary(), password :: binary()) ::
          {:ok, t()} | {:error, DSpace.Api.Error.t()}
  defdelegate login(api, username, password), to: DSpace.Api.Auth

  @doc """
  Verifies if the current client is authenticated with the DSpace API.

  Also returns `false` if the check fails.
  """
  @spec authenticated?(api :: t()) :: boolean()
  defdelegate authenticated?(api), to: DSpace.Api.Auth

  # Private helpers

  defp maybe_add_auth(options, nil), do: options

  defp maybe_add_auth(options, token),
    do: Keyword.put(options, :auth, {:bearer, token})

  defp maybe_add_csrf(options, nil), do: options

  defp maybe_add_csrf(options, token),
    do: Keyword.put(options, :headers, [{"x-xsrf-token", token}])

  # A particular of the DSpace API's design.
  defp unsafe_methods_need_csrf!(options) do
    method = Keyword.get(options, :method)

    if method in [:post, :put, :patch, :delete] and not has_csrf_token?(options) do
      raise ArgumentError, "CSRF token is required for #{method} operations with a DSpace API"
    end

    options
  end

  defp has_csrf_token?(options) do
    Keyword.get(options, :headers, [])
    |> Enum.any?(&match?({"x-xsrf-token", _}, &1))
  end
end
