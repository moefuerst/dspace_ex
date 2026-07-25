defmodule DSpace.API do
  @moduledoc """
  Represents a DSpace API client configuration.

  ## Basic Usage / Configuration

  dspace_ex doesn't prescribe the configuration strategy of consuming applications. For API
  interactions, declare a `t:t/0` structure with the necessary configuration when you need it:

      client = %DSpace.API{
        endpoint: "https://example.com/server",
        access_token: "my-access-token",
        csrf_token: "my-csrf-token"
      }

  Then, use the client struct to perform an operation with one of the request functions:

      {:ok, item} =
        "a1b2c3d4-e5f6-4a7b-8c9d-0e1f2a3b4c5d"
        |> DSpace.API.Item.fetch()
        |> DSpace.API.request(client)

  See `new/1` for all client configuration options.

  ## Session Management

  Per DSpace API contract, *all* responses need to be monitored for CSRF token updates, regardless
  of client or use context. In practice, the actual implementation of the DSpace backend does not
  currently refresh CSRF tokens with every request, only with login/logout, when the token refresh
  endpoints are called, or the client sends an invalid token.

  The optional `:on_response_hook` field allows applications to handle CSRF token updates. When
  set, the function will be invoked whenever a response header contains a CSRF token (which should
  be every response).

      client = %DSpace.API{
          endpoint: "https://example.com/server",
          on_response_hook: &MyApp.Session.update_csrf/1
      }

  The hook will receive a map with a `:csrf_token` key. Invocation is synchronous and will block
  until the hook returns. It's probably best to think about using a separate process or a task to
  invoke the function for asynchronous handling, depending on your session management strategy.

  ## API Compatibility

  The DSpace API is not versioned. Some endpoints and behaviours differ across DSpace versions and
  distributions, *including* "patch" or "minor" version bumps. Per default, operations in
  dspace_ex assume the latest DSpace release supported and may not work correctly with instances
  running older versions of DSpace.

  However, dspace_ex includes version-specific overrides where the API differences are known. To
  enable them, include the DSpace version of the instance you are connecting to in the client
  struct:

  <!-- tabs-open -->

  ### DSpace

      client = %DSpace.API{
        endpoint: "https://example.com/server",
        api_version: "7.6.2"
      }

  ### CRIS fork

  If your connect to an instance running the DSpace-CRIS fork, set the `cris_version` field
  instead of `api_version` in the client struct:

      client = %DSpace.API{
        endpoint: "https://example.com/server",
        cris_version: "2023.02.07"
      }

  If you target a version prior to the `2023.01.01` release, please review the
  `m:DSpace.API.Version#module-cris-fork-compatibility` module documentation.

  <!-- tabs-close -->

  Doing so will

    * adjust operation behaviour to the targeted DSpace version
    * return a `t:DSpace.API.Operation.Error.t/0` when you try to perform an operation that is not
      supported on the targeted instance instead of making a request to the server

  ### Configuring version information at runtime

  There might be scenarios where the API version of the DSpace instance you are interacting with
  is not available at compile time of your application. To initialise or update a client
  configuration from a live API directly, see `load_version/1`. To source the API version for
  other configuration strategies, use the operation `DSpace.API.Version.fetch/0`.
  """

  import DSpace.Utils

  alias DSpace.API.Auth
  alias DSpace.API.Operation
  alias DSpace.API.Transform
  alias DSpace.API.Version

  @external_resource lib_version = DSpace.MixProject.project()[:version]
  @user_agent "dspace-ex/#{lib_version}"

  @derive {Inspect, except: [:access_token, :csrf_token]}
  defstruct endpoint: %URI{},
            access_token: nil,
            csrf_token: nil,
            api_version: nil,
            cris_version: nil,
            user_agent: @user_agent,
            http_impl: {DSpace.API.HTTP.Req, []},
            on_response_hook: nil

  @typedoc """
  A DSpace API client structure.
  """
  @type t :: %__MODULE__{
          endpoint: URI.t() | binary() | (-> term()),
          access_token: nil | binary(),
          csrf_token: nil | binary(),
          api_version: nil | binary(),
          cris_version: nil | binary(),
          user_agent: binary(),
          http_impl: {module(), keyword()},
          on_response_hook: nil | (map() -> :ok)
        }

  # Public API

  @doc """
  Creates a new API client structure.

  ## Parameters

  This function takes either

    * a keyword list of attributes or
    * a single argument that represents the DSpace API endpoint; either as
      * an `t:URI.t/0` structure
      * a string
      * a 0-arity function that returns a `t:URI.t/0` structure or a string

  ## Attributes

    * `endpoint` - The DSpace API endpoint, e.g. https://example.com/server. Can be either
      * an `t:URI.t/0` structure
      * a string
      * a 0-arity function that returns a `t:URI.t/0` structure or a string
    * `:access_token` - Optional login token or API key used for authentication
    * `:csrf_token` - Optional CSRF token. Needed for all modifying requests
    * `:api_version` - Optional base DSpace API version as a string, e.g. `10.0.0`
    * `:cris_version` - Optional CRIS fork release version, e.g. `2025.02.00` or
      `cris-2025.02.00`
    * `:user_agent` - Optional User agent string, defaults to `#{@user_agent}`
    * `:http_impl` - Optional HTTP adapter implementation and options as `{module, options}`
    * `:on_response_hook` - Optional callback function invoked when CSRF tokens are updated
  """
  @doc group: "Struct API"
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
    * `endpoint` - The DSpace API endpoint, e.g. https://example.com/server. Can be either
      * an `t:URI.t/0` structure
      * a string
      * a 0-arity function that returns a `t:URI.t/0` structure or a string
  """
  @doc group: "Struct API"
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
  @doc group: "Struct API"
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
  @doc group: "Struct API"
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
  @doc group: "Struct API"
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
  @doc group: "Struct API"
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
  @doc group: "Struct API"
  @spec put_user_agent(t(), user_agent :: binary()) :: t()
  def put_user_agent(%__MODULE__{} = api, user_agent) when is_nonempty_binary(user_agent) do
    %{api | user_agent: user_agent}
  end

  @doc """
  Updates the API version.

  ## Parameters

    * `api` - A `t:DSpace.API.t/0` structure
    * `version` - Base DSpace API version as a string, e.g. `10.0.0`
  """
  @doc group: "Struct API"
  @spec put_api_version(t(), version :: binary()) :: t()
  def put_api_version(%__MODULE__{} = api, version) when is_nonempty_binary(version) do
    %{api | api_version: version}
  end

  @doc """
  Updates the CRIS fork release version.

  ## Parameters

    * `api` - A `t:DSpace.API.t/0` structure
    * `version` - DSpace-CRIS release version as a string, with or without the `cris-` prefix,
      e.g. `2025.02.00`
  """
  @doc group: "Struct API"
  @spec put_cris_version(t(), version :: binary()) :: t()
  def put_cris_version(%__MODULE__{} = api, version) when is_nonempty_binary(version) do
    %{api | cris_version: version}
  end

  @doc """
  Fetches version information from a DSpace API and returns an updated client structure.

  Returns the passed `t:DSpace.API.t/0` client structure unchanged if the version information
  cannot be retrieved.

  ## Parameters

    * `api` - A `t:DSpace.API.t/0` structure

  ## Example

      client =
        [endpoint: "https://example.com/server"]
        |> DSpace.API.new()
        |> DSpace.API.load_version()
  """
  @doc group: "Client helpers"
  @doc since: "0.2.0"
  @spec load_version(t()) :: t()
  def load_version(%__MODULE__{} = api) do
    case request(Version.fetch(), api) do
      {:ok, version} ->
        %{api | api_version: version.api_version, cris_version: version.cris_version}

      _ ->
        api
    end
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
  @doc group: "Client helpers"
  @spec login(t(), username, password) :: {:ok, t()} | {:error, Exception.t()}
        when username: binary(), password: binary()
  def login(%__MODULE__{} = api, username, password) when is_nonempty_binary(username) and is_nonempty_binary(password) do
    login = Auth.login(username, password)

    case request(login, api, transform: &Transform.tokens_from_response/1) do
      {:ok, {auth_token, csrf_token}} -> {:ok, %{api | access_token: auth_token, csrf_token: csrf_token}}
      {:error, _reason} = error -> error
    end
  end

  @doc """
  Authenticates the client with a DSpace API and raises on errors.

  Similar to `login/3`, but returns the updated client structure directly or raises on errors.
  """
  @doc group: "Client helpers"
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

  Most users will prefer to stream operations that return paginated results, as `stream!/3` wraps
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
  @doc group: "Requests"
  @spec next_page(Operation.JSON.t(), binary()) :: Operation.JSON.t()
  def next_page(%Operation.JSON{} = operation, next_url) when is_nonempty_binary(next_url) do
    # `next_url` is already fully built, so we drop the params of the initial operation
    %{operation | path: next_url, params: []}
  end

  @doc """
  Verifies if the passed client is authenticated with a DSpace API.

  Returns `false` if the server indicates the client is not authenticated, or if the server is
  unreachable. Callers who want to separate transport errors from authentication status should
  request `DSpace.API.Auth.status/0` directly.

  ## Parameters

    * `api` - A `t:DSpace.API.t/0` structure
  """
  @doc group: "Client helpers"
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
  @doc group: "Requests"
  @spec request(Operation.t(), t(), keyword()) :: {:ok, term()} | {:error, Exception.t()}
  def request(operation, %__MODULE__{} = api, options \\ []) when is_list(options) do
    Operation.perform(operation, api, options)
  end

  @doc """
  Makes a request to the API and returns a result or raises an error.

  For parameters and options, see `request/3`.
  """
  @doc group: "Requests"
  @spec request!(Operation.t(), t(), keyword()) :: term()
  def request!(operation, %__MODULE__{} = api, options \\ []) when is_list(options) do
    case request(operation, api, options) do
      {:ok, result} -> result
      {:error, exception} -> raise exception
    end
  end

  @doc """
  Makes a request to the API and returns a stream.

  ## Parameters

    * `operation` - A `t:DSpace.API.Operation.t/0`
    * `api` - A `t:DSpace.API.t/0` structure
    * `options` - Keyword list of options for the request

  ## Options

    * request option overrides passed to the HTTP adapter

  ## Examples

      client = DSpace.API.new("https://example.com/server")

      stream =
        [query: "software errors"]
        |> DSpace.API.Item.find()
        |> DSpace.API.stream!(client)

      Enum.take(stream, 5)
  """
  @doc group: "Requests"
  @spec stream!(Operation.t(), t(), keyword()) :: Enumerable.t()
  def stream!(operation, %__MODULE__{} = api, options \\ []) when is_list(options) do
    Operation.stream!(operation, api, options)
  end
end
