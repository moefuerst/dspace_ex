defmodule DSpace.Api.Error do
  @moduledoc false

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
    message = extract_message(body) || format_type(type)
    build(type, 403, message, response, body)
  end

  def from_response(%{status: status, body: body} = response) when status in 400..499 do
    type = @client_error_status_map[status] || :bad_request
    message = extract_message(body) || format_type(type)
    build(type, status, message, response, body)
  end

  def from_response(%{status: status, body: body} = response) when status >= 500 do
    message = extract_message(body) || format_type(:server_error)
    build(:server_error, status, message, response, body)
  end

  # Responses without a body
  def from_response(%{status: status} = response) when status in 400..499 do
    type = @client_error_status_map[status] || :bad_request
    build(type, status, format_type(type), response, nil)
  end

  def from_response(%{status: status} = response) when status >= 500 do
    build(:server_error, status, format_type(:server_error), response, nil)
  end

  @doc """
  Creates a connection error.
  """
  @spec connection_error(term()) :: t()
  def connection_error(reason) do
    message = format_reason(reason) || "API connection error"
    build(:api_connection, nil, message, nil, reason)
  end

  @doc """
  Creates a timeout error.
  """
  @spec timeout_error(term() | nil) :: t()
  def timeout_error(reason \\ nil) do
    message = format_reason(reason) || "API request timed out"
    build(:api_timeout, nil, message, nil, reason)
  end

  @doc """
  Creates a response validation error.
  """
  def response_validation_error(
        response,
        message \\ "API response data invalid for expected schema",
        reason \\ nil
      ) do
    status = if response && is_map(response), do: Map.get(response, :status), else: nil
    build(:api_response_validation, status, message, response, reason)
  end

  # Private helpers

  defp build(type, status, message, response, reason) do
    actual_reason =
      if response && is_map(response) && reason == Map.get(response, :body) do
        nil
      else
        reason
      end

    %__MODULE__{
      type: type,
      status: status,
      message: message,
      response: response,
      reason: actual_reason
    }
  end

  defp extract_message(%{"message" => msg}) when is_binary(msg), do: msg
  defp extract_message(_), do: nil

  # Minimal fallback message formatter
  defp format_type(type) when is_atom(type) do
    type
    |> Atom.to_string()
    |> String.replace("_", " ")
    |> String.capitalize()
  end

  defp format_type(_), do: "An error occurred"

  # Tries to get a useful message string from common error reasons
  defp format_reason({:error, reason}), do: format_reason(reason)
  defp format_reason({_, description}) when is_binary(description), do: description
  # Req errors etc.
  defp format_reason(%{message: msg}) when is_binary(msg), do: msg
  # e.g. :timeout, :nxdomain
  defp format_reason(reason) when is_atom(reason) and not is_nil(reason),
    do: Atom.to_string(reason)

  defp format_reason(reason) when is_binary(reason), do: reason
  defp format_reason(_), do: nil

  defp csrf_token_error?(%{"message" => msg}) when is_binary(msg) do
    String.contains?(msg, "CSRF token")
  end

  defp csrf_token_error?(_), do: false
end
