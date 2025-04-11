defmodule DSpace.Api.Auth do
  @moduledoc false

  alias DSpace.Api

  @ep_login_url "/api/authn/login"
  @ep_status_url "/api/authn/status"
  @ep_csrf_url "/api/security/csrf"

  @doc """
  Verifies if the current client is authenticated with the DSpace backend.

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
          {:ok, Api.t()} | {:error, DSpace.Api.Error.t()}
  def login(%Api{} = api, username, password)
      when is_binary(username) and is_binary(password) do
    api_with_csrf = with_csrf_token_if_missing(api)

    api_with_csrf
    |> attempt_login(username, password)
    |> process_login_response(api_with_csrf, username, password)
  end

  @doc """
  Gets a fresh CSRF token from the API.

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
      {:ok, response} -> Api.with_token_from_response(api, response)
      {:error, _error} -> api
    end
  end

  # Private helpers

  defp with_csrf_token_if_missing(%Api{csrf_token: token} = api) when is_binary(token), do: api
  defp with_csrf_token_if_missing(api), do: refresh_csrf_token(api)

  defp attempt_login(api, username, password) do
    {client_impl, _} = api.client_impl

    # Bypass the standard request pipeline, because it's configured for JSON.
    # This is the only time we need a form request.
    form_body = URI.encode_query(user: username, password: password)

    result =
      DSpace.Api.Http.request(client_impl,
        method: :post,
        base_url: api.endpoint,
        url: @ep_login_url,
        body: form_body,
        headers: [
          {"content-type", "application/x-www-form-urlencoded"},
          {"x-xsrf-token", api.csrf_token}
        ]
      )

    DSpace.Api.Response.normalize(result)
  end

  defp process_login_response({:ok, response}, api, _username, _password) do
    access_token = extract_access_token(response)

    updated_api =
      %Api{}
      |> Api.with_endpoint(api.endpoint)
      |> Api.with_token_from_response(response)
      |> Api.with_access_token(access_token)

    {:ok, updated_api}
  end

  defp process_login_response(error, _api, _username, _password), do: error

  defp extract_access_token(%{headers: headers}) do
    token = headers["authorization"]
    if is_list(token), do: List.first(token), else: token
  end

  defp extract_access_token(_), do: nil
end
