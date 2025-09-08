defmodule DSpace.API.Error do
  @moduledoc """
  Represents an API Error.
  """

  import DSpace.API.Utils, only: [is_nonempty_binary: 1]

  alias DSpace.API.HTTP.Response

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
          status: non_neg_integer(),
          message: binary(),
          request_url: URI.t(),
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
          | :api_csrf_invalid
          | :api_unexpected_response
          | :api_unexpected_payload
          | :api_unexpected_client_error

  # Public API

  @doc """
  Builds an error from a response structure based on the HTTP status code.
  """
  @spec from_response(Response.t()) :: t()
  def from_response(%Response{status: 403, body: body} = response) do
    {type, message} = maybe_csrf_error(body)

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
  Builds a validation error from a response structure.
  """
  @spec response_validation_error(Response.t(), binary()) :: t()
  def response_validation_error(
        %Response{status: status} = response,
        message \\ "API response data invalid for expected schema."
      )
      when is_nonempty_binary(message) do
    exception(type: :api_unexpected_payload, status: status, message: message, response: response)
  end

  # Callbacks

  @spec exception(keyword() | binary()) :: t()
  @impl true
  def exception(attributes) when is_list(attributes) do
    attributes = Keyword.put_new(attributes, :request_url, attributes[:response].request_url)
    struct(__MODULE__, attributes)
  end

  # Private helpers

  defp extract_message(%{"message" => message}) when is_nonempty_binary(message), do: message
  defp extract_message(_), do: nil

  defp maybe_csrf_error(body) do
    message = extract_message(body)

    cond do
      is_nonempty_binary(message) and String.contains?(message, "CSRF token") ->
        {:api_csrf_invalid, message}

      is_nonempty_binary(message) ->
        {:forbidden, message}

      true ->
        {:forbidden, "Forbidden"}
    end
  end

  defp format_type(type) when is_atom(type) do
    type
    |> Atom.to_string()
    |> String.replace("_", " ")
    |> String.capitalize()
  end
end
