defmodule DSpace.API do
  @moduledoc """
  Represents a DSpace API client configuration.
  """

  import DSpace.API.Utils

  alias DSpace.API.Operation

  @external_resource version = DSpace.MixProject.project()[:version]

  # DSpace 7.6.1
  @api_version "7.6.1"
  @user_agent "dspace-ex/#{version}"
  @default_http_impl {DSpace.API.HTTP.Req, []}

  @derive {Inspect, except: [:access_token, :csrf_token]}
  defstruct endpoint: %URI{},
            access_token: nil,
            csrf_token: nil,
            api_version: @api_version,
            user_agent: @user_agent,
            http_impl: @default_http_impl,
            session_callback: nil

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
          session_callback: nil | (map() -> :ok)
        }

  # Public API

  @doc """
  Creates a new client.

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
    * `:access_token` - Optional login token or API key used for authentication. This is a JWT
    * `:csrf_token` - Optional CSRF token. Needed for all modifying requests
    * `:api_version` - Optional DSpace API version as a string, defaults to latest version
      `dspace-ex` was fully tested against
    * `:user_agent` - Optional User agent string, defaults to `dspace-ex/<version>`
    * `:http_impl` - Optional HTTP adapter implementation and options as `{module, options}`
    * `:session_callback` - Optional callback function invoked when CSRF tokens are updated
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
    * `api` - A `t:DSpace.API.t/0` structure.
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
    * `api` - A `t:DSpace.API.t/0` structure.
    * `access_token` - Login token or API key as a string
  """
  @spec put_access_token(t(), binary()) :: t()
  def put_access_token(%__MODULE__{} = api, access_token) when is_nonempty_binary(access_token) do
    %{api | access_token: access_token}
  end

  @doc """
  Updates the CSRF token.

  ## Parameters
    * `api` - A `t:DSpace.API.t/0` structure.
    * `csrf_token` - CSRF token as a string
  """
  @spec put_csrf_token(t(), binary()) :: t()
  def put_csrf_token(%__MODULE__{} = api, csrf_token) when is_nonempty_binary(csrf_token) do
    %{api | csrf_token: csrf_token}
  end

  @doc """
  Updates the session callback function.

  ## Parameters
    * `api` - A `t:DSpace.API.t/0` structure.
    * `session_callback` - A 1-arity function invoked when CSRF tokens are updated, or `nil` to
      disable.
  """
  @spec put_session_callback(t(), (map() -> :ok) | nil) :: t()
  def put_session_callback(%__MODULE__{} = api, session_callback)
      when is_function(session_callback, 1) or is_nil(session_callback) do
    %{api | session_callback: session_callback}
  end

  @doc """
  Updates the HTTP adapter implementation.

  ## Parameters
    * `api` - A `t:DSpace.API.t/0` structure.
    * `http_impl` - A tuple of `{module, options}` where module implements `DSpace.API.HTTP`
      behaviour
  """
  @spec put_http_impl(t(), {module(), keyword()}) :: t()
  def put_http_impl(%__MODULE__{} = api, {module, options} = http_impl) when is_atom(module) and is_list(options) do
    %{api | http_impl: http_impl}
  end

  @doc """
  Updates the user agent.

  ## Parameters
    * `api` - A `t:DSpace.API.t/0` structure.
    * `user_agent` - User agent as a string
  """
  @spec put_user_agent(t(), binary()) :: t()
  def put_user_agent(%__MODULE__{} = api, user_agent) when is_nonempty_binary(user_agent) do
    %{api | user_agent: user_agent}
  end

  @doc """
  Updates the API version.

  ## Parameters
    * `api` - A `t:DSpace.API.t/0` structure.
    * `version` - DSpace API version as a string
  """
  @spec put_api_version(t(), binary()) :: t()
  def put_api_version(%__MODULE__{} = api, version) when is_nonempty_binary(version) do
    %{api | api_version: version}
  end

  @doc """
  Makes a request to the API and returns a result or an error.

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
  """
  @spec stream!(Operation.t(), t(), keyword()) :: Enumerable.t()
  def stream!(operation, %__MODULE__{} = api, options \\ []) when is_list(options) do
    Operation.stream!(operation, api, options)
  end
end
