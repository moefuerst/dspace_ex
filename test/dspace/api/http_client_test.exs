defmodule DSpace.Api.HttpClientTest do
  @moduledoc """
  Tests for HttpClient behavior.

  The behavior was basically designed by working backwards from Req's API. We verify that the default implementation maintains compatibility with the specific options defined in the contract to prevent regressions in case of a dependency breaking change.
  """
  use ExUnit.Case, async: true

  alias DSpace.Api.HttpClient

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
      Bypass.expect_once(bypass, "POST", "/unsafe", fn conn ->
        assert ["Bearer my123bearer"] == Plug.Conn.get_req_header(conn, "authorization"),
               "Authorization header not set correctly"

        assert ["application/json"] == Plug.Conn.get_req_header(conn, "content-type"),
               "Content-Type header not set correctly"

        conn = Plug.Conn.put_resp_header(conn, "content-type", "application/json")
        Plug.Conn.resp(conn, 200, ~s({"key": "value"}))
      end)

      result =
        HttpClient.Req.request(
          method: :post,
          base_url: url(bypass),
          url: "/unsafe",
          auth: {:bearer, "my123bearer"},
          # Option passed to the client per default in the `DSpace.Api` struct:
          json: true
        )

      assert {:ok, %{status: 200, body: %{"key" => "value"}}} = result
    end

    @doc """
    Verifies that the client properly propagates exceptions for failed requests

    An example are connection failures. Disables retry to avoid needless timeout delays in tests.
    """
    test "propagates exceptions from failed requests using request/1", %{bypass: bypass} do
      Bypass.down(bypass)

      result =
        HttpClient.Req.request(
          retry: false,
          base_url: url(bypass),
          url: "/path"
        )

      assert {:error, %Req.TransportError{}} = result
    end

    @doc """
    Verifies that the client implementation handles requests when `request!/1` is called

    Demonstrates that the client
    * returns response map directly without wrapping in :ok tuple
    * correctly encodes request body as JSON
    * correctly decodes JSON response body into map
    * works with PATCH (bonus, we don't need to duplicate Req's test suite)
    """
    test "request!/1 returns response directly on success", %{bypass: bypass} do
      Bypass.expect_once(bypass, "PATCH", "/unsafe", fn conn ->
        {:ok, body, conn} = Plug.Conn.read_body(conn)
        assert body == ~s({"update": "value"}), "Request body not sent correctly"

        conn
        |> Plug.Conn.put_resp_header("content-type", "application/json")
        |> Plug.Conn.resp(200, ~s({"key": "updated"}))
      end)

      result =
        HttpClient.Req.request!(
          method: :patch,
          base_url: url(bypass),
          url: "/unsafe",
          body: %{update: "value"},
          json: true
        )

      assert %{status: 200, body: %{"key" => "updated"}} = result
    end

    @doc """
    Verifies that the client properly raises exceptions for failed requests like connection failures.

    Disables retry to avoid needless timeout delays in tests.
    """
    test "request!/1 raises on failed requests", %{bypass: bypass} do
      Bypass.down(bypass)

      assert_raise Req.TransportError, fn ->
        HttpClient.Req.request!(
          method: :get,
          base_url: url(bypass),
          url: "/some-path"
        )
      end
    end
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
      HttpClient.Req.request(
        base_url: url(bypass),
        url: "/error",
        json: true
      )

    assert {:ok, %{status: 500, body: %{"error" => "internal server error"}}} = result
  end

  defp url(bypass), do: "http://localhost:#{bypass.port}"
end
