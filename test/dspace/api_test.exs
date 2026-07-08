defmodule DSpace.APITest do
  use ExUnit.Case, async: true

  import TestHelper, only: [respond_with_json: 3]

  alias DSpace.API
  alias DSpace.API.Operation

  setup do
    api = %API{user_agent: "test", api_version: "1.0.0"}

    %{api: api}
  end

  describe "client configuration" do
    setup %{api: api} do
      %{
        api: %{
          api
          | endpoint: "https://example.com",
            http_impl: {TestHelper.HTTP, [client_config: "default", method: :get]}
        }
      }
    end

    test "injects a client implementation", %{api: api} do
      operation = %Operation.JSON{path: "/test"}
      API.request(operation, api)

      assert_received {:http_request, _options}

      assert {TestHelper.HTTP, client_opts} = api.http_impl,
             "API should include the client implementation"

      assert Keyword.get(client_opts, :client_config) == "default",
             "API should include the client configuration"
    end

    test "correctly merges adapter config", %{api: api} do
      operation = %Operation.JSON{http_method: :head, path: "/test"}
      API.request(operation, api, request_option: "custom")

      assert_received {:http_request, options}

      assert Keyword.get(options, :client_config) == "default",
             "Client config options should be included in what is passed to the request/1 callback"

      assert Keyword.get(options, :request_option) == "custom",
             "Request-specific options should be included in what is passed to the request/1 callback"

      url = Keyword.get(options, :url)

      assert url.host == "example.com",
             "Configured endpoint from API structure should be preserved"

      assert url.path == "/test",
             "Requested path should be preserved"

      assert Keyword.get(options, :method) == :head,
             "Request-specific options should override adapter config"
    end
  end

  describe "login functionality" do
    setup do
      sham = Sham.start()

      api = %API{
        endpoint: url(sham),
        csrf_token: "123",
        http_impl: {DSpace.API.HTTP.Req, [retry: false]}
      }

      {:ok, sham: sham, api: api}
    end

    @user "test@example.com"
    @pass "password123"

    test "login/3 returns updated client when login succeeds", %{sham: sham, api: api} do
      Sham.expect(sham, fn conn ->
        conn
        # sic, DSpace *does* return the access token this way...
        |> Plug.Conn.put_resp_header("authorization", "Bearer xyz123")
        |> Plug.Conn.put_resp_header("dspace-xsrf-token", "abc123")
        |> respond_with_json(200, "")
      end)

      {:ok, updated_client} = API.login(api, @user, @pass)

      assert is_struct(updated_client, API)
      assert updated_client.access_token == "xyz123"
      assert updated_client.csrf_token == "abc123"
    end

    test "login/3 returns error when login fails", %{sham: sham, api: api} do
      Sham.expect(sham, fn conn ->
        respond_with_json(conn, 500, ~s({"error": "internal server error"}))
      end)

      result = API.login(api, @user, @pass)

      assert {:error, %DSpace.API.Error{status: http_status}} = result
      assert 500 == http_status
    end

    test "login!/3 returns updated client when login succeeds", %{sham: sham, api: api} do
      Sham.expect(sham, fn conn ->
        conn
        # sic, DSpace *does* return the access token this way...
        |> Plug.Conn.put_resp_header("authorization", "Bearer xyz123")
        |> Plug.Conn.put_resp_header("dspace-xsrf-token", "abc123")
        |> respond_with_json(200, "")
      end)

      updated_client = API.login!(api, @user, @pass)

      assert is_struct(updated_client, API)
      assert updated_client.access_token == "xyz123"
      assert updated_client.csrf_token == "abc123"
    end

    test "login!/3 raises when login fails", %{sham: sham, api: api} do
      Sham.expect(sham, fn conn ->
        respond_with_json(conn, 500, ~s({"error": "internal server error"}))
      end)

      assert_raise API.Error, "Server error", fn ->
        API.login!(api, @user, @pass)
      end
    end
  end

  describe "authenticated?/1" do
    setup do
      sham = Sham.start()
      api = %API{endpoint: url(sham), http_impl: {DSpace.API.HTTP.Req, [retry: false]}}

      {:ok, sham: sham, api: api}
    end

    test "returns true when API response indicates authenticated", %{sham: sham, api: api} do
      Sham.expect(sham, fn conn ->
        respond_with_json(conn, 200, ~s({"authenticated": true}))
      end)

      result = API.authenticated?(api)

      assert result == true
    end

    test "returns false when API response indicates not authenticated", %{
      sham: sham,
      api: api
    } do
      Sham.expect(sham, fn conn ->
        respond_with_json(conn, 200, ~s({"authenticated": false}))
      end)

      result = API.authenticated?(api)

      assert result == false
    end

    test "returns false when API response is missing the authenticated key", %{
      sham: sham,
      api: api
    } do
      Sham.expect(sham, fn conn ->
        respond_with_json(conn, 200, ~s({"some_other_key": true}))
      end)

      result = API.authenticated?(api)

      assert result == false
    end

    test "returns false on API request error", %{api: api} do
      # Simulate a request error by setting an invalid endpoint
      api = API.put_endpoint(api, "http://localhost:1")

      result = API.authenticated?(api)

      assert result == false
    end
  end

  describe "request/3" do
    setup do
      sham = Sham.start()
      api = %API{endpoint: url(sham), http_impl: {DSpace.API.HTTP.Req, [retry: false]}}

      {:ok, sham: sham, api: api}
    end

    test "handles an operation with json payload", %{sham: sham, api: api} do
      api = API.put_csrf_token(api, "abc123")

      operation = %Operation.JSON{
        http_method: :post,
        path: "/items",
        content_type: :json,
        data: %{name: "Test Item", description: "Test Description"},
        transformer: &Function.identity/1
      }

      Sham.expect_once(sham, "POST", "/items", fn conn ->
        conn = Plug.Conn.fetch_query_params(conn)
        {:ok, body, conn} = Plug.Conn.read_body(conn)

        assert ["application/json"] == Plug.Conn.get_req_header(conn, "content-type")

        expected_json = ~s({"name":"Test Item","description":"Test Description"})
        assert body == expected_json

        respond_with_json(conn, 200, ~s({"response":"ok"}))
      end)

      result = API.request(operation, api)

      assert {:ok, response} = result
      assert response.status == 200
      assert response.body == %{"response" => "ok"}
    end

    test "accepts success code other than 200", %{sham: sham, api: api} do
      api = API.put_csrf_token(api, "abc123")

      operation = %Operation.JSON{
        http_method: :put,
        path: "/test/resource",
        expected_status: [200, 201],
        transformer: &Function.identity/1
      }

      Sham.expect_once(sham, "PUT", "/test/resource", fn conn ->
        assert Plug.Conn.get_req_header(conn, "x-xsrf-token") == ["abc123"]
        respond_with_json(conn, 201, ~s({"response":"ok"}))
      end)

      result = API.request(operation, api)

      assert {:ok, response} = result
      assert response.status == 201
    end

    test "applies transformation to HTTP response", %{sham: sham, api: api} do
      transform_fn = fn response -> %{transformed: true, original_status: response.status} end
      operation = %Operation.JSON{path: "/test", transformer: transform_fn}

      Sham.expect_once(sham, "GET", "/test", fn conn ->
        respond_with_json(conn, 200, ~s({"data": "test"}))
      end)

      result = API.request(operation, api)

      assert {:ok, response} = result
      assert response == %{transformed: true, original_status: 200}
    end

    test "respects transform: false option to skip transformation", %{sham: sham, api: api} do
      transform_fn = fn _response -> %{should_not_see_this: true} end
      operation = %Operation.JSON{path: "/test", transformer: transform_fn}

      Sham.expect_once(sham, "GET", "/test", fn conn ->
        respond_with_json(conn, 200, ~s({"data": "test"}))
      end)

      result = API.request(operation, api, transform: false)

      assert {:ok, response} = result
      assert response.status == 200
      assert response.body == %{"data" => "test"}
      refute Map.has_key?(response, :should_not_see_this)
    end

    test "invokes response hook after HTTP response", %{sham: sham, api: api} do
      test_pid = self()
      callback = fn token_map -> send(test_pid, {:callback_invoked, token_map}) end
      api = %{api | on_response_hook: callback}

      operation = %Operation.JSON{path: "/test", transformer: &Function.identity/1}

      Sham.expect_once(sham, "GET", "/test", fn conn ->
        conn
        |> Plug.Conn.put_resp_header("dspace-xsrf-token", "new-csrf-token")
        |> respond_with_json(200, ~s({"data": "test"}))
      end)

      API.request(operation, api)

      assert_receive {:callback_invoked, %{csrf_token: "new-csrf-token"}}
    end

    test "handles nil response hook", %{sham: sham, api: api} do
      api = %{api | on_response_hook: nil}
      operation = %Operation.JSON{path: "/test", transformer: &Function.identity/1}

      Sham.expect_once(sham, "GET", "/test", fn conn ->
        conn
        |> Plug.Conn.put_resp_header("dspace-xsrf-token", "new-csrf-token")
        |> respond_with_json(200, ~s({"data": "test"}))
      end)

      result = API.request(operation, api)

      assert {:ok, _response} = result
    end
  end

  describe "stream!/3" do
    # TODO: stream!/3 tests
  end

  defp url(sham), do: "http://localhost:#{sham.port}"
end
