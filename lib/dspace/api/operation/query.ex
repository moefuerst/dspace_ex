defmodule DSpace.API.Operation.Query do
  @moduledoc """
  Represents an operation that retrieves data from the API.
  """

  defstruct http_method: :get,
            path: "/",
            transformer: &DSpace.API.Transform.from_response/1,
            params: [],
            headers: %{},
            version_overrides: [],
            before_step: nil,
            stream_impl: nil

  @type t :: %__MODULE__{
          http_method: :get | :head | :post,
          path: binary(),
          transformer: function(),
          params: keyword(),
          headers: %{optional(binary()) => [binary()]},
          version_overrides: [{binary(), keyword()}],
          before_step: function() | nil,
          stream_impl: function() | nil
        }

  def new(options) do
    struct(%__MODULE__{}, options)
  end

  defimpl DSpace.API.Operation do
    import DSpace.API.Operation.Helpers

    alias DSpace.API.HTTP
    alias DSpace.API.Operation.Query

    @spec perform(Query.t(), DSpace.API.t(), keyword()) :: {:ok, term()} | {:error, Exception.t()}
    def perform(operation, client, override_options) do
      {operation, client, override_options} =
        maybe_invoke_callback(operation, client, override_options)

      operation = maybe_apply_version_overrides(operation, client)
      {http_impl, client_config} = client.http_impl

      headers =
        %{
          :accept => ["application/json"],
          :user_agent => [client.user_agent]
        }
        |> Map.merge(operation.headers)
        |> maybe_add_auth_header(client.access_token)
        |> maybe_add_csrf_header(client.csrf_token)

      url =
        operation.path
        |> URI.parse()
        |> maybe_add_base_url(client.endpoint)

      request_options =
        client_config
        |> Keyword.merge(
          method: operation.http_method,
          headers: headers,
          url: url,
          params: operation.params
        )
        |> Keyword.merge(override_options)
        # Drop all options not relevant for the HTTP Adapter
        |> Keyword.delete(:transform)

      with {:ok, response} <- HTTP.request(http_impl, request_options) do
        transformer = maybe_override_transformer(override_options, operation.transformer)

        maybe_invoke_session_callback(client, response)
        normalize_result(transformer.(response))
      end
    end

    @spec stream!(Query.t(), DSpace.API.t(), keyword()) :: Enumerable.t()
    def stream!(%Query{stream_impl: nil}, _client, _options) do
      raise ArgumentError, "this operation cannot be streamed"
    end

    def stream!(%Query{stream_impl: stream_impl}, client, options) do
      stream_impl.(client, options)
    end
  end
end
