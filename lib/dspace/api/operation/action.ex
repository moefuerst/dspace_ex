defmodule DSpace.API.Operation.Action do
  @moduledoc """
  Represents an operations that performs an action with a payload.
  """

  defstruct http_method: :post,
            path: "/",
            transformer: &DSpace.API.Transform.from_response/1,
            data: nil,
            type: :json,
            params: [],
            headers: %{},
            version_overrides: [],
            before_step: nil,
            stream_impl: nil

  @type t :: %__MODULE__{
          http_method: :post | :put | :patch | :delete,
          path: binary(),
          transformer: function(),
          data: map() | list() | binary() | nil,
          type: :json | :form | :multipart | :uri_list,
          params: keyword(),
          headers: %{optional(binary()) => [binary()]},
          version_overrides: [{binary(), keyword()}],
          before_step: function() | nil,
          stream_impl: function() | nil
        }

  def new(options) do
    struct(%__MODULE__{}, options)
  end
end

defimpl DSpace.API.Operation, for: DSpace.API.Operation.Action do
  import DSpace.API.Operation.Helpers
  import DSpace.API.Utils, only: [is_nonempty_binary: 1]

  alias DSpace.API.HTTP
  alias DSpace.API.Operation.Action

  @spec perform(Action.t(), DSpace.API.t(), keyword()) :: {:ok, term()} | {:error, Exception.t()}
  def perform(operation, client, override_options) do
    {operation, client, override_options} =
      maybe_invoke_callback(operation, client, override_options)

    operation = maybe_apply_version_overrides(operation, client)
    {http_impl, client_config} = client.http_impl
    {content_header, body_option} = build_content_options(operation)

    headers =
      %{
        :accept => ["application/json"],
        :user_agent => [client.user_agent]
      }
      |> Map.merge(content_header)
      |> Map.merge(operation.headers)
      |> maybe_add_auth_header(client.access_token)
      |> add_csrf_header(client.csrf_token)

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
      |> Keyword.merge(body_option)
      |> Keyword.merge(override_options)
      |> drop_extra_options()

    with {:ok, response} <- HTTP.request(http_impl, request_options) do
      transformer = maybe_override_transformer(override_options, operation.transformer)

      maybe_invoke_session_callback(client, response)
      normalize_result(transformer.(response))
    end
  end

  @spec stream!(Action.t(), DSpace.API.t(), keyword()) :: Enumerable.t()
  def stream!(%Action{stream_impl: nil}, _client, _options) do
    raise ArgumentError, "this operation cannot be streamed"
  end

  def stream!(%Action{stream_impl: stream_impl}, client, options) do
    stream_impl.(client, options)
  end

  # Private helpers

  def add_csrf_header(headers, csrf_token) when is_nonempty_binary(csrf_token) do
    Map.put(headers, "x-xsrf-token", [csrf_token])
  end

  def add_csrf_header(_headers, nil) do
    raise ArgumentError, "executing actions requires a CSRF token"
  end

  defp build_content_options(%{type: :uri_list, data: data}) when is_list(data) do
    {%{:content_type => ["text/uri-list"]}, [body: Enum.join(data, "\n")]}
  end

  # Adapter-supported content types per DSpace.API.HTTP contract
  defp build_content_options(%{type: :json, data: data}), do: {%{}, [json: data]}
  defp build_content_options(%{type: :form, data: data}), do: {%{}, [form: data]}
  defp build_content_options(%{type: :multipart, data: data}), do: {%{}, [form_multipart: data]}
end
