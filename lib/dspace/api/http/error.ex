defmodule DSpace.API.HTTP.Error do
  @moduledoc """
  Represents an error with the connection to the API.
  """

  defexception [:request_url, :reason]

  @type t :: %__MODULE__{
          request_url: URI.t(),
          reason: term()
        }

  # Callbacks

  @spec message(t()) :: binary()
  @impl true
  def message(exception) do
    [request_url, _] =
      exception.request_url
      |> URI.to_string()
      |> String.split("?", parts: 2)

    """
    The DSpace API was unreachable.

    Requested endpoint:
    #{request_url}

    Reason:
    #{inspect(exception.reason, pretty: true)}
    """
  end
end
