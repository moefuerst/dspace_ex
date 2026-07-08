defmodule DSpace.API.HTTPTest do
  use ExUnit.Case, async: true

  import TestHelper, only: [respond_with_json: 3]

  alias DSpace.API.Error
  alias DSpace.API.HTTP

  setup do
    sham = Sham.start()

    {:ok, sham: sham}
  end

  describe "Request preparation" do
    test "Adds requested endpoint to the response structure", %{sham: sham} do
      Sham.expect_once(sham, "GET", "/my-path", fn conn ->
        Plug.Conn.resp(conn, 200, "ok")
      end)

      result = HTTP.request(HTTP.Req, url: URI.parse(url(sham) <> "/my-path"))

      assert {:ok, %HTTP.Response{request_url: requested}} = result
      assert requested.path == "/my-path"
    end
  end

  describe "Response normalization" do
    test "returns DSpace.API.Error for common non-success status codes", %{sham: sham} do
      common_error_codes = [400, 401, 403, 404, 410, 412, 422, 429, 500, 502, 503]

      for status <- common_error_codes do
        Sham.expect_once(sham, "GET", "/error", fn conn ->
          respond_with_json(conn, status, ~s({"error": "error for status #{status}"}))
        end)

        # Disable retry to fail fast
        result =
          HTTP.request(HTTP.Req,
            url: url(sham) <> "/error",
            expected_status: [200],
            retry: false
          )

        assert {:error, %Error{status: http_status}} = result
        assert status == http_status
      end
    end

    test "returns DSpace.API.Error for unexpected response 304 Not Modified", %{sham: sham} do
      Sham.expect_once(sham, "GET", "/not-modified", fn conn ->
        respond_with_json(conn, 304, "")
      end)

      # Disable retry to fail fast
      result =
        HTTP.request(HTTP.Req,
          url: url(sham) <> "/not-modified",
          expected_status: [200],
          retry: false
        )

      assert {:error, %Error{type: :api_unexpected_response, status: 304}} = result
    end

    test "propagates exceptional error returned by the HTTP adapter as DSpace.API.HTTP.Error", %{
      sham: sham
    } do
      Sham.expect_once(sham, fn conn ->
        conn
        |> Plug.Conn.put_resp_header("content-length", "error")
        |> Plug.Conn.put_resp_header("transfer-encoding", "20")
        |> Plug.Conn.resp(200, "")
      end)

      result = HTTP.request(HTTP.Req, url: url(sham) <> "/error", retry: false)

      assert {:error, %DSpace.API.HTTP.Error{reason: %Req.HTTPError{}}} = result
    end
  end

  # Private helpers
  defp url(sham), do: "http://localhost:#{sham.port}"
end
