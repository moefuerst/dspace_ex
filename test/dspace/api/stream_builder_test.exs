defmodule DSpace.API.StreamBuilderTest do
  use ExUnit.Case, async: true

  import TestHelper, only: [respond_with_json: 3]

  alias DSpace.API.HTTP
  alias DSpace.API.Operation
  alias DSpace.API.StreamBuilder

  setup do
    bypass = Bypass.open()

    # Disable retry to fail fast in all tests
    client = %DSpace.API{endpoint: url(bypass), http_impl: {HTTP.Req, [retry: false]}}

    {:ok, bypass: bypass, client: client}
  end

  describe "new/3" do
    test "streams pages until no next URL is returned", %{bypass: bypass, client: client} do
      Bypass.expect(bypass, "GET", "/items", fn conn ->
        case conn.query_string do
          "" ->
            respond_with_json(
              conn,
              200,
              ~s({"items": ["item1", "item2"], "next": "#{url(bypass)}/items?page=2"})
            )

          "page=2" ->
            respond_with_json(
              conn,
              200,
              ~s({"items": ["item3", "item4"], "next": "#{url(bypass)}/items?page=3"})
            )

          "page=3" ->
            respond_with_json(
              conn,
              200,
              ~s({"items": ["item5", "item6"], "next": null})
            )
        end
      end)

      operation = %Operation.JSON{
        path: "/items",
        transformer: fn response -> {response.body["items"], %{}, response.body["next"]} end
      }

      stream = StreamBuilder.new(client, operation, [])
      result = Enum.to_list(stream)

      assert result == ["item1", "item2", "item3", "item4", "item5", "item6"]
    end

    test "terminates stream when next is nil", %{bypass: bypass, client: client} do
      Bypass.expect_once(bypass, "GET", "/items", fn conn ->
        respond_with_json(conn, 200, ~s({"items": ["item1", "item2"], "next": null}))
      end)

      operation = %Operation.JSON{
        path: "/items",
        transformer: fn response -> {response.body["items"], %{}, response.body["next"]} end
      }

      stream = StreamBuilder.new(client, operation, [])
      result = Enum.to_list(stream)

      assert result == ["item1", "item2"]
    end

    test "terminates stream when next is not a URL string", %{bypass: bypass, client: client} do
      Bypass.expect_once(bypass, "GET", "/items", fn conn ->
        respond_with_json(conn, 200, ~s({"items": ["item1"], "next": 404}))
      end)

      operation = %Operation.JSON{
        path: "/items",
        transformer: fn response -> {response.body["items"], %{}, response.body["next"]} end
      }

      stream = StreamBuilder.new(client, operation, [])
      result = Enum.to_list(stream)

      assert result == ["item1"]
    end

    test "propagates errors from API requests", %{bypass: bypass, client: client} do
      Bypass.expect(bypass, "GET", "/items", fn conn ->
        Plug.Conn.resp(conn, 500, "Server Error")
      end)

      operation = %Operation.JSON{
        path: "/items",
        transformer: fn _response -> {[], %{}, nil} end
      }

      stream = StreamBuilder.new(client, operation, [])

      assert_raise DSpace.API.Error, fn -> Enum.to_list(stream) end
    end

    test "handles empty result pages", %{bypass: bypass, client: client} do
      Bypass.expect_once(bypass, "GET", "/items", fn conn ->
        respond_with_json(conn, 200, ~s({"items": [], "next": null}))
      end)

      operation = %Operation.JSON{
        path: "/items",
        transformer: fn response -> {response.body["items"], %{}, response.body["next"]} end
      }

      stream = StreamBuilder.new(client, operation, [])
      result = Enum.to_list(stream)

      assert result == []
    end
  end

  defp url(bypass), do: "http://localhost:#{bypass.port}"
end
