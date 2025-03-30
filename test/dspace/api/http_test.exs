defmodule DSpace.Api.HttpTest do
  @moduledoc """
  Tests for Http behavior.

  The behavior was basically designed by working backwards from Req's API. We verify that the default implementation maintains compatibility with the specific options defined in the contract to prevent regressions in case of a dependency breaking change.
  """
  use ExUnit.Case, async: true

  alias DSpace.Api.Http

  setup do
    bypass = Bypass.open()
    {:ok, bypass: bypass}
  end

  describe "Default client implementation using Req" do
    @doc """
    Verifies that the client implementation handles requests.

    Demonstrates that the client
    * supports method verb
    * supports URL concatenation when an endpoint is defined
    * supports setting an auth header from a given bearer token
    * parses JSON responses and encodes them into a map
    """
    test "makes a request using request/1", %{bypass: bypass} do
      Bypass.expect_once(bypass, "POST", "/some-post", fn conn ->
        assert ["Bearer my123bearer"] == Plug.Conn.get_req_header(conn, "authorization"),
               "Authorization header not set correctly"

        assert ["application/json"] == Plug.Conn.get_req_header(conn, "content-type"),
               "Content-Type header not set correctly"

        conn = Plug.Conn.put_resp_header(conn, "content-type", "application/json")
        Plug.Conn.resp(conn, 200, ~s({"key": "value"}))
      end)

      result =
        Http.Req.request(
          method: :post,
          base_url: url(bypass),
          url: "/some-post",
          auth: {:bearer, "my123bearer"},
          # Option passed to the client per default in the `DSpace.Api` struct:
          json: true,
          # Disable retry to fail fast:
          retry: false
        )

      assert {:ok, %{body: %{"key" => "value"}, status: 200}} = result
    end

    @doc """
    Verifies that the client properly propagates exceptions for failed requests

    An example are connection failures.
    """
    test "propagates exceptions from failed requests using request/1", %{bypass: bypass} do
      Bypass.down(bypass)

      result =
        Http.Req.request(
          base_url: url(bypass),
          url: "/some-path",
          # Disable retry to fail fast:
          retry: false
        )

      assert {:error, %Req.TransportError{}} = result
    end

    @doc """
    Verifies that the client treats 5xx responses as regular responses and not exceptions.

    Background: Many other HTTP clients raise exceptions for 5xx responses, Req (and therefore our implementation) returns them as regular response maps.

    Demonstrates that:
    * 500 responses don't raise exceptions
    * Response status and body are returned normally
    * JSON parsing still works for error responses
    """
    test "handles 500 response as response, not exception", %{bypass: bypass} do
      Bypass.expect_once(bypass, "GET", "/error", fn conn ->
        conn
        |> Plug.Conn.put_resp_header("content-type", "application/json")
        |> Plug.Conn.resp(500, ~s({"error": "internal server error"}))
      end)

      result =
        Http.Req.request(
          base_url: url(bypass),
          url: "/error",
          # Option passed to the client per default in the `DSpace.Api` struct:
          json: true,
          # Disable retry to fail fast:
          retry: false
        )

      assert {:ok, %{body: %{"error" => "internal server error"}, status: 500}} = result
    end
  end

  defp url(bypass), do: "http://localhost:#{bypass.port}"
end
