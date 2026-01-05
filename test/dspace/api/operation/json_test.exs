defmodule DSpace.API.Operation.JSONTest do
  use ExUnit.Case, async: true

  alias DSpace.API
  alias DSpace.API.HTTP.Response
  alias DSpace.API.Operation
  alias DSpace.API.Operation.JSON, as: JSONOp

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

  describe "new/1" do
    test "creates JSONOp op structure with defaults" do
      op = JSONOp.new(path: "/api/test")

      assert %JSONOp{} = op
      assert op.http_method == :get
      assert op.path == "/api/test"
      assert op.data == nil
      assert op.content_type == :json
      assert op.csrf == :auto
      assert op.transformer == (&DSpace.API.Transform.from_response/1)
    end

    test "creates JSONOp structure with write defaults" do
      op = JSONOp.new(path: "/api/test", http_method: :post, data: %{})

      assert %JSONOp{} = op
      assert op.http_method == :post
      assert op.path == "/api/test"
      assert op.data == %{}
      assert op.content_type == :json
      assert op.csrf == :auto
    end
  end

  describe "CSRF handling" do
    test "does not require CSRF token for GET operations (auto mode)", %{client: client} do
      client = %{client | csrf_token: nil}
      operation = JSONOp.new(path: "/api/test")

      _result = Operation.perform(operation, client, [])

      assert_received {:http_request, options}
      assert options[:method] == :get
      refute Map.has_key?(options[:headers], "x-xsrf-token")
    end

    test "does not require CSRF token for HEAD operations (auto mode)", %{client: client} do
      client = %{client | csrf_token: nil}
      operation = JSONOp.new(path: "/api/test", http_method: :head)

      _result = Operation.perform(operation, client, [])

      assert_received {:http_request, options}
      assert options[:method] == :head
      refute Map.has_key?(options[:headers], "x-xsrf-token")
    end

    test "requires CSRF token for POST operations (auto mode)", %{client: client} do
      client = %{client | csrf_token: nil}
      operation = JSONOp.new(path: "/api/test", http_method: :post, data: %{})

      assert_raise ArgumentError, ~r/CSRF token/, fn ->
        Operation.perform(operation, client, [])
      end
    end

    test "requires CSRF token for PUT operations (auto mode)", %{client: client} do
      client = %{client | csrf_token: nil}
      operation = JSONOp.new(path: "/api/test", http_method: :put, data: %{})

      assert_raise ArgumentError, ~r/CSRF token/, fn ->
        Operation.perform(operation, client, [])
      end
    end

    test "requires CSRF token for PATCH operations (auto mode)", %{client: client} do
      client = %{client | csrf_token: nil}
      operation = JSONOp.new(path: "/api/test", http_method: :patch, data: %{})

      assert_raise ArgumentError, ~r/CSRF token/, fn ->
        Operation.perform(operation, client, [])
      end
    end

    test "requires CSRF token for DELETE operations (auto mode)", %{client: client} do
      client = %{client | csrf_token: nil}
      operation = JSONOp.new(path: "/api/test", http_method: :delete)

      assert_raise ArgumentError, ~r/CSRF token/, fn ->
        Operation.perform(operation, client, [])
      end
    end

    test "includes CSRF token for mutating operations when present", %{client: client} do
      operation = JSONOp.new(path: "/api/test", http_method: :post, data: %{})

      _result = Operation.perform(operation, client, [])

      assert_received {:http_request, options}
      assert options[:headers]["x-xsrf-token"] == ["test-csrf-token"]
    end

    test "includes CSRF token for GET when available (auto mode)", %{client: client} do
      operation = JSONOp.new(path: "/api/test")

      _result = Operation.perform(operation, client, [])

      assert_received {:http_request, options}
      assert options[:headers]["x-xsrf-token"] == ["test-csrf-token"]
    end

    test "csrf: :required raises when token is nil", %{client: client} do
      client = %{client | csrf_token: nil}
      operation = JSONOp.new(path: "/api/test", csrf: :required)

      assert_raise ArgumentError, ~r/CSRF token/, fn ->
        Operation.perform(operation, client, [])
      end
    end

    test "csrf: :optional does not raise when token is nil", %{client: client} do
      client = %{client | csrf_token: nil}
      operation = JSONOp.new(path: "/api/test", http_method: :post, data: %{}, csrf: :optional)

      _result = Operation.perform(operation, client, [])

      assert_received {:http_request, options}
      refute Map.has_key?(options[:headers], "x-xsrf-token")
    end

    test "csrf: :skip never includes CSRF token", %{client: client} do
      operation = JSONOp.new(path: "/api/test", http_method: :post, data: %{}, csrf: :skip)

      _result = Operation.perform(operation, client, [])

      assert_received {:http_request, options}
      refute Map.has_key?(options[:headers], "x-xsrf-token")
    end
  end

  describe "HTTP support" do
    test "includes query parameters in request", %{client: client} do
      operation = JSONOp.new(path: "/api/test", params: [page: 1, size: 20, sort: "name,asc"])

      _result = Operation.perform(operation, client, [])

      assert_received {:http_request, options}
      assert options[:params] == [page: 1, size: 20, sort: "name,asc"]
    end

    test "includes headers in request", %{client: client} do
      operation = JSONOp.new(path: "/api/test", headers: %{"x-custom-header" => ["custom-value"]})

      _result = Operation.perform(operation, client, [])

      assert_received {:http_request, options}
      assert options[:headers]["x-custom-header"] == ["custom-value"]
    end
  end

  describe "content type handling" do
    test "handles :json content_type with default content-type", %{client: client} do
      operation =
        JSONOp.new(
          path: "/api/test",
          http_method: :post,
          content_type: :json,
          data: %{"key" => "value"}
        )

      _result = Operation.perform(operation, client, [])

      assert_received {:http_request, options}
      assert options[:json] == %{"key" => "value"}
    end

    test "handles :form content_type with form encoding", %{client: client} do
      operation =
        JSONOp.new(
          path: "/api/auth",
          http_method: :post,
          content_type: :form,
          data: %{"username" => "test", "password" => "secret"}
        )

      _result = Operation.perform(operation, client, [])

      assert_received {:http_request, options}
      assert options[:form] == %{"username" => "test", "password" => "secret"}
    end

    test "handles :multipart content_type with multipart encoding", %{client: client} do
      operation =
        JSONOp.new(
          path: "/api/upload",
          http_method: :post,
          content_type: :multipart,
          data: %{"file" => "content", "metadata" => "info"}
        )

      _result = Operation.perform(operation, client, [])

      assert_received {:http_request, options}
      assert options[:form_multipart] == %{"file" => "content", "metadata" => "info"}
    end

    test "handles :uri_list content_type with uri list encoding", %{client: client} do
      operation =
        JSONOp.new(
          path: "/api/batch",
          http_method: :post,
          content_type: :uri_list,
          data: ["https://example.com/1", "https://example.com/2"]
        )

      _result = Operation.perform(operation, client, [])

      assert_received {:http_request, options}
      assert options[:body] == "https://example.com/1\nhttps://example.com/2"
      assert options[:headers][:content_type] == ["text/uri-list"]
    end

    test "does not include body options when data is nil", %{client: client} do
      operation = JSONOp.new(path: "/api/test")

      _result = Operation.perform(operation, client, [])

      assert_received {:http_request, options}
      refute Keyword.has_key?(options, :json)
      refute Keyword.has_key?(options, :form)
      refute Keyword.has_key?(options, :body)
      refute Keyword.has_key?(options, :form_multipart)
    end
  end

  describe "transformer integration" do
    test "applies transformer to response", %{client: client} do
      custom_transformer = fn response -> {:custom, response.body} end
      operation = JSONOp.new(path: "/api/test", transformer: custom_transformer)

      result = Operation.perform(operation, client, [])

      assert {:ok, {:custom, %{"response" => "ok"}}} = result
    end

    test "applies transform: false to disable transformation", %{client: client} do
      operation_transformer = fn response -> {:operation, response.body} end
      operation = JSONOp.new(path: "/api/test", transformer: operation_transformer)

      result = Operation.perform(operation, client, transform: false)

      assert {:ok, %Response{body: %{"response" => "ok"}}} = result
    end
  end

  describe "before_step callback integration" do
    test "invokes callback when present", %{client: client} do
      test_pid = self()

      callback = fn operation, client, options ->
        send(test_pid, {:callback_invoked, operation.path})
        {operation, client, options}
      end

      operation = JSONOp.new(path: "/api/test", before_step: callback)

      _result = Operation.perform(operation, client, [])

      assert_received {:callback_invoked, "/api/test"}
    end
  end

  describe "streaming support" do
    test "invokes stream_impl when present" do
      test_pid = self()

      stream_impl = fn api, options ->
        send(test_pid, {:stream_invoked, api, options})
        [:item1, :item2]
      end

      operation = JSONOp.new(path: "/api/test", stream_impl: stream_impl)
      api = %API{}

      result = Operation.stream!(operation, api, page: 1)

      assert_received {:stream_invoked, ^api, [page: 1]}
      assert Enum.to_list(result) == [:item1, :item2]
    end

    test "raises when stream_impl is nil" do
      operation = JSONOp.new(path: "/api/test", stream_impl: nil)
      api = %API{}

      assert_raise ArgumentError, "this operation cannot be streamed", fn ->
        Operation.stream!(operation, api, [])
      end
    end
  end

  describe "version overrides" do
    test "returns operation unchanged when api_version is nil", %{client: client} do
      operation = %JSONOp{path: "/test", http_method: :get}
      client = %{client | api_version: nil}

      _result = Operation.perform(operation, client, [])

      assert_received {:http_request, options}
      assert options[:url].path == "/server/test"
    end

    test "returns operation unchanged when no overrides match", %{client: client} do
      client = %{client | api_version: "7.6.1"}

      operation = %JSONOp{
        path: "/test",
        version_overrides: [{">= 8.0.0", [path: "/upgraded"]}]
      }

      _result = Operation.perform(operation, client, [])

      assert_received {:http_request, options}
      assert options[:url].path == "/server/test"
    end

    test "applies field override when version matches", %{client: client} do
      client = %{client | api_version: "7.5.0"}

      operation = %JSONOp{
        path: "/test",
        version_overrides: [{">= 7.5.0", [path: "/upgraded"]}]
      }

      _result = Operation.perform(operation, client, [])

      assert_received {:http_request, options}
      assert options[:url].path == "/server/upgraded"
    end

    test "applies multiple overrides when both match", %{client: client} do
      client = %{client | api_version: "7.5.0"}

      operation = %JSONOp{
        path: "/test",
        http_method: :get,
        headers: %{},
        version_overrides: [
          {">= 7.0.0", [http_method: :post, csrf: :skip]},
          {">= 7.5.0", [headers: %{"x-test" => ["value"]}]}
        ]
      }

      _result = Operation.perform(%{operation | csrf: :skip}, client, [])

      assert_received {:http_request, options}
      assert options[:method] == :post
      assert options[:headers]["x-test"] == ["value"]
    end

    test "handles invalid version specification gracefully", %{client: client} do
      client = %{client | api_version: "7.6.1"}

      operation = %JSONOp{
        path: "/test",
        version_overrides: [{"invalid-version-spec", [path: "/bad"]}]
      }

      _result = Operation.perform(operation, client, [])

      assert_received {:http_request, options}
      assert options[:url].path == "/server/test"
    end

    test "supports version operators", %{client: client} do
      operation = %JSONOp{
        path: "/original",
        version_overrides: [
          {"< 7.5.0", [path: "/legacy"]},
          {"~> 7.6.0", [path: "/compatible"]},
          {"== 8.0.0", [path: "/exact"]}
        ]
      }

      client_74 = %{client | api_version: "7.4.0"}
      _result = Operation.perform(operation, client_74, [])
      assert_received {:http_request, options}
      assert options[:url].path == "/server/legacy"

      client_762 = %{client | api_version: "7.6.2"}
      _result = Operation.perform(operation, client_762, [])
      assert_received {:http_request, options}
      assert options[:url].path == "/server/compatible"

      client_800 = %{client | api_version: "8.0.0"}
      _result = Operation.perform(operation, client_800, [])
      assert_received {:http_request, options}
      assert options[:url].path == "/server/exact"

      client_900 = %{client | api_version: "9.0.0"}
      _result = Operation.perform(operation, client_900, [])
      assert_received {:http_request, options}
      assert options[:url].path == "/server/original"
    end

    test "handles overriding same field multiple times", %{client: client} do
      client = %{client | api_version: "7.5.0"}

      operation = %JSONOp{
        path: "/test",
        version_overrides: [
          {">= 7.0.0", [path: "/first"]},
          {">= 7.5.0", [path: "/second"]}
        ]
      }

      _result = Operation.perform(operation, client, [])

      assert_received {:http_request, options}
      assert options[:url].path == "/server/second"
    end
  end

  describe "on_response_hook" do
    test "handles callback errors gracefully", %{client: client} do
      callback = fn _token_data -> raise "hook error" end
      client = %{client | on_response_hook: callback}
      operation = JSONOp.new(path: "/api/test")

      # Should not raise as errors in the hook are rescued
      {:ok, _result} = Operation.perform(operation, client, [])

      assert_received {:http_request, _options}
    end
  end
end
