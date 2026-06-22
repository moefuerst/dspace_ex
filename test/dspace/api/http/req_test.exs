defmodule DSpace.API.HTTP.ReqTest do
  use ExUnit.Case, async: true

  import TestHelper, only: [respond_with_json: 3]

  alias DSpace.API.HTTP

  setup do
    bypass = Bypass.open()

    {:ok, bypass: bypass}
  end

  describe "Default HTTP adapter implementation using Req" do
    @doc """
    Verifies that the adapter implementation handles requests and maintains compatibility with the
    options defined in the contract.

    Demonstrates that the adapter

      * supports method verb
      * supports query params
      * supports setting an auth header from a given bearer token
      * supports setting headers with atom header name
      * takes a JSON payload as an option and correctly sends it
      * parses JSON responses and encodes them into a map
      * supports URL concatenation when an endpoint is given via `base_url`
      * returns a `t:DSpace.API.HTTP.Response/0`
    """
    test "makes a request using request/1", %{bypass: bypass} do
      Bypass.expect_once(bypass, "POST", "/some-post", fn conn ->
        assert Plug.Conn.get_req_header(conn, "authorization") == ["Bearer my123bearer"]
        assert Plug.Conn.get_req_header(conn, "content-type") == ["application/json"]
        assert Plug.Conn.get_req_header(conn, "accept") == ["application/json"]
        assert Plug.Conn.get_req_header(conn, "x-xsrf-token") == ["token123"]
        assert Plug.Conn.fetch_query_params(conn).query_params == %{"x" => "1", "y" => "param"}

        {:ok, body, conn} = Plug.Conn.read_body(conn)
        assert body == ~s({"key":"value"})

        respond_with_json(conn, 200, ~s({"key":"other_value"}))
      end)

      result =
        HTTP.Req.request(
          method: :post,
          base_url: url(bypass),
          url: "/some-post",
          auth: {:bearer, "my123bearer"},
          headers: %{:accept => ["application/json"], :x_xsrf_token => ["token123"]},
          json: %{key: "value"},
          params: [x: 1, y: "param"],
          # Disable retry to fail fast
          retry: false
        )

      assert {:ok, %HTTP.Response{body: %{"key" => "other_value"}, status: 200}} = result
    end

    test "makes a form request using request/1", %{bypass: bypass} do
      Bypass.expect_once(bypass, "POST", "/form-data", fn conn ->
        assert Plug.Conn.get_req_header(conn, "content-type") == [
                 "application/x-www-form-urlencoded"
               ]

        {:ok, body, conn} = Plug.Conn.read_body(conn)
        assert body == "password=secret&username=admin"

        respond_with_json(conn, 200, ~s({"authenticated": true}))
      end)

      result =
        HTTP.Req.request(
          method: :post,
          url: url(bypass) <> "/form-data",
          form: %{username: "admin", password: "secret"},
          # Disable retry to fail fast
          retry: false
        )

      assert {:ok, %HTTP.Response{body: %{"authenticated" => true}, status: 200}} = result
    end

    test "makes a multipart form request using request/1", %{bypass: bypass} do
      Bypass.expect_once(bypass, "POST", "/upload", fn conn ->
        [content_type] = Plug.Conn.get_req_header(conn, "content-type")

        assert String.starts_with?(content_type, "multipart/form-data")

        {:ok, body, conn} = Plug.Conn.read_body(conn)
        assert String.contains?(body, "name=\"file\"")
        assert String.contains?(body, "file_content")

        respond_with_json(conn, 201, ~s({"uploaded": true}))
      end)

      result =
        HTTP.Req.request(
          method: :post,
          url: url(bypass) <> "/upload",
          form_multipart: %{file: "file_content", metadata: "info"},
          # Disable retry to fail fast
          retry: false
        )

      assert {:ok, %HTTP.Response{body: %{"uploaded" => true}, status: 201}} = result
    end

    test "takes an option to disable response body decoding", %{bypass: bypass} do
      Bypass.expect_once(bypass, "POST", "/some-post", fn conn ->
        respond_with_json(conn, 200, ~s({"key":"other_value"}))
      end)

      result =
        HTTP.Req.request(
          method: :post,
          base_url: url(bypass),
          url: "/some-post",
          decode_body: false,
          # Disable retry to fail fast
          retry: false
        )

      assert {:ok, %HTTP.Response{body: ~s({"key":"other_value"})}} = result
    end

    test "propagates exceptions from failed requests using request/1", %{bypass: bypass} do
      Bypass.down(bypass)

      # Disable retry to fail fast
      result = HTTP.Req.request(base_url: url(bypass), url: "/some-path", retry: false)

      assert {:error, %DSpace.API.HTTP.Error{reason: %Req.TransportError{}}} = result
    end

    test "handles 500 response as response, not exception", %{bypass: bypass} do
      Bypass.expect_once(bypass, "GET", "/error", fn conn ->
        respond_with_json(conn, 500, ~s({"error": "internal server error"}))
      end)

      # Disable retry to fail fast
      result = HTTP.Req.request(base_url: url(bypass), url: "/error", retry: false)

      assert {:ok, %HTTP.Response{body: %{"error" => "internal server error"}, status: 500}} =
               result
    end
  end

  # Private helpers

  defp url(bypass), do: "http://localhost:#{bypass.port}"
end
