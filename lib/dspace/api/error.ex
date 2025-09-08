defmodule DSpace.Api.Error do
  @moduledoc """
  Represents a DSpace API Error.
  """

  alias DSpace.Api.Http.Response

  # Expected error codes per API contract
  @expected_client_errors %{
    400 => :bad_request,
    401 => :unauthorized,
    403 => :forbidden,
    404 => :not_found,
    405 => :method_not_allowed,
    422 => :unprocessable_entity,
    429 => :too_many_requests
  }

  defexception [:type, :status, :message, :request_url, :response]

  @type t :: %__MODULE__{
          type: error_type(),
          status: non_neg_integer() | nil,
          message: binary(),
          request_url: binary(),
          response: Response.t()
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
          | :csrf_invalid
          | :api_unexpected_client_error
          | :api_unexpected_response
          | :api_unexpected_payload
          | :api_error

  # Public API

  @doc """
  Creates an error from a response.
  """
  @spec from_response(Response.t()) :: t()
  def from_response(%Response{status: 403, body: body} = response) do
    type = if csrf_token_error?(body), do: :api_csrf_invalid, else: :forbidden
    message = extract_message(body) || format_type(type)

    exception(type: type, status: 403, message: message, response: response)
  end

  def from_response(%Response{status: status, body: body} = response) when status in 400..499 do
    type = @expected_client_errors[status] || :api_unexpected_client_error
    message = extract_message(body) || format_type(type)

    exception(type: type, status: status, message: message, response: response)
  end

  def from_response(%Response{status: status, body: body} = response) when status >= 500 do
    message = extract_message(body) || format_type(:server_error)

    exception(type: :server_error, status: status, message: message, response: response)
  end

  def from_response(%Response{status: status, body: body} = response) do
    message = extract_message(body) || format_type(:api_unexpected_response)

    exception(type: :api_unexpected_response, status: status, message: message, response: response)
  end

  @doc """
  Creates a response validation error.
  """
  @spec response_validation_error(Response.t(), binary()) :: t()
  def response_validation_error(response, message \\ "API response data invalid for expected schema.") do
    status = Map.get(response, :status)

    exception(type: :api_unexpected_payload, status: status, message: message, response: response)
  end

  # Callbacks

  @spec exception(keyword() | binary()) :: t()
  @impl true
  def exception(attributes) when is_list(attributes) do
    attributes = Keyword.put_new(attributes, :request_url, attributes[:response].request_url)
    struct(__MODULE__, attributes)
  end

  def exception(message) when is_binary(message) do
    struct(__MODULE__, type: :api_error, message: message)
  end

  # Private helpers

  defp extract_message(%{"message" => msg}) when is_binary(msg), do: msg
  defp extract_message(_), do: nil

  defp format_type(type) when is_atom(type) do
    type
    |> Atom.to_string()
    |> String.replace("_", " ")
    |> String.capitalize()
  end

  defp csrf_token_error?(%{"message" => msg}) when is_binary(msg) do
    String.contains?(msg, "CSRF token")
  end

  defp csrf_token_error?(_), do: false
end
