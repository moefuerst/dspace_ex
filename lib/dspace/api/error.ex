defmodule DSpace.Api.Error do
  @moduledoc """
  Represents errors from the DSpace API.
  """

  defstruct [:type, :status, :message, :response, :reason]

  @type t :: %__MODULE__{
          type: error_type(),
          status: non_neg_integer() | nil,
          message: String.t() | nil,
          response: map() | nil,
          reason: term() | nil
        }

  @type error_type ::
          :bad_request
          | :unauthorized
          | :forbidden
          | :not_found
          | :method_not_allowed
          | :unprocessable_entity
          | :too_many_requests
          | :server_error
          | :api_csrf_invalid
          | :api_response_validation
          | :api_timeout
          | :api_connection

  @client_error_status_map %{
    400 => :bad_request,
    401 => :unauthorized,
    403 => :forbidden,
    404 => :not_found,
    405 => :method_not_allowed,
    422 => :unprocessable_entity,
    429 => :too_many_requests
  }

  # Public API

  @doc """
  Creates a structured error from a response.
  """
  @spec from_response(map()) :: t()
  def from_response(%{status: 403, body: body} = response) do
    type = if csrf_token_error?(body), do: :api_csrf_invalid, else: :forbidden
    build(type, 403, body, response)
  end

  def from_response(%{status: status, body: body} = response) when status in 400..499 do
    type = @client_error_status_map[status] || :bad_request
    build(type, status, body, response)
  end

  def from_response(%{status: status, body: body} = response) when status >= 500 do
    build(:server_error, status, body, response)
  end

  # Responses without a body
  def from_response(%{status: status} = response) when status in 400..499 do
    type = @client_error_status_map[status] || :bad_request
    build(type, status, %{}, response)
  end

  def from_response(%{status: status} = response) when status >= 500 do
    build(:server_error, status, %{}, response)
  end

  @doc """
  Creates a connection error.
  """
  @spec connection_error(term()) :: t()
  def connection_error(%{reason: inner_reason} = _reason) do
    %__MODULE__{type: :api_connection, message: "Connection error", reason: inner_reason}
  end

  def connection_error(reason) do
    %__MODULE__{type: :api_connection, message: "Connection error", reason: reason}
  end

  @doc """
  Creates a timeout error.
  """
  @spec timeout_error(term() | nil) :: t()
  def timeout_error(reason \\ nil) do
    %__MODULE__{type: :api_timeout, message: "Request timed out", reason: reason}
  end

  @doc """
  Creates a response validation error.
  """
  def response_validation_error(
        response,
        message \\ "API response data invalid for expected schema"
      ) do
    %__MODULE__{type: :api_response_validation, message: message, response: response}
  end

  # Private helpers

  defp build(type, status, body, response) do
    %__MODULE__{
      type: type,
      status: status,
      message: extract_message(body) || default_message(type),
      response: response
    }
  end

  defp extract_message(%{"message" => msg}) when is_binary(msg), do: msg
  defp extract_message(_), do: nil

  # Never trust anything DSpace
  defp default_message(:bad_request), do: "Bad request"
  defp default_message(:unauthorized), do: "Authentication required"
  defp default_message(:forbidden), do: "Insufficient permissions for this operation"
  defp default_message(:not_found), do: "Resource not found"
  defp default_message(:method_not_allowed), do: "Method not allowed for this endpoint"
  defp default_message(:unprocessable_entity), do: "Request could not be processed"
  defp default_message(:too_many_requests), do: "Rate limit exceeded"
  defp default_message(:server_error), do: "Server error"
  defp default_message(:api_csrf_invalid), do: "Invalid CSRF token"
  defp default_message(_), do: "An error occurred"

  defp csrf_token_error?(%{"message" => msg}) when is_binary(msg) do
    String.contains?(msg, "CSRF token")
  end

  defp csrf_token_error?(_), do: false
end
