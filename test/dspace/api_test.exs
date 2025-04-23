defmodule DSpace.ApiTest do
  use ExUnit.Case, async: true

  import TestHelper, only: [respond_with_json: 3]

  alias DSpace.Api
  alias DSpace.Api.Auth

  defmodule TestHttpClient do
    @behaviour DSpace.Api.Http

    @impl true
    def request(options) do
      send(self(), {:http_request, options})

      {status, _options} = Keyword.pop(options, :test_return_status, 200)

      {:ok,
       %{
         status: status,
         headers: %{},
         body: %{"response" => "ok"},
         trailers: %{}
       }}
    end
  end

  setup do
    %{api: %Api{}}
  end

  describe "client configuration" do
    setup %{api: api} do
      %{
        api:
          api
          |> Api.with_endpoint("https://example.com")
          |> Api.with_client_impl({TestHttpClient, [client_config: "default", method: :get]})
      }
    end

    test "injects client implementation", %{api: api} do
      assert {TestHttpClient, client_opts} = api.client_impl,
             "API should include the configured client implementation"

      assert Keyword.get(client_opts, :client_config) == "default",
             "API should include the client configuration"

      Api.request(api, url: "/test-endpoint")
      assert_received {:http_request, _options}
    end

    test "correctly merges client options", %{api: api} do
      Api.request(api, method: :head, url: "/test", request_option: "custom")
      assert_received {:http_request, options}

      assert Keyword.get(options, :method) == :head,
             "Request method should override client config"

      assert Keyword.get(options, :base_url) == "https://example.com",
             "Base URL from API struct should be included in options"

      assert Keyword.get(options, :client_config) == "default",
             "Client config options should be included in what is passed to request/1"

      assert Keyword.get(options, :request_option) == "custom",
             "Request-specific options should be included in what is passed to request/1"

      assert Keyword.get(options, :url) == "/test",
             "URL should be preserved from request option"
    end

    test "updates client with token extraction from response", %{api: api} do
      response = %{
        headers: %{"dspace-xsrf-token" => "abc123"}
      }

      updated_api = Api.with_csrf_from_response(api, response)
      assert updated_api.csrf_token == "abc123"

      Api.request(updated_api, url: "/test")

      assert_received {:http_request, options}
      assert Keyword.get(options, :headers) == [{"x-xsrf-token", "abc123"}]
    end
  end

  describe "login/3" do
    setup do
      bypass = Bypass.open()
      api = Api.new(url(bypass))
      {:ok, bypass: bypass, api: api}
    end

    @ep_login_url "/api/authn/login"
    @ep_status_url "/api/authn/status"
    @user "test@example.com"
    @pass "password123"

    test "succeeds, fetching CSRF token first", %{
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

    test "succeeds when CSRF token already exists", %{
      bypass: bypass,
      api: api
    } do
      api_with_csrf = Api.with_csrf_token(api, "abc123")

      Bypass.expect_once(bypass, "POST", @ep_login_url, fn conn ->
        assert Plug.Conn.get_req_header(conn, "x-xsrf-token") == ["abc123"],
               "Existing CSRF token not sent in header"

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
  end

  describe "request/2" do
    setup do
      bypass = Bypass.open()
      api = Api.new(url(bypass))
      {:ok, bypass: bypass, api: api}
    end

    test "sends a POST request with json body", %{bypass: bypass, api: api} do
      api = Api.with_csrf_token(api, "abc123")
      request_body = %{name: "Test Item", description: "Test Description"}

      Bypass.expect_once(bypass, "POST", "/items", fn conn ->
        conn = Plug.Conn.fetch_query_params(conn)
        {:ok, body, conn} = Plug.Conn.read_body(conn)

        expected_json = ~s({"name":"Test Item","description":"Test Description"})

        assert body == expected_json,
               "JSON payload was not delivered correctly"

        assert ["application/json"] == Plug.Conn.get_req_header(conn, "content-type"),
               "Content-Type header not set correctly"

        conn = Plug.Conn.put_resp_header(conn, "content-type", "application/json")
        Plug.Conn.resp(conn, 200, ~s({"response":"ok"}))
      end)

      assert {:ok, response} =
               Api.request(api,
                 method: :post,
                 url: "/items",
                 json: request_body
               )

      assert response.status == 200
      assert response.body == %{"response" => "ok"}
    end

    test "accepts success code other than 200", %{bypass: bypass, api: api} do
      api_with_csrf = Api.with_csrf_token(api, "abc123")

      Bypass.expect_once(bypass, "PUT", "/test/resource", fn conn ->
        assert Plug.Conn.get_req_header(conn, "x-xsrf-token") == ["abc123"]
        Plug.Conn.resp(conn, 201, ~s({"response":"ok"}))
      end)

      assert {:ok, response} =
               Api.request(api_with_csrf,
                 method: :put,
                 url: "/test/resource"
               )

      assert response.status == 201
    end
  end

  describe "stream/4" do
    # TODO: Implement stream/4 tests
  end

  defp url(bypass), do: "http://localhost:#{bypass.port}"
end
