defmodule DSpace.API.AuthTest do
  use DSpace.API.Case, async: true

  alias DSpace.API
  alias DSpace.API.Auth
  alias DSpace.API.Error

  describe "login/2" do
    @user "test@example.com"
    @pass "password123"

    test "operation returns token when executed successfully with existing CSRF", %{
      bypass: bypass,
      api: api
    } do
      form_body = URI.encode_query(user: @user, password: @pass)

      Bypass.expect(bypass, fn conn ->
        assert Plug.Conn.get_req_header(conn, "x-xsrf-token") == ["abc123"]

        assert Plug.Conn.get_req_header(conn, "content-type") == [
                 "application/x-www-form-urlencoded"
               ]

        {:ok, req_body, conn} = Plug.Conn.read_body(conn)
        assert req_body == form_body

        conn
        |> Plug.Conn.put_resp_header("authorization", "Bearer xyz123")
        |> respond_with_json(200, ~s({"token": "xyz123"}))
      end)

      operation = Auth.login(@user, @pass)
      {:ok, token} = API.request(operation, api)

      assert token == "xyz123"
    end

    test "operation fetches CSRF when missing", %{bypass: bypass, api: api} do
      api = %{api | csrf_token: nil}
      form_body = URI.encode_query(user: @user, password: @pass)

      # Expect CSRF fetch
      Bypass.expect_once(bypass, "GET", "/api/security/csrf", fn conn ->
        conn
        |> Plug.Conn.put_resp_header("dspace-xsrf-token", "auto-csrf-123")
        |> respond_with_json(204, "")
      end)

      # Expect login
      Bypass.expect_once(bypass, "POST", "/api/authn/login", fn conn ->
        assert Plug.Conn.get_req_header(conn, "x-xsrf-token") == ["auto-csrf-123"]

        {:ok, req_body, conn} = Plug.Conn.read_body(conn)
        assert req_body == form_body

        conn
        |> Plug.Conn.put_resp_header("authorization", "Bearer auto-token-456")
        |> respond_with_json(200, ~s({"token": "auto-token-456"}))
      end)

      operation = Auth.login(@user, @pass)
      {:ok, token} = API.request(operation, api)

      assert token == "auto-token-456"
    end

    test "operation returns error when request fails", %{bypass: bypass, api: api} do
      Bypass.expect(bypass, fn conn ->
        respond_with_json(conn, 401, ~s({"message": "Bad credentials"}))
      end)

      operation = Auth.login(@user, @pass)
      {:error, error} = API.request(operation, api)

      assert %Error{type: :unauthorized} = error
    end

    test "operation crashes when CSRF fetch fails", %{bypass: bypass, api: api} do
      api = %{api | csrf_token: nil}

      # Expect CSRF fetch
      Bypass.expect(bypass, "GET", "/api/security/csrf", fn conn ->
        respond_with_json(conn, 500, ~s({"message": "CSRF Fetch Error"}))
      end)

      operation = Auth.login(@user, @pass)

      assert_raise ArgumentError, "executing this operation requires a CSRF token", fn ->
        API.request(operation, api)
      end
    end
  end

  describe "fetch_api_key/0" do
    setup %{bypass: bypass, api: api} do
      api_with_tokens = %{api | access_token: "xyz123", csrf_token: "abc123"}
      %{bypass: bypass, api: api_with_tokens}
    end

    test "operation returns token when executed successfully", %{bypass: bypass, api: api} do
      Bypass.expect(bypass, fn conn ->
        assert Plug.Conn.get_req_header(conn, "authorization") == ["Bearer xyz123"]
        assert Plug.Conn.get_req_header(conn, "x-xsrf-token") == ["abc123"]

        respond_with_json(conn, 200, ~s({"token": "api_key_123"}))
      end)

      operation = Auth.fetch_api_key()
      {:ok, result} = API.request(operation, api)

      assert result == "api_key_123"
    end

    test "operation returns error when request fails", %{bypass: bypass, api: api} do
      Bypass.expect(bypass, fn conn ->
        respond_with_json(conn, 500, ~s({"message": "Server Error"}))
      end)

      operation = Auth.fetch_api_key()
      {:error, error} = API.request(operation, api)

      assert %Error{type: :server_error} = error
    end

    test "operation returns error when response body is invalid", %{bypass: bypass, api: api} do
      Bypass.expect(bypass, fn conn ->
        respond_with_json(conn, 200, ~s({"invalid": "response"}))
      end)

      operation = Auth.fetch_api_key()
      {:error, error} = API.request(operation, api)

      assert %Error{type: :api_unexpected_payload} = error
    end
  end

  describe "refresh_csrf_token/0" do
    test "operation returns token when executed successfully", %{bypass: bypass, api: api} do
      api = %{api | api_version: "7.6.2"}

      Bypass.expect_once(bypass, "GET", "/api/security/csrf", fn conn ->
        conn
        |> Plug.Conn.put_resp_header("dspace-xsrf-token", "fresh-csrf-token")
        |> respond_with_json(204, "")
      end)

      operation = Auth.refresh_csrf_token()
      {:ok, token} = API.request(operation, api)

      assert token == "fresh-csrf-token"
    end

    test "operation returns error when request fails", %{bypass: bypass, api: api} do
      Bypass.expect_once(bypass, fn conn ->
        respond_with_json(conn, 500, ~s({"message": "Server Error"}))
      end)

      operation = Auth.refresh_csrf_token()
      {:error, error} = API.request(operation, api)

      assert %Error{type: :server_error} = error
    end

    test "uses fallback endpoint for older DSpace versions", %{bypass: bypass, api: api} do
      api_old = %{api | api_version: "7.6.1"}

      Bypass.expect_once(bypass, "GET", "/api/authn/status", fn conn ->
        conn
        |> Plug.Conn.put_resp_header("dspace-xsrf-token", "fresh-csrf-token")
        |> respond_with_json(200, ~s({"authenticated": false}))
      end)

      operation = Auth.refresh_csrf_token()
      {:ok, token} = API.request(operation, api_old)

      assert token == "fresh-csrf-token"
    end
  end

  describe "refresh_access_token/0" do
    setup %{bypass: bypass, api: api} do
      api_with_tokens = %{api | access_token: "xyz123", csrf_token: "abc123"}
      %{bypass: bypass, api: api_with_tokens}
    end

    test "operation returns token when executed successfully", %{bypass: bypass, api: api} do
      Bypass.expect_once(bypass, fn conn ->
        assert Plug.Conn.get_req_header(conn, "authorization") == ["Bearer xyz123"]

        conn
        |> Plug.Conn.put_resp_header("authorization", "Bearer 123xyz")
        |> Plug.Conn.put_resp_header("dspace-xsrf-token", "abc123")
        |> respond_with_json(200, "")
      end)

      operation = Auth.refresh_access_token()
      {:ok, token} = API.request(operation, api)

      assert token == "123xyz"
    end

    test "operation returns error when request fails", %{bypass: bypass, api: api} do
      Bypass.expect_once(bypass, fn conn ->
        respond_with_json(conn, 401, ~s({"message": "Token expired"}))
      end)

      operation = Auth.refresh_access_token()
      {:error, error} = API.request(operation, api)

      assert %Error{type: :unauthorized} = error
    end
  end

  describe "delete_api_key/0" do
    setup %{bypass: bypass, api: api} do
      api_with_tokens = %{api | access_token: "xyz123", csrf_token: "abc123"}
      %{bypass: bypass, api: api_with_tokens}
    end

    test "operation returns token when executed successfully", %{bypass: bypass, api: api} do
      Bypass.expect_once(bypass, fn conn ->
        assert Plug.Conn.get_req_header(conn, "authorization") == ["Bearer xyz123"]
        assert Plug.Conn.get_req_header(conn, "x-xsrf-token") == ["abc123"]

        respond_with_json(conn, 204, "")
      end)

      operation = Auth.delete_api_key()
      {:ok, result} = API.request(operation, api)

      assert is_map(result)
    end

    test "operation returns error when request fails", %{bypass: bypass, api: api} do
      Bypass.expect_once(bypass, fn conn ->
        respond_with_json(conn, 404, ~s({"message": "Not Found"}))
      end)

      operation = Auth.delete_api_key()
      {:error, error} = API.request(operation, api)

      assert %Error{type: :not_found} = error
    end
  end

  describe "fetch_short_lived_token/0" do
    setup %{bypass: bypass, api: api} do
      api_with_tokens = %{api | access_token: "xyz123", csrf_token: "abc123"}
      %{bypass: bypass, api: api_with_tokens}
    end

    test "operation returns token when executed successfully", %{bypass: bypass, api: api} do
      Bypass.expect_once(bypass, fn conn ->
        assert Plug.Conn.get_req_header(conn, "authorization") == ["Bearer xyz123"]
        assert Plug.Conn.get_req_header(conn, "x-xsrf-token") == ["abc123"]

        respond_with_json(conn, 200, ~s({"token": "shorty123"}))
      end)

      operation = Auth.fetch_short_lived_token()
      {:ok, token} = API.request(operation, api)

      assert token == "shorty123"
    end

    test "operation returns error when request fails", %{bypass: bypass, api: api} do
      Bypass.expect_once(bypass, fn conn ->
        respond_with_json(conn, 401, ~s({"message": "Unauthorized"}))
      end)

      operation = Auth.fetch_short_lived_token()
      {:error, error} = API.request(operation, api)

      assert %Error{type: :unauthorized} = error
    end

    test "uses GET method for older DSpace versions", %{bypass: bypass, api: api} do
      api_old = %{api | api_version: "7.4.9"}

      Bypass.expect_once(bypass, fn conn ->
        assert Plug.Conn.get_req_header(conn, "authorization") == ["Bearer xyz123"]
        assert Plug.Conn.get_req_header(conn, "x-xsrf-token") == ["abc123"]

        respond_with_json(conn, 200, ~s({"token": "shorty456"}))
      end)

      operation = Auth.fetch_short_lived_token()
      {:ok, token} = API.request(operation, api_old)

      assert token == "shorty456"
    end
  end
end
