defmodule DSpace.API.Operation.JSON do
  @moduledoc """
  Represents a JSON operation against the DSpace API.

  This module is usually not used directly. Operation data structures are constructed by API
  operation modules. Building your own operations is useful in cases where dspace_ex doesn't
  support a specific API functionality yet.

  The `before_step` field allows to specify a function to be called at execution time. It takes
  the operation, the client configuration and override options and allows to modify them before
  the HTTP request is made or produce other side effects based on their data.
  """

  defstruct http_method: :get,
            path: "/",
            csrf: :auto,
            transformer: &DSpace.API.Transform.from_response/1,
            expected_status: nil,
            data: nil,
            content_type: :json,
            params: [],
            headers: %{},
            version_overrides: [],
            before_step: nil,
            stream_impl: nil

  @type t :: %__MODULE__{
          http_method: :get | :head | :post | :put | :patch | :delete,
          path: binary(),
          csrf: :auto | :required | :optional | :skip,
          transformer: function(),
          expected_status: [non_neg_integer()] | nil,
          data: map() | list() | binary() | nil,
          content_type: :json | :form | :multipart | :uri_list,
          params: keyword(),
          headers: %{optional(binary()) => [binary()]},
          version_overrides: [{binary(), keyword()}],
          before_step: function() | nil,
          stream_impl: function() | nil
        }

  # Public API

  @doc """
  Creates a new JSON operation from the given options.
  """
  @spec new(keyword()) :: t()
  def new(options) do
    struct(__MODULE__, options)
  end
end

defimpl DSpace.API.Operation, for: DSpace.API.Operation.JSON do
  import DSpace.Utils, only: [is_nonempty_binary: 1, maybe_add_base_url: 2, wrap: 1]

  alias DSpace.API
  alias DSpace.API.HTTP
  alias DSpace.API.HTTP.Response
  alias DSpace.API.Operation.JSON, as: OpJSON

  # Options which don't need to be passed to the HTTP adapter
  @extra_options [:transform, :base_url]

  @spec perform(OpJSON.t(), API.t(), keyword()) :: {:ok, term()} | {:error, Exception.t()}
  def perform(operation, client, opts_override) do
    {operation, client, opts_override} = maybe_invoke_callback(operation, client, opts_override)

    operation = maybe_apply_version_overrides(operation, client)
    {content_header, body_option} = build_content_options(operation)
    csrf_policy = resolve_csrf(operation.csrf, operation.http_method)
    {http_impl, client_config} = client.http_impl

    headers =
      %{
        :accept => ["application/json"],
        :user_agent => [client.user_agent]
      }
      |> Map.merge(content_header)
      |> Map.merge(operation.headers)
      |> maybe_add_csrf_header(csrf_policy, client.csrf_token)
      |> maybe_add_csrf_cookie(csrf_policy, client.csrf_token)
      |> maybe_add_auth_header(client.access_token)

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
        params: operation.params,
        expected_status: resolve_expected_status(operation)
      )
      |> Keyword.merge(body_option)
      |> Keyword.merge(opts_override)
      |> Keyword.drop(@extra_options)

    with {:ok, response} <- HTTP.request(http_impl, request_options),
         :ok <- maybe_invoke_on_response_hook(client, response) do
      transformer = maybe_override_transformer(opts_override, operation.transformer)

      response
      |> apply_transform(transformer)
      |> wrap()
    end
  end

  @spec stream!(OpJSON.t(), API.t(), keyword()) :: Enumerable.t()
  def stream!(%OpJSON{stream_impl: nil}, _client, _options) do
    raise ArgumentError, "this operation cannot be streamed"
  end

  def stream!(%OpJSON{stream_impl: stream_impl}, client, options) do
    stream_impl.(client, options)
  end

  # Private helpers

  defp maybe_invoke_callback(%{before_step: nil} = operation, client, options) do
    {operation, client, options}
  end

  defp maybe_invoke_callback(%{before_step: callback} = operation, client, options) when is_function(callback, 3) do
    callback.(operation, client, options)
  end

  defp maybe_apply_version_overrides(%{version_overrides: []} = operation, _client), do: operation

  defp maybe_apply_version_overrides(%{version_overrides: overrides} = operation, client) do
    %API{api_version: version} = client

    Enum.reduce(overrides, operation, fn {version_spec, changes}, acc ->
      if version_matches?(version, version_spec) do
        struct(acc, changes)
      else
        acc
      end
    end)
  end

  defp version_matches?(version, spec) when is_binary(version) and is_binary(spec) do
    case Version.parse_requirement(spec) do
      {:ok, requirement} -> Version.match?(version, requirement)
      :error -> false
    end
  end

  defp version_matches?(_version, _spec), do: false

  defp build_content_options(%{data: nil}), do: {%{}, []}

  defp build_content_options(%{content_type: :uri_list, data: data}) when is_binary(data) do
    build_content_options(%{content_type: :uri_list, data: [data]})
  end

  defp build_content_options(%{content_type: :uri_list, data: data}) when is_list(data) do
    {%{:content_type => ["text/uri-list"]}, [body: Enum.join(data, "\n")]}
  end

  defp build_content_options(%{content_type: :json, data: data}) do
    {%{:content_type => ["application/json"]}, [json: data]}
  end

  defp build_content_options(%{content_type: :form, data: data}) do
    {%{:content_type => ["application/x-www-form-urlencoded"]}, [form: data]}
  end

  defp build_content_options(%{content_type: :multipart, data: data}) do
    {%{:content_type => ["multipart/form-data"]}, [form_multipart: data]}
  end

  defp resolve_csrf(:auto, method) when method in [:post, :put, :patch, :delete], do: :required
  defp resolve_csrf(:auto, _method), do: :optional
  defp resolve_csrf(explicit, _method), do: explicit

  defp maybe_add_csrf_header(headers, :skip, _csrf_token), do: headers

  defp maybe_add_csrf_header(headers, :required, csrf_token) when is_nonempty_binary(csrf_token) do
    Map.put(headers, :x_xsrf_token, [csrf_token])
  end

  defp maybe_add_csrf_header(_headers, :required, _csrf_token) do
    raise ArgumentError, "executing this operation requires a CSRF token"
  end

  defp maybe_add_csrf_header(headers, :optional, csrf_token) when is_nonempty_binary(csrf_token) do
    Map.put(headers, :x_xsrf_token, [csrf_token])
  end

  defp maybe_add_csrf_header(headers, :optional, _csrf_token), do: headers

  defp maybe_add_csrf_cookie(headers, :skip, _csrf_token), do: headers

  # Policy is enforced by maybe_add_csrf_header/3 called before in the chain.
  defp maybe_add_csrf_cookie(headers, _policy, csrf_token) when is_nonempty_binary(csrf_token) do
    csrf_cookie = "DSPACE-XSRF-COOKIE=" <> csrf_token

    if xsrf_cookie_header_set?(headers) do
      headers
    else
      Map.update(headers, :cookie, [csrf_cookie], &[csrf_cookie | &1])
    end
  end

  defp maybe_add_csrf_cookie(headers, _policy, _csrf_token), do: headers

  defp xsrf_cookie_header_set?(headers) do
    headers
    |> Map.get(:cookie, [])
    |> Enum.flat_map(&String.split(&1, ";"))
    |> Enum.map(&String.trim/1)
    |> Enum.any?(&String.starts_with?(&1, "DSPACE-XSRF-COOKIE="))
  end

  defp maybe_add_auth_header(headers, access_token) when is_nonempty_binary(access_token) do
    Map.put(headers, :authorization, ["Bearer " <> access_token])
  end

  defp maybe_add_auth_header(headers, nil), do: headers

  defp resolve_expected_status(%{expected_status: status}) when is_list(status), do: status
  defp resolve_expected_status(%{http_method: :post}), do: [200, 201]
  defp resolve_expected_status(%{http_method: :delete}), do: [200, 204]
  defp resolve_expected_status(_operation), do: [200]

  defp maybe_invoke_on_response_hook(%API{on_response_hook: nil}, _response) do
    :ok
  end

  defp maybe_invoke_on_response_hook(%API{on_response_hook: hook}, response) when is_function(hook, 1) do
    %Response{headers: headers} = response

    case extract_csrf(headers) do
      {:ok, token} ->
        hook.(%{csrf_token: token})

        :ok

      _no_token ->
        :ok
    end
  end

  defp extract_csrf(%{"dspace-xsrf-token" => [token | _]}) when is_nonempty_binary(token) do
    {:ok, token}
  end

  defp extract_csrf(_headers), do: :error

  defp maybe_override_transformer(options, transform_fn) do
    case Keyword.get(options, :transform, true) do
      true -> transform_fn
      false -> &Function.identity/1
      custom when is_function(custom, 1) -> custom
    end
  end

  defp apply_transform(response, transform_fn) when is_function(transform_fn, 1) do
    transform_fn.(response)
  end
end
