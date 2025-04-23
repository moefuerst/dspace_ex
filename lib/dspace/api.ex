defmodule DSpace.Api do
  @moduledoc """
  Represents a DSpace API client.

  Provides credentials and connection details for making requests to the API.
  """

  alias DSpace.Api.Auth
  alias DSpace.Api.Error
  alias DSpace.Api.Http
  alias DSpace.Api.Http.Req
  alias DSpace.Api.Response
  alias DSpace.Api.Response.Page

  # DSpace 7.6.1
  @api_version "7.6.1"

  @derive {Inspect, except: [:access_token, :csrf_token]}
  defstruct endpoint: nil,
            access_token: nil,
            csrf_token: nil,
            api_version: @api_version,
            client_impl: {Req, [json: true]}

  @typedoc """
  The DSpace API client struct.

  * `:endpoint` - The DSpace REST endpoint, e.g. https://example.com/server
  * `:access_token` - API key or login token used for authentication. This is a standard JWT
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
  @spec with_csrf_from_response(api :: t(), response :: map()) :: t()
  defdelegate with_csrf_from_response(api, response), to: Auth

  @doc """
  Updates the API version.
  """
  @spec with_api_version(api :: t(), version :: binary()) :: t()
  def with_api_version(%__MODULE__{} = api, version) when is_binary(version) do
    %{api | api_version: version}
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
  @spec request(api :: t(), options :: keyword()) ::
          {:ok, map()} | {:error, Error.t() | Exception.t()}
  def request(%__MODULE__{endpoint: endpoint} = api, options) when is_list(options) do
    {client_impl, client_options} = api.client_impl

    request_options =
      [base_url: endpoint]
      |> Keyword.merge(client_options)
      |> maybe_add_csrf(api.csrf_token)
      |> maybe_add_auth(api.access_token)
      |> Keyword.merge(options)
      |> unsafe_methods_need_csrf!()

    Http.request(client_impl, request_options)
    |> Response.normalize()
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
      fn state -> handle_stream_state(state, extract_fn, transform_fn) end,
      fn _ -> :ok end
    )
  end

  @doc """
  Authenticates with the DSpace API using the provided credentials.

  Returns a client with updated tokens or an error.
  """
  @spec login(api :: t(), username :: binary(), password :: binary()) ::
          {:ok, t()} | {:error, Error.t() | Exception.t()}
  defdelegate login(api, username, password), to: Auth

  @doc """
  Verifies if the current client is authenticated with the DSpace API.

  Also returns `false` if the check fails.
  """
  @spec authenticated?(api :: t()) :: boolean()
  defdelegate authenticated?(api), to: Auth

  # Private helpers

  defp maybe_add_auth(options, nil), do: options

  defp maybe_add_auth(options, token) do
    Keyword.put(options, :auth, {:bearer, token})
  end

  defp maybe_add_csrf(options, nil), do: options

  defp maybe_add_csrf(options, token) do
    Keyword.update(options, :headers, [{"x-xsrf-token", token}], fn existing ->
      existing
      |> Enum.reject(fn {name, _} -> String.downcase(name) == "x-xsrf-token" end)
      |> then(fn filtered -> [{"x-xsrf-token", token} | filtered] end)
    end)
  end

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

  defp handle_stream_state(nil, _, _), do: {:halt, nil}

  defp handle_stream_state({current_api, request_options}, extract_fn, transform_fn) do
    case request(current_api, request_options) do
      {:ok, response} ->
        context = %{
          response: response,
          api: current_api,
          options: request_options,
          extract_fn: extract_fn,
          transform_fn: transform_fn
        }

        process_stream_response(context)

      _error ->
        {:halt, nil}
    end
  end

  defp process_stream_response(context) do
    %{
      response: response,
      api: api,
      options: options,
      extract_fn: extract_fn,
      transform_fn: transform_fn
    } = context

    resources = extract_fn.(response.body) |> Enum.map(transform_fn)
    updated_api = with_csrf_from_response(api, response)
    next_options = Page.next(response, options)
    next_state = if next_options, do: {updated_api, next_options}, else: nil

    {resources, next_state}
  end
end
