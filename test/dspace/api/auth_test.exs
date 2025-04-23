defmodule DSpace.Api.AuthTest do
  use ExUnit.Case, async: true

  import TestHelper, only: [respond_with_json: 3]

  alias DSpace.Api
  alias DSpace.Api.Auth
  alias DSpace.Api.Error
  alias DSpace.Api.Http.Req

  @ep_api_key_url "/api/authn/machinetokens"
  @ep_csrf_url "/api/security/csrf"
  @ep_login_url "/api/authn/login"
  @ep_short_token_url "/api/authn/shortlivedtokens"
  @ep_status_url "/api/authn/status"

  setup do
    bypass = Bypass.open()

    # Disable retry to fail fast
    api =
      Api.new(url(bypass))
      |> Api.with_client_impl({Req, [json: true, retry: false]})

    {:ok, bypass: bypass, api: api}
  end

  describe "authenticated?/1" do
    test "returns true when API response indicates authenticated", %{bypass: bypass, api: api} do
      Bypass.expect_once(bypass, "GET", @ep_status_url, fn conn ->
        respond_with_json(conn, 200, ~s({"authenticated": true}))
      end)

      result = Auth.authenticated?(api)

      assert result == true, "Expected authenticated? to return true for an authenticated status"
    end

    test "returns false when API response indicates not authenticated", %{
      bypass: bypass,
      api: api
    } do
      Bypass.expect_once(bypass, "GET", @ep_status_url, fn conn ->
        respond_with_json(conn, 200, ~s({"authenticated": false}))
      end)

      result = Auth.authenticated?(api)

      assert result == false,
             "Expected authenticated? to return false for a non-authenticated status"
    end

    test "returns false when API response is missing the authenticated key", %{
      bypass: bypass,
      api: api
    } do
      Bypass.expect_once(bypass, "GET", @ep_status_url, fn conn ->
        respond_with_json(conn, 200, ~s({"some_other_key": true}))
      end)

      result = Auth.authenticated?(api)

      assert result == false,
             "Expected authenticated? to return false when the key is missing"
    end

    test "returns false on API request error", %{bypass: bypass, api: api} do
      Bypass.down(bypass)

      result = Auth.authenticated?(api)

      assert result == false,
             "Expected authenticated? to map underlying API errors to false"
    end
  end

  describe "login/3" do
    @user "test@example.com"
    @pass "password123"

    test "succeeds and updates tokens when CSRF token already exists", %{
      bypass: bypass,
      api: api
    } do
      api_with_csrf = Api.with_csrf_token(api, "abc123")
      form_body = URI.encode_query(user: @user, password: @pass)

      Bypass.expect_once(bypass, "POST", @ep_login_url, fn conn ->
        assert Plug.Conn.get_req_header(conn, "x-xsrf-token") == ["abc123"],
               "Existing CSRF token not sent in header"

        assert Plug.Conn.get_req_header(conn, "content-type") == [
                 "application/x-www-form-urlencoded"
               ],
               "Incorrect Content-Type for login"

        {:ok, req_body, conn} = Plug.Conn.read_body(conn)
        assert req_body == form_body, "Login form body not sent correctly"

        conn
        |> Plug.Conn.put_resp_header("authorization", "Bearer xyz123")
        |> Plug.Conn.put_resp_header("dspace-xsrf-token", "123abc")
        |> respond_with_json(200, ~s({"token": "xyz123"}))
      end)

      result = Auth.login(api_with_csrf, @user, @pass)

      assert {:ok, %Api{access_token: "xyz123", csrf_token: "123abc"}} =
               result,
             "Login should return updated API client with new tokens"
    end

    test "succeeds, fetching CSRF token first if missing (DSpace < 7.6.2)", %{
      bypass: bypass,
      api: api
    } do
      api_old_version = Api.with_api_version(api, "7.6.1")
      form_body = URI.encode_query(user: @user, password: @pass)

      # Expect CSRF fetch first
      Bypass.expect_once(bypass, "GET", @ep_status_url, fn conn ->
        conn
        |> Plug.Conn.put_resp_header("dspace-xsrf-token", "abc123")
        |> respond_with_json(200, ~s({"authenticated": false}))
      end)

      # Expect login afterwards
      Bypass.expect_once(bypass, "POST", @ep_login_url, fn conn ->
        assert Plug.Conn.get_req_header(conn, "x-xsrf-token") == ["abc123"],
               "Fetched CSRF token not sent in login request header"

        {:ok, req_body, conn} = Plug.Conn.read_body(conn)
        assert req_body == form_body, "Login form body not sent correctly"

        conn
        |> Plug.Conn.put_resp_header("authorization", "Bearer xyz123")
        |> Plug.Conn.put_resp_header("dspace-xsrf-token", "123abc")
        |> respond_with_json(200, ~s({"token": "xyz123"}))
      end)

      result = Auth.login(api_old_version, @user, @pass)

      assert {:ok, %Api{access_token: "xyz123", csrf_token: "123abc"}} =
               result,
             "Login should fetch CSRF and then succeed with new tokens"
    end

    test "returns error if CSRF fetch fails", %{bypass: bypass, api: api} do
      Bypass.expect_once(bypass, "GET", @ep_status_url, fn conn ->
        respond_with_json(conn, 500, ~s({"message": "CSRF Fetch Error"}))
      end)

      result = Auth.login(api, @user, @pass)

      assert {:error, %Error{type: :server_error}} = result,
             "Login should fail if the initial CSRF fetch fails"
    end

    test "returns error on login failure (e.g., 401 Unauthorized)", %{
      bypass: bypass,
      api: api
    } do
      api_with_csrf = Api.with_csrf_token(api, "abc123")

      Bypass.expect_once(bypass, "POST", @ep_login_url, fn conn ->
        respond_with_json(conn, 401, ~s({"message": "Bad credentials"}))
      end)

      result = Auth.login(api_with_csrf, @user, @pass)

      assert {:error, %Error{type: :unauthorized, message: "Bad credentials"}} = result,
             "Login should return a structured error on 401 response"
    end

    test "returns specific error for CSRF invalid during login (403)", %{
      bypass: bypass,
      api: api
    } do
      api_with_csrf = Api.with_csrf_token(api, "abc123")

      Bypass.expect_once(bypass, "POST", @ep_login_url, fn conn ->
        respond_with_json(conn, 403, ~s({"message": "CSRF token invalid"}))
      end)

      result = Auth.login(api_with_csrf, @user, @pass)

      assert {:error, %Error{type: :api_csrf_invalid}} = result,
             "Login should return :api_csrf_invalid error for CSRF 403 response"
    end
  end

  describe "refresh_access_token/1" do
    test "succeeds and updates access token", %{bypass: bypass, api: api} do
      api_with_tokens =
        api |> Api.with_access_token("xyz123") |> Api.with_csrf_token("abc123")

      Bypass.expect_once(bypass, "POST", @ep_login_url, fn conn ->
        assert Plug.Conn.get_req_header(conn, "authorization") == ["Bearer xyz123"],
               "Old access token not sent for refresh"

        conn
        |> Plug.Conn.put_resp_header("authorization", "Bearer 123xyz")
        |> Plug.Conn.put_resp_header("dspace-xsrf-token", "abc123")
        |> respond_with_json(204, "")
      end)

      result = Auth.refresh_access_token(api_with_tokens)

      assert {:ok, {"123xyz", "abc123"}} = result,
             "Refresh should return updated API client with access token changed"
    end

    test "returns error if refresh fails (e.g., 401)", %{bypass: bypass, api: api} do
      api_with_tokens =
        api |> Api.with_access_token("xyz123expired") |> Api.with_csrf_token("abc123")

      Bypass.expect_once(bypass, "POST", @ep_login_url, fn conn ->
        respond_with_json(conn, 401, ~s({"message": "Token expired"}))
      end)

      result = Auth.refresh_access_token(api_with_tokens)

      assert {:error, %Error{type: :unauthorized, message: "Token expired"}} = result,
             "Refresh should return error if API rejects the old token"
    end

    test "raises ArgumentError if called without an existing access token", %{api: api} do
      api_no_access_token = Api.with_csrf_token(api, "csrf_token")

      assert_raise(
        ArgumentError,
        ~r/access token refresh operation needs an access token/,
        fn -> Auth.refresh_access_token(api_no_access_token) end
      )
    end
  end

  describe "refresh_csrf_token/1" do
    test "uses correct endpoint and updates token for DSpace >= 7.6.2", %{
      bypass: bypass,
      api: api
    } do
      api_new_version = Api.with_api_version(api, "7.6.2") |> Api.with_csrf_token("abc123")

      Bypass.expect_once(bypass, "GET", @ep_csrf_url, fn conn ->
        assert Plug.Conn.get_req_header(conn, "x-xsrf-token") == ["abc123"],
               "No CSRF token sent for refresh request"

        conn
        |> Plug.Conn.put_resp_header("dspace-xsrf-token", "123abc")
        |> respond_with_json(204, "")
      end)

      result = Auth.refresh_csrf_token(api_new_version)

      assert {:ok, "123abc"} = result,
             "Should use /api/security/csrf endpoint and update token"
    end

    test "uses fallback endpoint and updates token for DSpace < 7.6.2", %{
      bypass: bypass,
      api: api
    } do
      api_old_version = Api.with_api_version(api, "7.6.1")

      Bypass.expect_once(bypass, "GET", @ep_status_url, fn conn ->
        conn
        |> Plug.Conn.put_resp_header("dspace-xsrf-token", "123abc")
        |> respond_with_json(200, ~s({"authenticated": false}))
      end)

      result = Auth.refresh_csrf_token(api_old_version)

      assert {:ok, "123abc"} = result,
             "Should use /api/authn/status endpoint and update token"
    end

    test "returns error if request fails", %{bypass: bypass, api: api} do
      Bypass.expect_once(bypass, "GET", @ep_status_url, fn conn ->
        respond_with_json(conn, 500, ~s({"message": "CSRF Fetch Error"}))
      end)

      result = Auth.refresh_csrf_token(api)

      assert {:error, %Error{type: :server_error}} = result,
             "Should return error if the underlying request fails"
    end
  end

  describe "fetch_api_key/1" do
    test "succeeds and returns the API key", %{bypass: bypass, api: api} do
      api_authed =
        api |> Api.with_access_token("xyz123") |> Api.with_csrf_token("abc123")

      Bypass.expect_once(bypass, "POST", @ep_api_key_url, fn conn ->
        assert Plug.Conn.get_req_header(conn, "authorization") == ["Bearer xyz123"],
               "Auth token missing"

        assert Plug.Conn.get_req_header(conn, "x-xsrf-token") == ["abc123"],
               "CSRF token missing"

        respond_with_json(conn, 200, ~s({"token": "api_key_123"}))
      end)

      result = Auth.fetch_api_key(api_authed)

      assert result == {:ok, "api_key_123"}, "Should return the fetched API key"
    end

    test "returns error on API failure", %{bypass: bypass, api: api} do
      api_authed =
        api |> Api.with_access_token("xyz123") |> Api.with_csrf_token("abc123")

      Bypass.expect_once(bypass, "POST", @ep_api_key_url, fn conn ->
        respond_with_json(conn, 403, ~s({"message": "Forbidden"}))
      end)

      result = Auth.fetch_api_key(api_authed)

      assert {:error, %Error{type: :forbidden}} = result, "Should return error on API failure"
    end

    test "returns validation error if response body is invalid", %{bypass: bypass, api: api} do
      api_authed =
        api |> Api.with_access_token("xyz123") |> Api.with_csrf_token("abc123")

      Bypass.expect_once(bypass, "POST", @ep_api_key_url, fn conn ->
        respond_with_json(conn, 200, ~s({"wrong_key": "value"}))
      end)

      result = Auth.fetch_api_key(api_authed)

      assert {:error, %Error{type: :api_response_validation, response: resp}} = result,
             "Should return validation error for invalid response body"

      assert resp.body == %{"wrong_key" => "value"}
    end
  end

  describe "delete_api_key/1" do
    test "succeeds and returns :ok", %{bypass: bypass, api: api} do
      api_authed =
        api |> Api.with_access_token("xyz123") |> Api.with_csrf_token("abc123")

      Bypass.expect_once(bypass, "DELETE", @ep_api_key_url, fn conn ->
        assert Plug.Conn.get_req_header(conn, "authorization") == ["Bearer xyz123"],
               "Auth token missing"

        assert Plug.Conn.get_req_header(conn, "x-xsrf-token") == ["abc123"],
               "CSRF token missing"

        respond_with_json(conn, 204, "")
      end)

      result = Auth.delete_api_key(api_authed)

      assert result == :ok, "Should return :ok on successful deletion"
    end

    test "returns error on API failure", %{bypass: bypass, api: api} do
      api_authed =
        api |> Api.with_access_token("xyz123") |> Api.with_csrf_token("abc123")

      Bypass.expect_once(bypass, "DELETE", @ep_api_key_url, fn conn ->
        respond_with_json(conn, 404, ~s({"message": "Not Found"}))
      end)

      result = Auth.delete_api_key(api_authed)

      assert {:error, %Error{type: :not_found}} = result, "Should return error on API failure"
    end
  end

  describe "fetch_short_lived_token/1" do
    test "uses POST and returns token for DSpace >= 7.5.0", %{bypass: bypass, api: api} do
      api_new_version =
        api
        |> Api.with_api_version("7.5.0")
        |> Api.with_access_token("xyz123")
        |> Api.with_csrf_token("abc123")

      Bypass.expect_once(bypass, "POST", @ep_short_token_url, fn conn ->
        assert Plug.Conn.get_req_header(conn, "authorization") == ["Bearer xyz123"],
               "Auth token missing"

        assert Plug.Conn.get_req_header(conn, "x-xsrf-token") == ["abc123"],
               "CSRF token missing"

        respond_with_json(conn, 200, ~s({"token": "shorty123"}))
      end)

      result = Auth.fetch_short_lived_token(api_new_version)

      assert result == {:ok, "shorty123"}, "Should return token fetched via POST"
    end

    test "uses GET and returns token for DSpace < 7.5.0", %{bypass: bypass, api: api} do
      api_old_version =
        api |> Api.with_api_version("7.4.0") |> Api.with_access_token("xyz123")

      Bypass.expect_once(bypass, "GET", @ep_short_token_url, fn conn ->
        assert Plug.Conn.get_req_header(conn, "authorization") == ["Bearer xyz123"],
               "Auth token missing"

        respond_with_json(conn, 200, ~s({"token": "shorty123"}))
      end)

      result = Auth.fetch_short_lived_token(api_old_version)

      assert result == {:ok, "shorty123"}, "Should return token fetched via GET"
    end

    test "returns error on API failure", %{bypass: bypass, api: api} do
      api_authed =
        api |> Api.with_api_version("7.4.0") |> Api.with_access_token("xyz123")

      Bypass.expect_once(bypass, "GET", @ep_short_token_url, fn conn ->
        respond_with_json(conn, 401, ~s({"message": "Unauthorized"}))
      end)

      result = Auth.fetch_short_lived_token(api_authed)

      assert {:error, %Error{type: :unauthorized}} = result, "Should return error on API failure"
    end

    test "returns validation error if response body is invalid", %{bypass: bypass, api: api} do
      api_authed =
        api |> Api.with_api_version("7.4.0") |> Api.with_access_token("xyz123")

      Bypass.expect_once(bypass, "GET", @ep_short_token_url, fn conn ->
        respond_with_json(conn, 200, ~s({"invalid": "body"}))
      end)

      result = Auth.fetch_short_lived_token(api_authed)

      assert {:error, %Error{type: :api_response_validation, response: resp}} = result,
             "Should return validation error for invalid response body"

      assert resp.body == %{"invalid" => "body"}
    end
  end

  describe "with_csrf_from_response/2" do
    test "updates client with CSRF token from headers", %{api: api} do
      response = %{headers: %{"dspace-xsrf-token" => "abc123"}}

      updated_api = Auth.with_csrf_from_response(api, response)

      assert updated_api.csrf_token == "abc123",
             "Expected CSRF token to be extracted from headers"
    end

    test "updates client with first CSRF token if header value is a list", %{api: api} do
      response = %{headers: %{"dspace-xsrf-token" => ["abc123", "def456"]}}

      updated_api = Auth.with_csrf_from_response(api, response)

      assert updated_api.csrf_token == "abc123",
             "Expected first CSRF token from list header to be extracted"
    end

    test "returns original client if CSRF token header is missing", %{api: api} do
      api_with_token = Api.with_csrf_token(api, "abc123")

      response = %{headers: %{"other-header" => "value"}}

      updated_api = Auth.with_csrf_from_response(api_with_token, response)

      assert updated_api.csrf_token == "abc123",
             "Client should remain unchanged if response contains no CSRF header"

      assert updated_api == api_with_token, "The original client struct should be returned"
    end
  end

  defp url(bypass), do: "http://localhost:#{bypass.port}"
end
