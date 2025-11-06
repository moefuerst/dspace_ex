defmodule DSpace.API.Operation.ActionTest do
  use ExUnit.Case, async: true

  alias DSpace.API
  alias DSpace.API.Operation
  alias DSpace.API.Operation.Action

  setup do
    client =
      %API{
        endpoint: "https://example.com/server",
        http_impl: {TestHelper.HTTP, []},
        csrf_token: "test-csrf-token",
        access_token: "test-access-token"
      }

    {:ok, client: client}
  end

  test "new/1 creates Action structure with defaults" do
    action = Action.new(path: "/api/test", data: %{})

    assert %Action{} = action
    assert action.http_method == :post
    assert action.type == :json
    assert action.path == "/api/test"
    assert action.data == %{}
    assert action.transformer == (&DSpace.API.Transform.from_response/1)
  end

  describe "error scenarios" do
    test "raises when CSRF token is missing for actions" do
      client = %API{
        endpoint: "https://example.com/server",
        http_impl: {TestHelper.HTTP, []},
        csrf_token: nil,
        access_token: "test-access-token"
      }

      operation = Action.new(path: "/api/test", data: %{})

      assert_raise ArgumentError, fn ->
        Operation.perform(operation, client, [])
      end
    end
  end

  describe "transformer integration" do
    test "applies transformer to response", %{client: client} do
      custom_transformer = fn response -> {:custom, response.body} end

      operation = Action.new(path: "/api/test", transformer: custom_transformer)

      result = Operation.perform(operation, client, [])

      assert_received {:http_request, _options}
      assert {:ok, {:custom, %{"response" => "ok"}}} = result
    end

    test "applies transform: false to disable transformation", %{client: client} do
      operation_transformer = fn response -> {:operation, response.body} end

      operation = Action.new(path: "/api/test", transformer: operation_transformer)

      result = Operation.perform(operation, client, transform: false)

      assert_received {:http_request, _options}
      assert {:ok, %DSpace.API.HTTP.Response{body: %{"response" => "ok"}}} = result
    end
  end

  describe "content type handling" do
    test "handles :json type with default content-type", %{client: client} do
      operation =
        Action.new(
          path: "/api/test",
          type: :json,
          data: %{"key" => "value"}
        )

      Operation.perform(operation, client, [])

      assert_received {:http_request, options}
      assert options[:json] == %{"key" => "value"}
      assert options[:headers][:accept] == ["application/json"]
    end

    test "handles :form type with form encoding", %{client: client} do
      operation =
        Action.new(
          path: "/api/auth",
          type: :form,
          data: %{"username" => "test", "password" => "secret"}
        )

      Operation.perform(operation, client, [])

      assert_received {:http_request, options}
      assert options[:form] == %{"username" => "test", "password" => "secret"}
    end

    test "handles :multipart type with multipart encoding", %{client: client} do
      operation =
        Action.new(
          path: "/api/upload",
          type: :multipart,
          data: %{"file" => "content", "metadata" => "info"}
        )

      Operation.perform(operation, client, [])

      assert_received {:http_request, options}
      assert options[:form_multipart] == %{"file" => "content", "metadata" => "info"}
    end

    test "handles :uri_list type with uri list encoding", %{client: client} do
      operation =
        Action.new(
          path: "/api/batch",
          type: :uri_list,
          data: ["https://example.com/1", "https://example.com/2"]
        )

      Operation.perform(operation, client, [])

      assert_received {:http_request, options}
      assert options[:body] == "https://example.com/1\nhttps://example.com/2"
      assert options[:headers][:content_type] == ["text/uri-list"]
    end
  end

  describe "before_step callback integration" do
    test "invokes before_step callback when present", %{client: client} do
      test_pid = self()

      callback = fn operation, client, options ->
        send(test_pid, {:callback_invoked, operation.path})
        {operation, client, options}
      end

      operation =
        Action.new(
          path: "/api/test",
          data: %{"test" => "data"},
          before_step: callback
        )

      Operation.perform(operation, client, [])

      assert_received {:callback_invoked, "/api/test"}
      assert_received {:http_request, _options}
    end
  end
end
