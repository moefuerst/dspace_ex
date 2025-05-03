defmodule DSpace.Api.PidTest do
  use ExUnit.Case, async: true

  import TestHelper, only: [load_fixture: 1, respond_with_json: 3]

  alias DSpace.Api
  alias DSpace.Api.Error
  alias DSpace.Api.Object
  alias DSpace.Api.Pid
  alias DSpace.Api.Pid.Identifier

  @api_endpoint "/api/pid"

  setup do
    bypass = Bypass.open()
    api = Api.new(url(bypass))
    {:ok, bypass: bypass, api: api}
  end

  describe "resolve/2" do
    test "correctly resolves an identifier to a DSpace object", %{bypass: bypass, api: api} do
      identifier = "10.12345/123456"
      item = load_fixture("get_item.json")

      Bypass.expect_once(bypass, "GET", "#{@api_endpoint}/find", fn conn ->
        assert %{"id" => ^identifier} = conn.params,
               "The identifier should be sent as 'id' parameter"

        respond_with_json(conn, 200, item)
      end)

      result = Pid.resolve(api, identifier)

      assert {:ok, %Object{} = object} = result, "Should return an Object struct on success"

      assert object.uuid == "8f62713a-c495-467b-a918-2e392f781d2e",
             "UUID should be mapped correctly"

      assert object.name ==
               "Usage of Concurrency Patterns and Fault Tolerance in Telecom Applications: An overview",
             "Name should be mapped correctly"

      assert object.type == "item", "Type should be mapped correctly"
    end

    test "returns not_found error when identifier not found", %{bypass: bypass, api: api} do
      identifier = "10.12345/nonexistent"

      Bypass.expect_once(bypass, "GET", "#{@api_endpoint}/find", fn conn ->
        respond_with_json(conn, 404, ~s({"message": "Identifier not found"}))
      end)

      result = Pid.resolve(api, identifier)

      assert {:error, %Error{type: :not_found}} = result,
             "Should return a not_found error for 404 response"
    end
  end

  defp url(bypass), do: "http://localhost:#{bypass.port}"
end
