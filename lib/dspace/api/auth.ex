defmodule DSpace.API.Auth do
  @moduledoc """
  Authentication and token management.

  This module provides functions for authenticating with a DSpace API and managing CSRF tokens as
  well as different kinds of access tokens.
  """

  import DSpace.Utils, only: [is_nonempty_binary: 1]

  alias DSpace.API
  alias DSpace.API.Error
  alias DSpace.API.HTTP.Response
  alias DSpace.API.Operation

  @ep_auth "/api/authn"
  @ep_auth_status @ep_auth <> "/status"
  @ep_login @ep_auth <> "/login"
  @ep_logout @ep_auth <> "/logout"
  @ep_api_key @ep_auth <> "/machinetokens"
  @ep_shortlived_token @ep_auth <> "/shortlivedtokens"
  @ep_csrf "/api/security/csrf"

  @doc """
  Authenticates with the DSpace API using the provided credentials.

  Returns an operation to get an access token. Executing this operation will fetch a CSRF token
  from the API first if none is configured in the client, since that is a prerequisite for hitting
  the login endpoint.

  Managing token lifecycle (checking expiry, deciding when to refresh) is the responsibility of
  the consuming application. The token is a JWT and contains an `exp` claim. See
  `refresh_access_token/0`.
  """
  @spec login(binary(), binary()) :: Operation.t()
  def login(username, password) when is_nonempty_binary(username) and is_nonempty_binary(password) do
    login_operation = %Operation.JSON{
      path: @ep_login,
      http_method: :post,
      content_type: :form,
      data: %{user: username, password: password},
      transformer: &access_token_from_response/1
    }

    # Prefetches a CSRF token when the client doesn't carry one yet, since hitting the login
    # endpoint requires it.
    Operation.Chain.new([
      &maybe_fetch_csrf/2,
      &login_with_csrf(&1, &2, login_operation)
    ])
  end

  @doc """
  Invalidates all access tokens associated with the user's current session.
  """
  @spec logout() :: Operation.t()
  def logout do
    %Operation.JSON{
      path: @ep_logout,
      http_method: :post,
      transformer: fn _ -> :ok end
    }
  end

  @doc """
  Retrieves a fresh access token from the API.

  Executing this operation returns a freshly issued token with an extended expiration time.
  """
  @spec refresh_access_token() :: Operation.t()
  def refresh_access_token do
    %Operation.JSON{
      path: @ep_login,
      http_method: :post,
      transformer: &access_token_from_response/1
    }
  end

  @doc """
  Retrieves a fresh CSRF token from the API.

  This is not a "real" refresh on DSpace < 7.6.2 where the `/api/security/csrf` endpoint doesn't
  exist and this function uses the `/api/authn/status` endpoint instead.
  """
  @spec refresh_csrf_token() :: Operation.t()
  def refresh_csrf_token do
    %Operation.JSON{
      path: @ep_csrf,
      expected_status: [204],
      transformer: &csrf_token_from_response/1,
      version_overrides: [
        {"< 7.6.2", [path: @ep_auth_status, expected_status: [200]]}
      ]
    }
  end

  @doc """
  Fetches an API key for the currently authenticated user.

  In DSpace-CRIS-speak the API key is called "machine token". The returned token is valid until
  manually revoked using `delete_api_key/0`.
  """
  @spec fetch_api_key() :: Operation.t()
  def fetch_api_key do
    %Operation.JSON{
      path: @ep_api_key,
      http_method: :post,
      transformer: &token_from_response/1
    }
  end

  @doc """
  Deletes an API key.

  Executing this operation invalidates the currently authenticated user's API key
  ("machine token").
  """
  @spec delete_api_key() :: Operation.t()
  def delete_api_key do
    %Operation.JSON{
      path: @ep_api_key,
      http_method: :delete
    }
  end

  @doc """
  Fetches a short-lived access token from the API.

  Short-lived tokens are used for operations like downloading restricted files.
  """
  @spec fetch_short_lived_token() :: Operation.t()
  def fetch_short_lived_token do
    %Operation.JSON{
      path: @ep_shortlived_token,
      http_method: :post,
      transformer: &token_from_response/1,
      version_overrides: [
        {"< 7.5.0", [http_method: :get]}
      ]
    }
  end

  @doc """
  Verifies if the client is authenticated with the DSpace API.

  Performing this operation will return `{:ok, true}` or `{:ok, false}`.
  """
  @spec status() :: Operation.t()
  def(status) do
    %Operation.JSON{
      path: @ep_auth_status,
      transformer: &API.Transform.get(&1, "authenticated", false)
    }
  end

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

  # Private helpers

  defp maybe_fetch_csrf(_nil, %{client: %API{csrf_token: token}} = context) when is_nonempty_binary(token) do
    {:skip, context}
  end

  defp maybe_fetch_csrf(_nil, %{client: %API{csrf_token: nil}} = context) do
    {refresh_csrf_token(), context}
  end

  defp login_with_csrf(csrf_token, context, login_operation) do
    {login_operation, put_csrf_token(context, csrf_token)}
  end

  defp put_csrf_token(context, token) when is_nonempty_binary(token) do
    %{context | client: %{context.client | csrf_token: token}}
  end

  defp put_csrf_token(context, nil), do: context

  defp token_from_response(%Response{} = response) do
    case extract_token_from_body(response) do
      {:ok, token} -> token
      {:error, :token_missing} -> {:error, Error.response_validation_error(response)}
    end
  end

  defp access_token_from_response(%Response{} = response) do
    case extract_access_token(response) do
      {:ok, token} -> token
      {:error, :access_token_missing} -> {:error, Error.response_validation_error(response)}
    end
  end

  defp csrf_token_from_response(%Response{} = response) do
    case extract_csrf(response) do
      {:ok, token} -> token
      {:error, :csrf_token_missing} -> {:error, Error.response_validation_error(response)}
    end
  end

  defp extract_token_from_body(%{body: %{"token" => token}} = _response) when is_nonempty_binary(token) do
    {:ok, token}
  end

  defp extract_token_from_body(_response), do: {:error, :token_missing}

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
end
