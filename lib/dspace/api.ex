defmodule DSpace.API do
  @moduledoc """
  Represents a DSpace API client configuration.

  ## Basic Usage / Configuration

  dspace_ex doesn't prescribe the configuration strategy of consuming applications. For API
  interactions, declare a `t:DSpace.API.t/0` structure with the necessary configuration when you
  need it:

      client = %DSpace.API{
        endpoint: "https://example.com/server",
        access_token: "my-access-token",
        csrf_token: "my-csrf-token"
      }

  Then, use the client struct to perform an operation:

      {:ok, item} =
        "a1b2c3d4-e5f6-4a7b-8c9d-0e1f2a3b4c5d"
        |> DSpace.API.Item.fetch()
        |> DSpace.API.request(client)

  See `new/1` for all client configuration options.

  ## Session Management

  Per DSpace API contract, *all* responses need to be monitored for CSRF token updates, regardless
  of client or use context. The actual implementation of the DSpace backend does not currently
  refresh CSRF tokens with every request, only with login/logout, when the token refresh endpoints
  are called, or the client sends an invalid token.

  The `:on_response_hook` field allows applications to handle CSRF token updates. When set, the
  function will be invoked whenever a response header contains a CSRF token (which should be every
  response).

      client = %DSpace.API{
          endpoint: "https://example.com/server",
          on_response_hook: &MyApp.Session.update_csrf/1
      }

  The hook will receive a map with a `:csrf_token` key. Invocation is synchronous and will block
  until the hook returns. It's probably best to think about using a separate process or a task to
  invoke the function for asynchronous handling, depending on your session management strategy.
  """

  import DSpace.Utils

  alias DSpace.API.Auth
  alias DSpace.API.Operation

  @external_resource version = DSpace.MixProject.project()[:version]

  # DSpace 9.2 / cris-2025.02.00
  @api_version "9.2.0"
  @user_agent "dspace-ex/#{version}"
  @default_http_impl {DSpace.API.HTTP.Req, []}

  @derive {Inspect, except: [:access_token, :csrf_token]}
  defstruct endpoint: %URI{},
            access_token: nil,
            csrf_token: nil,
            api_version: @api_version,
            user_agent: @user_agent,
            http_impl: @default_http_impl,
            on_response_hook: nil

  @typedoc """
  A DSpace API client structure.
  """
  @type t :: %__MODULE__{
          endpoint: URI.t() | binary() | (-> term()),
          access_token: nil | binary(),
          csrf_token: nil | binary(),
          api_version: binary(),
          user_agent: binary(),
          http_impl: {module(), keyword()},
          on_response_hook: nil | (map() -> :ok)
        }

  # Public API

  @doc """
  Creates a new API client.

  ## Parameters

  This function takes either

    * a keyword list of attributes or
    * a single argument that represents the DSpace REST endpoint; either as
      * an `t:URI.t/0` structure
      * a string
      * a 0-arity function that returns a `t:URI.t/0` structure or a string

  ## Attributes

    * `endpoint` - The DSpace REST endpoint, e.g. https://example.com/server. Can be either
      * an `t:URI.t/0` structure
      * a string
      * a 0-arity function that returns a `t:URI.t/0` structure or a string
    * `:access_token` - Optional login token or API key used for authentication
    * `:csrf_token` - Optional CSRF token. Needed for all modifying requests
    * `:api_version` - Optional DSpace API version as a string, defaults to `#{@api_version}`
    * `:user_agent` - Optional User agent string, defaults to `#{@user_agent}`
    * `:http_impl` - Optional HTTP adapter implementation and options as `{module, options}`
    * `:on_response_hook` - Optional callback function invoked when CSRF tokens are updated
  """
  @spec new(attributes :: keyword()) :: t()
  def new(attributes) when is_list(attributes) do
    struct(__MODULE__, attributes)
  end

  @spec new(endpoint :: URI.t() | binary() | fun()) :: t()
  def new(endpoint) when is_struct(endpoint, URI) or is_nonempty_binary(endpoint) or is_function(endpoint, 0) do
    new(endpoint: endpoint)
  end

  @doc """
  Updates the API endpoint.

  ## Parameters

    * `api` - A `t:DSpace.API.t/0` structure
    * `endpoint` - The DSpace REST endpoint, e.g. https://example.com/server. Can be either
      * an `t:URI.t/0` structure
      * a string
      * a 0-arity function that returns a `t:URI.t/0` structure or a string
  """
  @spec put_endpoint(t(), endpoint :: URI.t() | binary()) :: t()
  def put_endpoint(%__MODULE__{} = api, endpoint) when is_struct(endpoint, URI) or is_function(endpoint, 0) do
    %{api | endpoint: endpoint}
  end

  def put_endpoint(%__MODULE__{} = api, endpoint) when is_nonempty_binary(endpoint) do
    endpoint = URI.parse(endpoint)
    put_endpoint(api, endpoint)
  end

  @doc """
  Updates the Access token.

  ## Parameters

    * `api` - A `t:DSpace.API.t/0` structure
    * `access_token` - Login token or API key as a string
  """
  @spec put_access_token(t(), access_token :: binary()) :: t()
  def put_access_token(%__MODULE__{} = api, access_token) when is_nonempty_binary(access_token) do
    %{api | access_token: access_token}
  end

  @doc """
  Updates the CSRF token.

  ## Parameters

    * `api` - A `t:DSpace.API.t/0` structure
    * `csrf_token` - CSRF token as a string
  """
  @spec put_csrf_token(t(), csrf_token :: binary()) :: t()
  def put_csrf_token(%__MODULE__{} = api, csrf_token) when is_nonempty_binary(csrf_token) do
    %{api | csrf_token: csrf_token}
  end

  @doc """
  Updates the session hook function.

  ## Parameters

    * `api` - A `t:DSpace.API.t/0` structure
    * `on_response_hook` - A 1-arity function invoked when CSRF tokens are updated
  """
  @spec put_on_response_hook(t(), (map() -> :ok) | nil) :: t()
  def put_on_response_hook(%__MODULE__{} = api, on_response_hook)
      when is_function(on_response_hook, 1) or is_nil(on_response_hook) do
    %{api | on_response_hook: on_response_hook}
  end

  @doc """
  Updates the HTTP adapter implementation.

  ## Parameters

    * `api` - A `t:DSpace.API.t/0` structure
    * `http_impl` - A tuple of `{module, options}` where module implements `DSpace.API.HTTP`
      behaviour.
  """
  @spec put_http_impl(t(), adapter :: {module(), keyword()}) :: t()
  def put_http_impl(%__MODULE__{} = api, {module, options} = http_impl) when is_atom(module) and is_list(options) do
    %{api | http_impl: http_impl}
  end

  @doc """
  Updates the user agent.

  ## Parameters

    * `api` - A `t:DSpace.API.t/0` structure
    * `user_agent` - User agent as a string
  """
  @spec put_user_agent(t(), user_agent :: binary()) :: t()
  def put_user_agent(%__MODULE__{} = api, user_agent) when is_nonempty_binary(user_agent) do
    %{api | user_agent: user_agent}
  end

  @doc """
  Updates the API version.

  ## Parameters

    * `api` - A `t:DSpace.API.t/0` structure
    * `version` - DSpace API version as a string
  """
  @spec put_api_version(t(), version :: binary()) :: t()
  def put_api_version(%__MODULE__{} = api, version) when is_nonempty_binary(version) do
    %{api | api_version: version}
  end

  @doc """
  Authenticates with a DSpace API and returns an updated client structure.

  Returns returns a `t:DSpace.API.t/0` client structure with updated access- and CSRF tokens.
  Managing token lifecycle (checking expiry, deciding when to refresh) is the responsibility of
  the consuming application. The token is a JWT and contains an `exp` claim. See
  `DSpace.API.Auth.refresh_access_token/0`.

  Executing this operation will fetch a CSRF token from the API first if none is configured in the
  client struct, since that is a prerequisite for hitting the login endpoint.

  ## Parameters

    * `api` - A `t:DSpace.API.t/0` structure
    * `username` - Username as a string
    * `password` - Password as a string

  ## Usage

  The login operation is executed directly when calling this function. The returned client can
  then immediately be used for follow-up operations:

      client =
        [endpoint: "https://example.com/server"]
        |> DSpace.API.new()
        |> DSpace.API.login("username", "password")

      items =
        Item.list()
        |> DSpace.API.stream!(client)
  """
  @spec login(t(), username, password) :: {:ok, t()} | {:error, Exception.t()}
        when username: binary(), password: binary()
  def login(%__MODULE__{} = api, username, password) when is_nonempty_binary(username) and is_nonempty_binary(password) do
    login = Auth.login(username, password)

    case request(login, api, transform: &Auth.tokens_from_response/1) do
      {:ok, {auth_token, csrf_token}} -> {:ok, %{api | access_token: auth_token, csrf_token: csrf_token}}
      {:error, _reason} = error -> error
    end
  end

  @doc """
  Authenticates the client with a DSpace API and raises on errors.

  Similar to `login/3`, but returns the updated client structure directly or raises on errors.
  """
  @spec login!(t(), username, password) :: t()
        when username: binary(), password: binary()
  def login!(%__MODULE__{} = api, username, password)
      when is_nonempty_binary(username) and is_nonempty_binary(password) do
    case login(api, username, password) do
      {:ok, api} -> api
      {:error, reason} -> raise reason
    end
  end

  @doc """
  Updates the path of an operation with a continuation URL.

  This function is intended to be used with paginated responses, where the continuation URL
  is returned as the third element of the response tuple `{items, meta, next_url}`.

  Alternatively, stream operations that return paginated results, as `stream!/3` wraps
  pagination automatically and returns a lazy Stream of resources.

  ## Parameters

    * `operation` - A `t:DSpace.API.Operation.t/0`
    * `next_url` - The continuation URL returned as the third element of a paginated response
      tuple `{items, meta, next_url}`

  ## Example

      client = DSpace.API.new("https://example.com/server")
      operation = Collection.list()

      {:ok, {collections, _meta, next_url}} = DSpace.API.request(operation, client)

      {:ok, {more_collections, _meta, _next_url}} =
        operation
        |> DSpace.API.next_page(next_url)
        |> DSpace.API.request(client)
  """
  @spec next_page(Operation.JSON.t(), binary()) :: Operation.JSON.t()
  def next_page(%Operation.JSON{} = operation, next_url) when is_nonempty_binary(next_url) do
    # `next_url` is already fully built, so we drop the params of the initial operation
    %{operation | path: next_url, params: []}
  end

  @doc """
  Verifies if the passed client is authenticated with the DSpace API.

  Returns `false` if the server indicates the client is not authenticated, or if the server is
  unreachable. Callers who want to separate transport errors from authentication status should
  request `DSpace.API.Auth.status/0` directly.

  ## Parameters

    * `api` - A `t:DSpace.API.t/0` structure
  """
  @spec authenticated?(t()) :: boolean()
  def authenticated?(%__MODULE__{} = api) do
    match?({:ok, true}, request(Auth.status(), api))
  end

  @doc """
  Makes a request to the API and returns a result or an error.

  ## Parameters

    * `operation` - A `t:DSpace.API.Operation.t/0`
    * `api` - A `t:DSpace.API.t/0` structure
    * `options` - Keyword list of options for the request

  ## Options

    * `:transform` - How to transform the API response. Can bei either
      * a 1-arity function that takes a `t:DSpace.API.HTTP.Response.t/0` struct and returns a
        transformed value
      * `false` - passes the raw `t:DSpace.API.HTTP.Response.t/0` struct
    * request option overrides passed to the HTTP adapter

  ## Examples

      client = DSpace.API.new("https://example.com/server")

      {:ok, item} =
        "a1b2c3d4-e5f6-4a7b-8c9d-0e1f2a3b4c5d"
        |> DSpace.API.Item.fetch()
        |> DSpace.API.request(client)
  """
  @spec request(Operation.t(), t(), keyword()) :: {:ok, term()} | {:error, Exception.t()}
  def request(operation, %__MODULE__{} = api, options \\ []) when is_list(options) do
    Operation.perform(operation, api, options)
  end

  @doc """
  Makes a request to the API and returns a result or raises an error.

  For parameters and options, see `request/3`.
  """
  @spec request!(Operation.t(), t(), keyword()) :: term()
  def request!(operation, %__MODULE__{} = api, options \\ []) when is_list(options) do
    case request(operation, api, options) do
      {:ok, result} -> result
      {:error, exception} -> raise exception
    end
  end

  @doc """
  Makes a request to the API and returns a stream.

  For parameters and options, see `request/3`.

  ## Examples

      client = DSpace.API.new("https://example.com/server")

      stream =
        [query: "software errors"]
        |> DSpace.API.Item.find()
        |> DSpace.API.stream!(client)

      Enum.take(stream, 5)
  """
  @spec stream!(Operation.t(), t(), keyword()) :: Enumerable.t()
  def stream!(operation, %__MODULE__{} = api, options \\ []) when is_list(options) do
    Operation.stream!(operation, api, options)
  end
end
