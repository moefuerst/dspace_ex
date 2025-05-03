defmodule DSpace.Api.Auth do
  @moduledoc false

  alias DSpace.Api
  alias DSpace.Api.Error

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
          {:ok, Api.t()} | {:error, Error.t() | Exception.t()}
  def login(%Api{} = api, username, password) when is_binary(username) and is_binary(password) do
    with {:ok, api_with_csrf} <- with_csrf_token_if_missing(api),
         {:ok, response} <- attempt_login(api_with_csrf, username, password),
         {:ok, {access_token, csrf_token}} <- process_token_response(response) do
      {:ok, api |> Api.with_csrf_token(csrf_token) |> Api.with_access_token(access_token)}
    else
      {:error, _} = error -> error
    end
  end

  @doc """
  Retrieves a fresh access token from the API.

  Access tokens obtained via login are only valid for an amount of time. The token is a standard JWT and contains an `exp` claim that you can use to manage session validity in your application.

  Calling this function returns a new freshly issued token with an extended expiration time. Managing token lifecycle (checking expiry, deciding when to refresh) is the responsibility of the consuming application.
  """
  @spec refresh_access_token(api :: Api.t()) ::
          {:ok, {access :: binary(), csrf :: binary()}}
          | {:error, Error.t() | Exception.t()}
  def refresh_access_token(%Api{access_token: token} = api) when is_binary(token) do
    case Api.request(api, method: :post, url: @ep_login_url) do
      {:ok, response} -> process_token_response(response)
      {:error, _} = error -> error
    end
  end

  def refresh_access_token(%Api{} = _api) do
    raise ArgumentError, "access token refresh operation needs an access token"
  end

  @doc """
  Retrieves a fresh CSRF token from the API.

  This is not a "real" refresh on DSpace < 7.6.2 where the `/api/security/csrf` endpoint doesn't exist and this function uses the `/api/authn/status` endpoint instead.
  """
  @spec refresh_csrf_token(api :: Api.t()) ::
          {:ok, csrf :: binary()} | {:error, Error.t() | Exception.t()}
  def refresh_csrf_token(%Api{api_version: version} = api) do
    endpoint =
      if Version.compare(version, "7.6.2") in [:gt, :eq] do
        @ep_csrf_url
      else
        @ep_status_url
      end

    case Api.request(api, url: endpoint) do
      {:ok, response} -> process_csrf_response(response)
      {:error, _} = error -> error
    end
  end

  @doc """
  Updates the client with a CSRF token from an API response if present.
  """
  @spec with_csrf_from_response(api :: Api.t(), response :: map()) :: Api.t()
  def with_csrf_from_response(api, response) do
    case extract_csrf(response) do
      {:ok, token} -> Api.with_csrf_token(api, token)
      {:error, :csrf_token_missing} -> api
    end
  end

  @doc """
  Generates and fetches an API key from the API.

  In DSpace sprech the API key is called ["machine token"](https://github.com/4Science/Rest7Contract/blob/main-cris/authentication.md#request-machine-to-machine-token).
  """
  @spec fetch_api_key(api :: Api.t()) ::
          {:ok, binary()} | {:error, Error.t() | Exception.t()}
  def fetch_api_key(%Api{access_token: token} = api) when is_binary(token) do
    case Api.request(api,
           method: :post,
           url: @ep_api_key_url
         ) do
      {:ok, response} -> extract_token_from_body(response)
      {:error, _} = error -> error
    end
  end

  def fetch_api_key(%Api{} = _api) do
    raise ArgumentError, "generating API key operation needs an access token"
  end

  @doc """
  Deletes an API key.

  This deletes the currently authenticated user's API key ("machine token").
  """
  @spec delete_api_key(api :: Api.t()) ::
          :ok | {:error, Error.t() | Exception.t()}
  def delete_api_key(%Api{access_token: token} = api) when is_binary(token) do
    case Api.request(api,
           method: :delete,
           url: @ep_api_key_url
         ) do
      {:ok, _response} -> :ok
      {:error, _} = error -> error
    end
  end

  def delete_api_key(%Api{} = _api) do
    raise ArgumentError, "deleting API key operation needs an access token"
  end

  @doc """
  Fetches a short-lived access token from the API.

  Short-lived tokens are used for operations like downloading bitstreams.
  """
  @spec fetch_short_lived_token(api :: Api.t()) ::
          {:ok, binary()} | {:error, Error.t() | Exception.t()}
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
      {:ok, response} -> extract_token_from_body(response)
      {:error, _} = error -> error
    end
  end

  # Private helpers

  defp with_csrf_token_if_missing(%Api{csrf_token: token} = api) when is_binary(token),
    do: {:ok, api}

  defp with_csrf_token_if_missing(api) do
    case refresh_csrf_token(api) do
      {:ok, token} -> {:ok, Api.with_csrf_token(api, token)}
      {:error, _} = error -> error
    end
  end

  defp attempt_login(api, username, password) do
    form_body = URI.encode_query(user: username, password: password)

    Api.request(api,
      method: :post,
      url: @ep_login_url,
      body: form_body,
      headers: [
        {"content-type", "application/x-www-form-urlencoded"},
        {"x-xsrf-token", api.csrf_token}
      ],
      json: false
    )
  end

  defp process_token_response(response) do
    with {:ok, access_token} <- extract_access_token(response),
         {:ok, csrf_token} <- extract_csrf(response) do
      {:ok, {access_token, csrf_token}}
    else
      _ ->
        {:error,
         Error.response_validation_error(
           response,
           "Token response missing required tokens"
         )}
    end
  end

  defp process_csrf_response(response) do
    case extract_csrf(response) do
      {:ok, token} ->
        {:ok, token}

      {:error, :csrf_token_missing} ->
        {:error,
         Error.response_validation_error(
           response,
           "Token refresh response missing CSRF token"
         )}
    end
  end

  defp extract_csrf(%{headers: %{"dspace-xsrf-token" => [token | _]}}), do: {:ok, token}

  defp extract_csrf(%{headers: %{"dspace-xsrf-token" => token}}) when is_binary(token),
    do: {:ok, token}

  defp extract_csrf(_), do: {:error, :csrf_token_missing}

  # Note: DSpace returns the access token in the *response's* `authorization` header, which is a misuse
  # per RFC 7235 (intended for client-to-server *requests*). This approach diverges from OAuth standards
  # (e.g. RFC 6749) and OWASP recommendations, and potentially breaks compatibility with tools, proxies,
  # and browsers.
  defp extract_access_token(%{headers: %{"authorization" => auth}}) do
    case normalize_auth_header(auth) do
      "Bearer " <> token -> {:ok, token}
      token when is_binary(token) -> {:ok, token}
      _ -> {:error, :invalid_auth_header}
    end
  end

  defp extract_access_token(_), do: {:error, :missing_auth_header}

  defp normalize_auth_header([auth | _]) when is_binary(auth), do: auth
  defp normalize_auth_header(auth) when is_binary(auth), do: auth
  defp normalize_auth_header(_), do: nil

  defp extract_token_from_body(%{body: %{"token" => token}} = _response) do
    {:ok, token}
  end

  defp extract_token_from_body(response) do
    {:error, Error.response_validation_error(response)}
  end
end
