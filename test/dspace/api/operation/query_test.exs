defmodule DSpace.API.Operation.QueryTest do
  use ExUnit.Case, async: true

  alias DSpace.API
  alias DSpace.API.Operation
  alias DSpace.API.Operation.Query

  setup do
    api = %API{
      endpoint: "https://example.com/server",
      http_impl: {TestHelper.HTTP, []},
      access_token: "test-access-token"
    }

    {:ok, api: api}
  end

  test "new/1 creates Query structure with defaults" do
    query = Query.new(path: "/api/test")

    assert %Query{} = query
    assert query.http_method == :get
    assert query.path == "/api/test"
    assert query.transformer == (&DSpace.API.Transform.from_response/1)
  end

  describe "query-specific behavior" do
    test "does not require CSRF token for safe method operations", %{api: api} do
      api = %{api | csrf_token: nil}
      operation = Query.new(path: "/api/test")

      result = Operation.perform(operation, api, [])

      assert_received {:http_request, options}
      assert options[:method] == :get
      refute Map.has_key?(options[:headers], "x-xsrf-token")
      assert {:ok, _response} = result
    end

    test "supports HEAD method", %{api: api} do
      operation = Query.new(path: "/api/test", http_method: :head)

      result = Operation.perform(operation, api, [])

      assert_received {:http_request, options}
      assert options[:method] == :head
      assert {:ok, _response} = result
    end

    test "supports POST method", %{api: api} do
      operation = Query.new(path: "/api/discover/search/objects", http_method: :post)

      result = Operation.perform(operation, api, [])

      assert_received {:http_request, options}
      assert options[:method] == :post
      assert {:ok, _response} = result
    end

    test "includes query parameters in request", %{api: api} do
      operation = Query.new(path: "/api/test", params: [page: 1, size: 20, sort: "name,asc"])

      result = Operation.perform(operation, api, [])

      assert_received {:http_request, options}
      assert options[:params] == [page: 1, size: 20, sort: "name,asc"]
      assert {:ok, _response} = result
    end

    test "includes headers in request", %{api: api} do
      operation = Query.new(path: "/api/test", headers: %{"x-custom-header" => ["custom-value"]})

      result = Operation.perform(operation, api, [])

      assert_received {:http_request, options}
      assert options[:headers]["x-custom-header"] == ["custom-value"]
      assert {:ok, _response} = result
    end
  end

  describe "transformer integration" do
    test "applies transformer to response", %{api: api} do
      custom_transformer = fn response -> {:custom, response.body} end

      operation = Query.new(path: "/api/test", transformer: custom_transformer)

      result = Operation.perform(operation, api, [])

      assert_received {:http_request, _options}
      assert {:ok, {:custom, %{"response" => "ok"}}} = result
    end

    test "applies transform: false to disable transformation", %{api: api} do
      operation_transformer = fn response -> {:operation, response.body} end

      operation = Query.new(path: "/api/test", transformer: operation_transformer)

      result = Operation.perform(operation, api, transform: false)

      assert_received {:http_request, _options}
      assert {:ok, %DSpace.API.HTTP.Response{body: %{"response" => "ok"}}} = result
    end
  end

  describe "before_step callback integration" do
    test "invokes before_step callback when present", %{api: api} do
      test_pid = self()

      callback = fn operation, api, options ->
        send(test_pid, {:callback_invoked, operation.path})
        {operation, api, options}
      end

      operation = Query.new(path: "/api/test", before_step: callback)

      Operation.perform(operation, api, [])

      assert_received {:callback_invoked, "/api/test"}
      assert_received {:http_request, _options}
    end
  end

  describe "streaming support" do
    test "invokes stream_impl when present" do
      test_pid = self()

      stream_impl = fn api, options ->
        send(test_pid, {:stream_invoked, api, options})
        [:item1, :item2]
      end

      operation = Query.new(path: "/api/test", stream_impl: stream_impl)
      api = %API{}

      result = Operation.stream!(operation, api, page: 1)

      assert_received {:stream_invoked, ^api, [page: 1]}
      assert Enum.to_list(result) == [:item1, :item2]
    end

    test "raises when stream_impl is nil" do
      operation = Query.new(path: "/api/test", stream_impl: nil)
      api = %API{}

      assert_raise ArgumentError, "this operation cannot be streamed", fn ->
        Operation.stream!(operation, api, [])
      end
    end
  end
end
