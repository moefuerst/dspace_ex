defmodule DSpace.Api.HttpTest do
  @moduledoc """
  Tests for Http behavior.
  """
  use ExUnit.Case, async: true

  alias DSpace.Api.Http

  setup do
    bypass = Bypass.open()
    {:ok, bypass: bypass}
  end

  describe "Default HTTP adapter implementation using Req" do
    @doc """
    Verifies that the adapter implementation handles requests and maintains compatibility with the options defined in the contract.

    Demonstrates that the adapter
    * supports method verb
    * supports query params
    * supports setting an auth header from a given bearer token
    * takes a JSON payload as an option and correctly sends it
    * parses JSON responses and encodes them into a map
    * supports URL concatenation when an endpoint is given via `base_url`
    * returns a `t:DSpace.Api.Http.Response/0`
    """
    test "makes a request using request/1", %{bypass: bypass} do
      Bypass.expect_once(bypass, "POST", "/some-post", fn conn ->
        assert Plug.Conn.get_req_header(conn, "authorization") == ["Bearer my123bearer"],
               "Authorization header not set correctly"

        assert Plug.Conn.get_req_header(conn, "content-type") == ["application/json"],
               "Content-Type header not set correctly"

        assert Plug.Conn.fetch_query_params(conn).query_params == %{"x" => "1", "y" => "param"},
               "Query params not set correctly"

        {:ok, body, conn} = Plug.Conn.read_body(conn)

        assert body == ~s({"key":"value"}),
               "JSON payload was not delivered correctly"

        conn = Plug.Conn.put_resp_header(conn, "content-type", "application/json")
        Plug.Conn.resp(conn, 200, ~s({"key":"other_value"}))
      end)

      result =
        Http.Req.request(
          method: :post,
          base_url: url(bypass),
          url: "/some-post",
          auth: {:bearer, "my123bearer"},
          json: %{key: "value"},
          params: [x: 1, y: "param"],
          # Disable retry to fail fast:
          retry: false
        )

      assert {:ok, %Http.Response{body: %{"key" => "other_value"}, status: 200}} = result
    end

    @doc """
    Verifies that the adapter properly propagates exceptions for failed requests

    An example are connection failures.
    """
    test "propagates exceptions from failed requests using request/1", %{bypass: bypass} do
      Bypass.down(bypass)

      # Disable retry to fail fast
      result = Http.Req.request(base_url: url(bypass), url: "/some-path", retry: false)

      assert {:error, %Http.Error{reason: %Req.TransportError{}}} = result
    end

    @doc """
    Verifies that the adapter treats 5xx responses as regular responses and not exceptions.

    Demonstrates that:
    * 500 responses don't return or raise errors
    * Response status and body are returned normally
    * JSON parsing still works for error responses
    """
    test "handles 500 response as response, not exception", %{bypass: bypass} do
      Bypass.expect_once(bypass, "GET", "/error", fn conn ->
        conn
        |> Plug.Conn.put_resp_header("content-type", "application/json")
        |> Plug.Conn.resp(500, ~s({"error": "internal server error"}))
      end)

      # Disable retry to fail fast
      result = Http.Req.request(base_url: url(bypass), url: "/error", retry: false)

      assert {:ok, %Http.Response{body: %{"error" => "internal server error"}, status: 500}} = result
    end
  end

  defp url(bypass), do: "http://localhost:#{bypass.port}"
end
