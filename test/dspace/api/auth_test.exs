defmodule DSpace.API.AuthTest do
  use DSpace.API.Case, async: true

  alias DSpace.API
  alias DSpace.API.Auth
  alias DSpace.API.Error

  describe "login/2" do
    @user "test@example.com"
    @pass "password123"

    test "operation returns token when executed successfully with existing CSRF", %{
      sham: sham,
      api: api
    } do
      form_body = URI.encode_query(user: @user, password: @pass)

      Sham.expect(sham, fn conn ->
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

    test "operation fetches CSRF when missing", %{sham: sham, api: api} do
      api = %{api | csrf_token: nil}
      form_body = URI.encode_query(user: @user, password: @pass)

      # Expect CSRF fetch
      Sham.expect_once(sham, "GET", "/api/security/csrf", fn conn ->
        conn
        |> Plug.Conn.put_resp_header("dspace-xsrf-token", "auto-csrf-123")
        |> respond_with_json(204, "")
      end)

      # Expect login
      Sham.expect_once(sham, "POST", "/api/authn/login", fn conn ->
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

    test "operation returns error when request fails", %{sham: sham, api: api} do
      Sham.expect(sham, fn conn ->
        respond_with_json(conn, 401, ~s({"message": "Bad credentials"}))
      end)

      operation = Auth.login(@user, @pass)
      {:error, error} = API.request(operation, api)

      assert %Error{type: :unauthorized} = error
    end

    test "operation returns the CSRF fetch error instead of attempting login", %{sham: sham, api: api} do
      api = %{api | csrf_token: nil}

      # Expect CSRF fetch to fail
      Sham.expect(sham, "GET", "/api/security/csrf", fn conn ->
        respond_with_json(conn, 500, ~s({"message": "CSRF Fetch Error"}))
      end)

      operation = Auth.login(@user, @pass)
      {:error, error} = API.request(operation, api)

      assert %Error{type: :server_error} = error
    end

    test "operation fetches CSRF when missing with tranform override", %{sham: sham, api: api} do
      api = %{api | csrf_token: nil}

      # Expect CSRF fetch
      Sham.expect_once(sham, "GET", "/api/security/csrf", fn conn ->
        conn
        |> Plug.Conn.put_resp_header("dspace-xsrf-token", "auto-csrf-123")
        |> respond_with_json(204, "")
      end)

      # Expect login
      Sham.expect_once(sham, "POST", "/api/authn/login", fn conn ->
        assert Plug.Conn.get_req_header(conn, "x-xsrf-token") == ["auto-csrf-123"]

        conn
        |> Plug.Conn.put_resp_header("authorization", "Bearer auto-token-456")
        |> respond_with_json(200, ~s({"token": "auto-token-456"}))
      end)

      operation = Auth.login(@user, @pass)
      {:ok, response} = API.request(operation, api, transform: false)

      assert %DSpace.API.HTTP.Response{body: body} = response
      assert Map.get(body, "token") == "auto-token-456"
    end
  end

  describe "fetch_api_key/0" do
    setup %{sham: sham, api: api} do
      api_with_tokens = %{api | access_token: "xyz123", csrf_token: "abc123"}
      %{sham: sham, api: api_with_tokens}
    end

    test "operation returns token when executed successfully", %{sham: sham, api: api} do
      Sham.expect(sham, fn conn ->
        assert Plug.Conn.get_req_header(conn, "authorization") == ["Bearer xyz123"]
        assert Plug.Conn.get_req_header(conn, "x-xsrf-token") == ["abc123"]

        respond_with_json(conn, 200, ~s({"token": "api_key_123"}))
      end)

      operation = Auth.fetch_api_key()
      {:ok, result} = API.request(operation, api)

      assert result == "api_key_123"
    end

    test "operation returns error when request fails", %{sham: sham, api: api} do
      Sham.expect(sham, fn conn ->
        respond_with_json(conn, 500, ~s({"message": "Server Error"}))
      end)

      operation = Auth.fetch_api_key()
      {:error, error} = API.request(operation, api)

      assert %Error{type: :server_error} = error
    end

    test "operation returns error when response body is invalid", %{sham: sham, api: api} do
      Sham.expect(sham, fn conn ->
        respond_with_json(conn, 200, ~s({"invalid": "response"}))
      end)

      operation = Auth.fetch_api_key()
      {:error, error} = API.request(operation, api)

      assert %Error{type: :api_unexpected_payload} = error
    end
  end

  describe "refresh_csrf_token/0" do
    test "operation returns token when executed successfully", %{sham: sham, api: api} do
      api = %{api | api_version: "7.6.2"}

      Sham.expect_once(sham, "GET", "/api/security/csrf", fn conn ->
        conn
        |> Plug.Conn.put_resp_header("dspace-xsrf-token", "fresh-csrf-token")
        |> respond_with_json(204, "")
      end)

      operation = Auth.refresh_csrf_token()
      {:ok, token} = API.request(operation, api)

      assert token == "fresh-csrf-token"
    end

    test "operation returns error when request fails", %{sham: sham, api: api} do
      Sham.expect_once(sham, fn conn ->
        respond_with_json(conn, 500, ~s({"message": "Server Error"}))
      end)

      operation = Auth.refresh_csrf_token()
      {:error, error} = API.request(operation, api)

      assert %Error{type: :server_error} = error
    end

    test "uses fallback endpoint for older DSpace versions", %{sham: sham, api: api} do
      api_old = %{api | api_version: "7.6.1"}

      Sham.expect_once(sham, "GET", "/api/authn/status", fn conn ->
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
    setup %{sham: sham, api: api} do
      api_with_tokens = %{api | access_token: "xyz123", csrf_token: "abc123"}
      %{sham: sham, api: api_with_tokens}
    end

    test "operation returns token when executed successfully", %{sham: sham, api: api} do
      Sham.expect_once(sham, fn conn ->
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

    test "operation returns error when request fails", %{sham: sham, api: api} do
      Sham.expect_once(sham, fn conn ->
        respond_with_json(conn, 401, ~s({"message": "Token expired"}))
      end)

      operation = Auth.refresh_access_token()
      {:error, error} = API.request(operation, api)

      assert %Error{type: :unauthorized} = error
    end
  end

  describe "delete_api_key/0" do
    setup %{sham: sham, api: api} do
      api_with_tokens = %{api | access_token: "xyz123", csrf_token: "abc123"}
      %{sham: sham, api: api_with_tokens}
    end

    test "operation returns token when executed successfully", %{sham: sham, api: api} do
      Sham.expect_once(sham, fn conn ->
        assert Plug.Conn.get_req_header(conn, "authorization") == ["Bearer xyz123"]
        assert Plug.Conn.get_req_header(conn, "x-xsrf-token") == ["abc123"]

        respond_with_json(conn, 204, "")
      end)

      operation = Auth.delete_api_key()
      {:ok, result} = API.request(operation, api)

      assert is_map(result)
    end

    test "operation returns error when request fails", %{sham: sham, api: api} do
      Sham.expect_once(sham, fn conn ->
        respond_with_json(conn, 404, ~s({"message": "Not Found"}))
      end)

      operation = Auth.delete_api_key()
      {:error, error} = API.request(operation, api)

      assert %Error{type: :not_found} = error
    end
  end

  describe "fetch_short_lived_token/0" do
    setup %{sham: sham, api: api} do
      api_with_tokens = %{api | access_token: "xyz123", csrf_token: "abc123"}
      %{sham: sham, api: api_with_tokens}
    end

    test "operation returns token when executed successfully", %{sham: sham, api: api} do
      Sham.expect_once(sham, fn conn ->
        assert Plug.Conn.get_req_header(conn, "authorization") == ["Bearer xyz123"]
        assert Plug.Conn.get_req_header(conn, "x-xsrf-token") == ["abc123"]

        respond_with_json(conn, 200, ~s({"token": "shorty123"}))
      end)

      operation = Auth.fetch_short_lived_token()
      {:ok, token} = API.request(operation, api)

      assert token == "shorty123"
    end

    test "operation returns error when request fails", %{sham: sham, api: api} do
      Sham.expect_once(sham, fn conn ->
        respond_with_json(conn, 401, ~s({"message": "Unauthorized"}))
      end)

      operation = Auth.fetch_short_lived_token()
      {:error, error} = API.request(operation, api)

      assert %Error{type: :unauthorized} = error
    end

    test "uses GET method for older DSpace versions", %{sham: sham, api: api} do
      api_old = %{api | api_version: "7.4.9"}

      Sham.expect_once(sham, fn conn ->
        assert Plug.Conn.get_req_header(conn, "authorization") == ["Bearer xyz123"]
        assert Plug.Conn.get_req_header(conn, "x-xsrf-token") == ["abc123"]

        respond_with_json(conn, 200, ~s({"token": "shorty456"}))
      end)

      operation = Auth.fetch_short_lived_token()
      {:ok, token} = API.request(operation, api_old)

      assert token == "shorty456"
    end
  end

  describe "extract_csrf/1" do
    test "extracts token from cookie header when xsrf-token header is absent", %{sham: sham, api: api} do
      api = %{api | api_version: "7.6.2"}

      Sham.expect_once(sham, "GET", "/api/security/csrf", fn conn ->
        conn
        |> Plug.Conn.put_resp_cookie("DSPACE-XSRF-COOKIE", "fresh-csrf-token",
          path: "/server",
          secure: true,
          http_only: true,
          same_site: "None"
        )
        |> respond_with_json(204, "")
      end)

      operation = Auth.refresh_csrf_token()
      {:ok, token} = API.request(operation, api)

      assert token == "fresh-csrf-token"
    end

    test "extracts token from second cookie header when first is an expired cookie", %{sham: sham, api: api} do
      api = %{api | api_version: "7.6.2"}

      Sham.expect_once(sham, "GET", "/api/security/csrf", fn conn ->
        conn
        |> Plug.Conn.put_resp_cookie("DSPACE-XSRF-COOKIE", "",
          path: "/server",
          max_age: 0,
          secure: true,
          http_only: true,
          same_site: "None"
        )
        |> Plug.Conn.put_resp_cookie("DSPACE-XSRF-COOKIE", "fresh-csrf-token",
          path: "/server",
          secure: true,
          http_only: true,
          same_site: "None"
        )
        |> respond_with_json(204, "")
      end)

      operation = Auth.refresh_csrf_token()
      {:ok, token} = API.request(operation, api)

      assert token == "fresh-csrf-token"
    end

    test "prefers xsrf-token header over cookie header when both are present", %{sham: sham, api: api} do
      api = %{api | api_version: "7.6.2"}

      Sham.expect_once(sham, "GET", "/api/security/csrf", fn conn ->
        conn
        |> Plug.Conn.put_resp_header("dspace-xsrf-token", "header-csrf-token")
        |> Plug.Conn.put_resp_cookie("DSPACE-XSRF-COOKIE", "cookie-csrf-token",
          path: "/server",
          secure: true,
          http_only: true,
          same_site: "None"
        )
        |> respond_with_json(204, "")
      end)

      operation = Auth.refresh_csrf_token()
      {:ok, token} = API.request(operation, api)

      assert token == "header-csrf-token"
    end
  end
end
