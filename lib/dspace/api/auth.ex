defmodule DSpace.Api.Auth do
  @moduledoc false

  alias DSpace.Api

  @ep_api_key_url "/api/authn/machinetokens"
  @ep_csrf_url "/api/security/csrf"
  @ep_login_url "/api/authn/login"
  @ep_short_token_url "/api/authn/shortlivedtokens"
  @ep_status_url "/api/authn/status"

  @doc """
  Verifies if the current client is authenticated with the DSpace API.

  Also returns false if the check fails.
  """
  @spec authenticated?(api :: Api.t()) :: boolean()
  def authenticated?(%Api{} = api) do
    case Api.request(api, url: @ep_status_url) do
      {:ok, %{body: body}} -> Map.get(body, "authenticated", false)
      {:error, _} -> false
    end
  end

  @doc """
  Authenticates with the DSpace API using the provided credentials.

  Returns a client with updated tokens or an error.
  """
  @spec login(api :: Api.t(), username :: binary(), password :: binary()) ::
          {:ok, Api.t()} | {:error, DSpace.Api.Error.t() | Exception.t()}
  def login(%Api{} = api, username, password)
      when is_binary(username) and is_binary(password) do
    api_with_csrf = with_csrf_token_if_missing(api)

    api_with_csrf
    |> attempt_login(username, password)
    |> process_login_response(api_with_csrf)
  end

  @doc """
  Updates the client with a fresh access token from the API.

  Access tokens obtained via login are only valid for an amount of time. The token is a standard JWT and contains an `exp` claim that you can use to manage session validity in your application.

  Calling this function returns the client with a new freshly issued token with an extended expiration time. Managing token lifecycle (checking expiry, deciding when to refresh) is the responsibility of the consuming application.
  """
  @spec refresh_access_token(api :: Api.t()) ::
          Api.t() | {:error, DSpace.Api.Error.t() | Exception.t()}
  def refresh_access_token(%Api{access_token: token} = api) when is_binary(token) do
    case Api.request(api,
           method: :post,
           url: @ep_login_url,
           auth: token
         ) do
      {:ok, response} ->
        Api.with_access_token(api, extract_access_token(response))

      {:error, _error} = error ->
        error
    end
  end

  def refresh_access_token(%Api{} = _api) do
    raise ArgumentError, "Access token refresh operation needs an access token"
  end

  @doc """
  Updates the client with a fresh CSRF token from the API.

  This is not a "real" refresh on DSpace < 7.6.2 where the `/api/security/csrf` endpoint doesn't exist and this function uses the `/api/authn/status` endpoint instead.
  """
  @spec refresh_csrf_token(api :: Api.t()) :: Api.t()
  def refresh_csrf_token(%Api{api_version: version} = api) do
    endpoint =
      if Version.compare(version, "7.6.2") in [:gt, :eq] do
        @ep_csrf_url
      else
        @ep_status_url
      end

    case Api.request(api, url: endpoint) do
      {:ok, response} ->
        with_csrf_from_response(api, response)

      {:error, _error} = error ->
        error
    end
  end

  @doc """
  Updates the client with a CSRF token from an API response if present.
  """
  @spec with_csrf_from_response(api :: Api.t(), response :: map()) :: Api.t()
  def with_csrf_from_response(api, response) do
    case extract_csrf(response) do
      nil -> api
      token -> Api.with_csrf_token(api, token)
    end
  end

  @doc """
  Generates and fetches an API key from the API.

  In DSpace sprech the API key is called ["machine token"](https://github.com/4Science/Rest7Contract/blob/main-cris/authentication.md#request-machine-to-machine-token).
  """
  @spec fetch_api_key(api :: Api.t()) ::
          {:ok, binary()} | {:error, DSpace.Api.Error.t() | Exception.t()}
  def fetch_api_key(%Api{} = api) do
    case Api.request(api,
           method: :post,
           url: @ep_api_key_url
         ) do
      {:ok, response} ->
        extract_token_from_body(response)

      {:error, _} = error ->
        error
    end
  end

  @doc """
  Deletes an API key.

  This deletes the currently authenticated user's API key ("machine token").
  """
  @spec delete_api_key(api :: Api.t()) ::
          :ok | {:error, DSpace.Api.Error.t() | Exception.t()}
  def delete_api_key(%Api{} = api) do
    case Api.request(api,
           method: :delete,
           url: @ep_api_key_url
         ) do
      {:ok, _} -> :ok
      {:error, _} = error -> error
    end
  end

  @doc """
  Fetches a short-lived access token from the API.

  Short-lived tokens are used for operations like downloading bitstreams.
  """
  @spec fetch_short_lived_token(api :: Api.t()) ::
          {:ok, binary()} | {:error, DSpace.Api.Error.t() | Exception.t()}
  def fetch_short_lived_token(%Api{api_version: version} = api) do
    method =
      if Version.compare(version, "7.5.0") in [:gt, :eq] do
        :post
      else
        :get
      end

    case Api.request(api,
           method: method,
           url: @ep_short_token_url
         ) do
      {:ok, response} ->
        extract_token_from_body(response)

      {:error, _} = error ->
        error
    end
  end

  # Private helpers

  defp with_csrf_token_if_missing(%Api{csrf_token: token} = api) when is_binary(token), do: api
  defp with_csrf_token_if_missing(api), do: refresh_csrf_token(api)

  defp attempt_login(api, username, password) do
    form_body = URI.encode_query(user: username, password: password)

    Api.request(api,
      method: :post,
      url: @ep_login_url,
      body: form_body,
      headers: [{"content-type", "application/x-www-form-urlencoded"}],
      json: false
    )
  end

  defp process_login_response({:ok, response}, api) do
    access_token = extract_access_token(response)
    csrf = extract_csrf(response)

    updated_api =
      api
      |> Api.with_csrf_token(csrf)
      |> Api.with_access_token(access_token)

    {:ok, updated_api}
  end

  defp process_login_response(error, _api), do: error

  defp extract_csrf(%{headers: headers}) do
    token = headers["dspace-xsrf-token"]
    if is_list(token), do: List.first(token), else: token
  end

  defp extract_access_token(%{headers: headers}) do
    token = headers["authorization"]
    if is_list(token), do: List.first(token), else: token
  end

  defp extract_access_token(_), do: nil

  defp extract_token_from_body(%{body: %{"token" => token}} = _response) do
    {:ok, token}
  end

  defp extract_token_from_body(response) do
    {:error, DSpace.Api.Error.response_validation_error(response)}
  end
end
