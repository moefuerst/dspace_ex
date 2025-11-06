defmodule DSpace.API.Operation.HelpersTest do
  use ExUnit.Case, async: true

  alias DSpace.API
  alias DSpace.API.HTTP.Response
  alias DSpace.API.Operation
  alias DSpace.API.Operation.Helpers

  describe "maybe_apply_version_overrides/2" do
    test "returns operation unchanged when api_version is nil" do
      operation = %Operation.Query{path: "/test", http_method: :get}
      client = %API{api_version: nil}
      result = Helpers.maybe_apply_version_overrides(operation, client)
      assert result == operation
    end

    test "returns operation unchanged when no overrides match" do
      operation = %Operation.Query{
        path: "/test",
        http_method: :get,
        version_overrides: [{">= 8.0.0", [http_method: :post]}]
      }

      client = %API{api_version: "7.6.1"}
      result = Helpers.maybe_apply_version_overrides(operation, client)
      assert result.http_method == :get
    end

    test "applies simple field override when version matches" do
      operation = %Operation.Query{
        path: "/test",
        http_method: :get,
        version_overrides: [{">= 7.5.0", [http_method: :post]}]
      }

      client = %API{api_version: "7.5.0"}
      result = Helpers.maybe_apply_version_overrides(operation, client)
      assert result.http_method == :post
    end

    test "applies multiple overrides when both match" do
      operation = %Operation.Query{
        path: "/test",
        http_method: :get,
        headers: %{},
        version_overrides: [
          {">= 7.0.0", [http_method: :post]},
          {">= 7.5.0", [headers: %{"x-test" => ["value"]}]}
        ]
      }

      client = %API{api_version: "7.5.0"}
      result = Helpers.maybe_apply_version_overrides(operation, client)
      assert result.http_method == :post
      assert result.headers == %{"x-test" => ["value"]}
    end

    test "handles invalid version specification gracefully" do
      operation = %Operation.Query{
        path: "/test",
        http_method: :get,
        version_overrides: [{"invalid-version-spec", [http_method: :post]}]
      }

      client = %API{api_version: "7.6.1"}
      result = Helpers.maybe_apply_version_overrides(operation, client)
      assert result.http_method == :get
    end

    test "supports version operators" do
      operation = %Operation.Query{
        path: "/original",
        version_overrides: [
          {"< 7.5.0", [path: "/legacy"]},
          {"~> 7.6.0", [path: "/compatible"]},
          {"== 8.0.0", [path: "/exact"]}
        ]
      }

      client = %API{api_version: "7.4.0"}
      result = Helpers.maybe_apply_version_overrides(operation, client)
      assert result.path == "/legacy"

      client = %API{api_version: "7.6.2"}
      result = Helpers.maybe_apply_version_overrides(operation, client)
      assert result.path == "/compatible"

      client = %API{api_version: "8.0.0"}
      result = Helpers.maybe_apply_version_overrides(operation, client)
      assert result.path == "/exact"

      client = %API{api_version: "9.0.0"}
      result = Helpers.maybe_apply_version_overrides(operation, client)
      assert result.path == "/original"
    end
  end

  describe "maybe_invoke_session_callback/2" do
    test "returns when session_callback is nil" do
      client = %API{session_callback: nil}

      response = %Response{
        headers: %{"dspace-xsrf-token" => ["test-token"]}
      }

      assert Helpers.maybe_invoke_session_callback(client, response) == :ok
    end

    test "invokes callback when CSRF token is present" do
      test_pid = self()

      callback = fn token_data ->
        send(test_pid, {:callback_invoked, token_data})
      end

      client = %API{session_callback: callback}

      response = %Response{
        headers: %{"dspace-xsrf-token" => ["test-token"]}
      }

      Helpers.maybe_invoke_session_callback(client, response)

      assert_receive {:callback_invoked, %{csrf_token: "test-token"}}
    end

    test "does not invoke callback when CSRF token is missing" do
      test_pid = self()

      callback = fn token_data ->
        send(test_pid, {:callback_invoked, token_data})
      end

      client = %API{session_callback: callback}

      response = %Response{
        headers: %{"other-header" => ["value"]}
      }

      assert Helpers.maybe_invoke_session_callback(client, response) == :ok
      refute_receive {:callback_invoked, _}
    end

    test "isolates callback errors and continues operation" do
      callback = fn _token_data ->
        raise "callback error"
      end

      client = %API{session_callback: callback}

      response = %Response{
        headers: %{"dspace-xsrf-token" => ["test-token"]}
      }

      assert Helpers.maybe_invoke_session_callback(client, response) == :ok
    end
  end
end
