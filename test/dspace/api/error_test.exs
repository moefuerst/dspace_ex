defmodule DSpace.Api.ErrorTest do
  use ExUnit.Case, async: true
  alias DSpace.Api.Error

  describe "from_response/1" do
    test "maps HTTP status codes to appropriate error types" do
      assert Error.from_response(%{status: 400, body: %{}}).type == :bad_request,
             "400 response should map to :bad_request"

      assert Error.from_response(%{status: 500, body: %{}}).type == :server_error,
             "500 response should map to :server_error"
    end

    test "detects CSRF token issues in 403 responses" do
      regular_403 = %{status: 403, body: %{"message" => "Access denied"}}
      csrf_403 = %{status: 403, body: %{"message" => "CSRF token invalid"}}

      assert Error.from_response(regular_403).type == :forbidden,
             "403 that's not CSRF related should map to :forbidden"

      assert Error.from_response(csrf_403).type == :api_csrf_invalid,
             "403 with CSRF token message should map to :api_csrf_invalid"
    end

    test "extracts error message from response body" do
      response = %{status: 404, body: %{"message" => "DSpace error message"}}

      assert Error.from_response(response).message == "DSpace error message",
             "Should extract DSpace error message from response body"
    end

    test "uses default message when none provided in response" do
      assert Error.from_response(%{status: 404, body: %{}}).message == "Resource not found",
             "Should use default message when body has no message field"

      assert Error.from_response(%{status: 500, body: %{}}).message == "Server error",
             "Should use default message when body has no message field"
    end
  end

  describe "error creation functions" do
    test "create appropriate error types with given reasons" do
      conn_error = Error.connection_error(:econnrefused)
      timeout_error = Error.timeout_error(:timeout)
      validation_error = Error.response_validation_error(%{body: %{}}, "Custom message")

      assert conn_error.type == :api_connection,
             "Connection error should have :api_connection type"

      assert timeout_error.type == :api_timeout,
             "Timeout error should have :api_timeout type"

      assert validation_error.type == :api_response_validation,
             "Validation error should have :api_response_validation type"

      assert validation_error.message == "Custom message",
             "Validation error should preserve the custom message passed to it"
    end
  end
end
