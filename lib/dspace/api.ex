defmodule DSpace.API do
  @moduledoc """
  Represents a DSpace API client configuration.

  ## Basic Usage / Configuration

  `dspace-ex` doesn't prescribe the configuration strategy of consuming applications. For API
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
  of client or use context (The actual implementation does not currently refresh it with every
  request, only with login/logout, when the token refresh endpoints are called, or the client
  sends an invalid token). The `:on_response_hook` field allows applications to handle these.
  When set, the function will be invoked whenever a response header contains a CSRF token (which
  should be every response).

      client = %DSpace.API{
          endpoint: "https://example.com/server",
          on_response_hook: &MyApp.Session.update_csrf/1
      }

  The hook will receive a map with a `:csrf_token` key. Errors are isolated and will not affect
  the operation's return value. Invocation is synchronous and will block until the hook returns.
  It's probably best to think about using a separate process or a task to invoke the function for
  asynchronous handling, depending on your session management strategy.
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
  Creates a new client.

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
    * `:access_token` - Optional login token or API key used for authentication.
    * `:csrf_token` - Optional CSRF token. Needed for all modifying requests
    * `:api_version` - Optional DSpace API version as a string, defaults to latest version
      `dspace-ex` was fully tested against
    * `:user_agent` - Optional User agent string, defaults to `dspace-ex/<version>`
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
  @spec put_access_token(t(), binary()) :: t()
  def put_access_token(%__MODULE__{} = api, access_token) when is_nonempty_binary(access_token) do
    %{api | access_token: access_token}
  end

  @doc """
  Updates the CSRF token.

  ## Parameters

    * `api` - A `t:DSpace.API.t/0` structure
    * `csrf_token` - CSRF token as a string
  """
  @spec put_csrf_token(t(), binary()) :: t()
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
  @spec put_http_impl(t(), {module(), keyword()}) :: t()
  def put_http_impl(%__MODULE__{} = api, {module, options} = http_impl) when is_atom(module) and is_list(options) do
    %{api | http_impl: http_impl}
  end

  @doc """
  Updates the user agent.

  ## Parameters

    * `api` - A `t:DSpace.API.t/0` structure
    * `user_agent` - User agent as a string
  """
  @spec put_user_agent(t(), binary()) :: t()
  def put_user_agent(%__MODULE__{} = api, user_agent) when is_nonempty_binary(user_agent) do
    %{api | user_agent: user_agent}
  end

  @doc """
  Updates the API version.

  ## Parameters

    * `api` - A `t:DSpace.API.t/0` structure
    * `version` - DSpace API version as a string
  """
  @spec put_api_version(t(), binary()) :: t()
  def put_api_version(%__MODULE__{} = api, version) when is_nonempty_binary(version) do
    %{api | api_version: version}
  end

  @doc """
  Authenticates with a DSpace API using the provided credentials.

  Returns an access token. Managing token lifecycle (checking expiry, deciding when to refresh) is
  the responsibility of the consuming application. The token is a JWT and contains an `exp` claim.
  See `DSpace.API.Auth.refresh_access_token/0`.

  Executing this operation will fetch a CSRF token from the API first if none is configured in the
  client struct, since that is a prerequisite for hitting the login endpoint.

  ## Parameters

    * `api` - A `t:DSpace.API.t/0` structure
    * `username` - Username as a string
    * `password` - Password as a string
  """
  @spec login(t(), binary(), binary()) :: {:ok, binary()} | {:error, Exception.t()}
  def login(%__MODULE__{} = api, username, password) when is_nonempty_binary(username) and is_nonempty_binary(password) do
    username
    |> Auth.login(password)
    |> request(api)
  end

  @doc """
  Authenticates with the DSpace API using a client and the provided credentials.

  Similar to `login/3`, but returns a `t:DSpace.API.t/0` client structure with updated access- and
  CSRF tokens. This function is mainly useful in testing and script usage.

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
        |> DSpace.API.login!("username", "password")

      items =
        Item.list()
        |> DSpace.API.stream!(client)
  """
  @spec login!(t(), binary(), binary()) :: t()
  def login!(%__MODULE__{} = api, username, password) do
    login = %{Auth.login(username, password) | transformer: &Auth.tokens_from_response/1}

    case request(login, api) do
      {:ok, {auth_token, csrf_token}} -> %{api | access_token: auth_token, csrf_token: csrf_token}
      {:error, reason} -> raise reason
    end
  end

  @doc """
  Verifies if the passed client is authenticated with the DSpace API.

  This function also returns `false` if the check fails.

  ## Parameters

    * `api` - A `t:DSpace.API.t/0` structure
  """
  @spec authenticated?(t()) :: boolean()
  def authenticated?(%__MODULE__{} = api) do
    request!(Auth.status(), api)
  rescue
    _ -> false
  end

  @doc """
  Makes a request to the API and returns a result or an error.

  ## Parameters

    * `operation` - A `t:DSpace.API.Operation.t/0`
    * `api` - A `t:DSpace.API.t/0` structure
    * `options` - Options for the request

  ## Options

    * `:transform` - Whether to transform the response. If set to false, returns a
      `t:DSpace.API.HTTP.Response.t/0` structure (defaults to true)
    * request option overrides passed to the HTTP adapter
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
  """
  @spec stream!(Operation.t(), t(), keyword()) :: Enumerable.t()
  def stream!(operation, %__MODULE__{} = api, options \\ []) when is_list(options) do
    Operation.stream!(operation, api, options)
  end
end
