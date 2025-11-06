defmodule DSpace.API.ErrorTest do
  use ExUnit.Case, async: true

  alias DSpace.API.Error
  alias DSpace.API.HTTP.Response

  describe "from_response/1" do
    test "maps known 4xx status codes to appropriate error types" do
      # Samples
      response_400 = %Response{status: 400, body: %{}}
      response_429 = %Response{status: 429, body: %{}, request_url: "/endpoint"}

      error_400 = Error.from_response(response_400)
      error_429 = Error.from_response(response_429)

      assert error_400.type == :bad_request, "400 response should map to :bad_request"
      assert error_400.status == 400, "Status should be preserved"

      assert error_400.message == "Bad request",
             "Should return fallback message if response is missing message"

      assert error_429.type == :too_many_requests, "429 response should map to :too_many_requests"
      assert error_429.status == 429, "Status should be preserved"
      assert error_429.request_url == "/endpoint", "Error should contain requested endpoint"
    end

    test "maps unknown 4xx status codes to :api_unexpected_client_error" do
      response = %Response{status: 418, body: %{"message" => "I'm a teapot"}}

      error = Error.from_response(response)

      assert error.type == :api_unexpected_client_error,
             "Unknown 4xx (418) should default to :api_unexpected_client_error"

      assert error.status == 418, "Status should be preserved"
    end

    test "maps 5xx status codes to :server_error" do
      response_503 = %Response{status: 503, body: %{}}

      error_503 = Error.from_response(response_503)

      assert error_503.type == :server_error, "503 response should map to :server_error"
      assert error_503.status == 503, "Status should be preserved"
    end

    test "detects CSRF token issues in 403 responses" do
      response = %Response{status: 403, body: %{"message" => "Invalid CSRF token"}}

      error = Error.from_response(response)

      assert error.type == :api_csrf_invalid,
             "403 with CSRF token message should map to :api_csrf_invalid"

      assert error.status == 403, "Status should be 403"
      assert error.message == "Invalid CSRF token", "Should extract CSRF message"
    end

    test "handles regular 403 responses as :forbidden" do
      response = %Response{status: 403, body: %{"message" => "Access denied"}}

      error = Error.from_response(response)

      assert error.type == :forbidden,
             "403 without CSRF message should map to :forbidden"

      assert error.status == 403, "Status should be 403"
      assert error.message == "Access denied", "Should extract non-CSRF message"
    end

    test "extracts error message from response body" do
      response = %Response{status: 404, body: %{"message" => "DSpace error not found message"}}

      error = Error.from_response(response)

      assert error.message == "DSpace error not found message",
             "Should extract DSpace error message from response body"

      assert error.type == :not_found, "Type should still be correctly mapped (404 -> :not_found)"
      assert error.status == 404, "Status should be preserved"
    end

    test "uses default message when message cannot be extracted (4xx)" do
      response_empty_body = %Response{status: 401, body: %{}}
      response_nil_body = %Response{status: 401, body: nil}
      response_string_body = %Response{status: 401, body: "Unauthorized access attempt"}
      response_wrong_key = %Response{status: 401, body: %{"error" => "unauthorized"}}

      error_empty_body = Error.from_response(response_empty_body)
      error_nil_body = Error.from_response(response_nil_body)
      error_string_body = Error.from_response(response_string_body)
      error_wrong_key = Error.from_response(response_wrong_key)

      expected_message = "Unauthorized"
      assert error_empty_body.message == expected_message, "Should use default for empty body map"
      assert error_nil_body.message == expected_message, "Should use default for nil body"
      assert error_string_body.message == expected_message, "Should use default for non-map body"

      assert error_wrong_key.message == expected_message,
             "Should use default if 'message' key missing"
    end

    test "uses default message when message cannot be extracted (5xx)" do
      response_empty_body = %Response{status: 500, body: %{}}
      response_nil_body = %Response{status: 500, body: nil}

      error_empty_body = Error.from_response(response_empty_body)
      error_nil_body = Error.from_response(response_nil_body)

      expected_message = "Server error"

      assert error_empty_body.message == expected_message, "Should use default for empty body map"
      assert error_nil_body.message == expected_message, "Should use default for nil body"
    end
  end

  describe "response_validation_error/2" do
    test "creates validation error with reason" do
      response = %Response{status: 123, body: %{"data" => "valid", "missing_field" => true}}
      message = "Missing field"

      error = Error.response_validation_error(response, message)

      assert error.type == :api_unexpected_payload, "Type should be :api_unexpected_payload"
      assert error.status == 123, "Should extract status from response"
      assert error.message == message, "Message should be stored"
    end
  end
end
