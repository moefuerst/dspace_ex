defmodule DSpace.Api.ErrorTest do
  use ExUnit.Case, async: true
  alias DSpace.Api.Error

  describe "from_response/1" do
    test "maps known 4xx status codes to appropriate error types" do
      # Samples
      response_400 = %{status: 400, body: %{}}
      response_429 = %{status: 429, body: %{}}

      error_400 = Error.from_response(response_400)
      error_429 = Error.from_response(response_429)

      assert error_400.type == :bad_request, "400 response should map to :bad_request"
      assert error_400.status == 400, "Status should be preserved"
      assert error_400.response == response_400, "Response should be stored"

      assert error_429.type == :too_many_requests, "429 response should map to :too_many_requests"
      assert error_429.status == 429, "Status should be preserved"
      assert error_429.response == response_429, "Response should be stored"
    end

    test "maps unknown 4xx status codes to :bad_request" do
      # I'm a teapot
      response = %{status: 418, body: %{}}

      error = Error.from_response(response)

      assert error.type == :bad_request, "Unknown 4xx (418) should default to :bad_request"
      assert error.status == 418, "Status should be preserved"
      assert error.response == response, "Response should be stored"
    end

    test "maps 5xx status codes to :server_error" do
      response_503 = %{status: 503, body: %{}}

      error_503 = Error.from_response(response_503)

      assert error_503.type == :server_error, "503 response should map to :server_error"
      assert error_503.status == 503, "Status should be preserved"
      assert error_503.response == response_503, "Response should be stored"
    end

    test "detects CSRF token issues in 403 responses" do
      response = %{status: 403, body: %{"message" => "Invalid CSRF token"}}

      error = Error.from_response(response)

      assert error.type == :api_csrf_invalid,
             "403 with CSRF token message should map to :api_csrf_invalid"

      assert error.status == 403, "Status should be 403"
      assert error.message == "Invalid CSRF token", "Should extract CSRF message"
      assert error.response == response, "Response should be stored"
    end

    test "handles regular 403 responses as :forbidden" do
      response = %{status: 403, body: %{"message" => "Access denied"}}

      error = Error.from_response(response)

      assert error.type == :forbidden,
             "403 without CSRF message should map to :forbidden"

      assert error.status == 403, "Status should be 403"
      assert error.message == "Access denied", "Should extract non-CSRF message"
      assert error.response == response, "Response should be stored"
    end

    test "extracts error message from response body" do
      response = %{status: 404, body: %{"message" => "DSpace error not found message"}}

      error = Error.from_response(response)

      assert error.message == "DSpace error not found message",
             "Should extract DSpace error message from response body"

      assert error.type == :not_found, "Type should still be correctly mapped (404 -> :not_found)"
      assert error.status == 404, "Status should be preserved"
    end

    test "uses default message when message cannot be extracted (4xx)" do
      response_empty_body = %{status: 401, body: %{}}
      response_nil_body = %{status: 401, body: nil}
      response_string_body = %{status: 401, body: "Unauthorized access attempt"}
      response_wrong_key = %{status: 401, body: %{"error" => "unauthorized"}}

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

      # Fully check one example
      assert error_empty_body.type == :unauthorized, "Type should be correct"
      assert error_empty_body.status == 401, "Status should be correct"
      assert error_empty_body.response == response_empty_body, "Response should be stored"
      assert error_empty_body.reason == nil, "Reason should be nil"
    end

    test "uses default message when message cannot be extracted (5xx)" do
      response_empty_body = %{status: 500, body: %{}}
      response_nil_body = %{status: 500, body: nil}

      error_empty_body = Error.from_response(response_empty_body)
      error_nil_body = Error.from_response(response_nil_body)

      expected_message = "Server error"

      assert error_empty_body.message == expected_message, "Should use default for empty body map"
      assert error_nil_body.message == expected_message, "Should use default for nil body"

      # Fully check one example
      assert error_empty_body.type == :server_error, "Type should be correct"
      assert error_empty_body.status == 500, "Status should be correct"
      assert error_empty_body.response == response_empty_body, "Response should be stored"
      assert error_empty_body.reason == nil, "Reason should be nil"
    end
  end

  describe "connection_error/1" do
    test "creates connection error with formatted message from atom reason" do
      reason = :econnrefused

      error = Error.connection_error(reason)

      assert error.type == :api_connection, "Type should be :api_connection"
      assert error.status == nil, "Status should be nil for connection errors"
      assert error.message == "econnrefused", "Message should be formatted atom"
      assert error.response == nil, "Response should be nil"
      assert error.reason == reason, "Reason should be stored"
    end

    test "creates connection error with formatted message from tuple reason" do
      reason = {:error, :nxdomain}
      reason_str = {:error, "TLS handshake failed"}

      error = Error.connection_error(reason)
      error_str = Error.connection_error(reason_str)

      assert error.type == :api_connection, "Type should be :api_connection"
      assert error.status == nil, "Status should be nil"
      assert error.message == "nxdomain", "Message should be formatted from tuple's atom"
      assert error.response == nil, "Response should be nil"
      assert error.reason == reason, "Reason should be stored"

      assert error_str.message == "TLS handshake failed",
             "Message should be formatted from tuple's string"

      assert error_str.reason == reason_str, "Reason should be stored"
    end

    test "creates connection error with message from map reason" do
      reason = %{message: "Underlying HTTP client error"}

      error = Error.connection_error(reason)

      assert error.type == :api_connection, "Type should be :api_connection"
      assert error.status == nil, "Status should be nil"

      assert error.message == "Underlying HTTP client error",
             "Message should be extracted from map"

      assert error.response == nil, "Response should be nil"
      assert error.reason == reason, "Reason should be stored"
    end

    test "creates connection error with default message for unformattable reason" do
      reason = %{some: :other_structure}

      error = Error.connection_error(reason)

      assert error.type == :api_connection, "Type should be :api_connection"
      assert error.status == nil, "Status should be nil"
      assert error.message == "API connection error", "Should use default message"
      assert error.response == nil, "Response should be nil"
      assert error.reason == reason, "Reason should be stored"
    end
  end

  describe "timeout_error/1" do
    test "creates timeout error with default message when no reason given" do
      error = Error.timeout_error()

      assert error.type == :api_timeout, "Type should be :api_timeout"
      assert error.status == nil, "Status should be nil for timeout errors"
      assert error.message == "API request timed out", "Should use default message"
      assert error.reason == nil, "Reason should be nil"
    end

    test "creates timeout error with formatted message from atom reason" do
      reason = :timeout

      error = Error.timeout_error(reason)

      assert error.type == :api_timeout, "Type should be :api_timeout"
      assert error.status == nil, "Status should be nil"
      assert error.message == "timeout", "Message should be formatted atom"
      assert error.reason == reason, "Reason should be stored"
    end

    test "creates timeout error with default message for unformattable reason" do
      # format_reason/1 won't handle that specifically
      reason = 12_345

      error = Error.timeout_error(reason)

      assert error.type == :api_timeout, "Type should be :api_timeout"
      assert error.status == nil, "Status should be nil"
      assert error.message == "API request timed out", "Should use default message"
      assert error.reason == reason, "Reason should be stored"
    end
  end

  describe "response_validation_error/3" do
    test "creates validation error with custom message and reason" do
      response = %{status: 200, body: %{"data" => "valid", "missing_field" => true}}
      custom_message = "Required field 'xyz' is missing"
      reason = {:missing_field, :xyz}

      error = Error.response_validation_error(response, custom_message, reason)

      assert error.type == :api_response_validation, "Type should be :api_response_validation"
      assert error.status == 200, "Should extract status from response"
      assert error.message == custom_message, "Should use custom message"
      assert error.response == response, "Response should be stored"
      assert error.reason == reason, "Reason should be stored"
    end
  end
end
