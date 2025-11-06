defmodule DSpace.API.Operation.Helpers do
  @moduledoc false

  import DSpace.API.Utils, only: [is_nonempty_binary: 1]

  alias DSpace.API
  alias DSpace.API.HTTP.Response
  alias DSpace.API.Operation

  # API for internal use

  @doc """
  Drops operation options not relevant for the HTTP Adapter
  """
  @spec drop_extra_options(keyword()) :: keyword()
  def drop_extra_options(options) do
    Keyword.delete(options, :transform)
  end

  def maybe_add_auth_header(headers, access_token) when is_nonempty_binary(access_token) do
    Map.put(headers, "authorization", ["Bearer " <> access_token])
  end

  def maybe_add_auth_header(headers, nil), do: headers

  def maybe_add_csrf_header(headers, csrf_token) when is_nonempty_binary(csrf_token) do
    Map.put(headers, "x-xsrf-token", [csrf_token])
  end

  def maybe_add_csrf_header(headers, nil), do: headers

  @spec maybe_add_base_url(URI.t() | binary(), URI.t() | binary() | (-> term())) :: URI.t()
  def maybe_add_base_url(request_url_or_path, base_url) when is_binary(request_url_or_path) do
    maybe_add_base_url(URI.parse(request_url_or_path), base_url)
  end

  def maybe_add_base_url(request_url_or_path, base_url) when is_struct(base_url, URI) do
    maybe_add_base_url(request_url_or_path, URI.to_string(base_url))
  end

  def maybe_add_base_url(request_url_or_path, base_url) when is_function(base_url, 0) do
    maybe_add_base_url(request_url_or_path, base_url.())
  end

  def maybe_add_base_url(request_url_or_path, base_url)
      when is_struct(request_url_or_path, URI) and is_binary(base_url) do
    if request_url_or_path.host do
      request_url_or_path
    else
      URI.new!(base_url <> URI.to_string(request_url_or_path))
    end
  end

  @spec maybe_apply_version_overrides(Operation.t(), API.t()) :: Operation.t()
  def maybe_apply_version_overrides(%{version_overrides: []} = operation, _client), do: operation

  def maybe_apply_version_overrides(%{version_overrides: overrides} = operation, client) do
    %API{api_version: version} = client

    updated_operation =
      Enum.reduce(overrides, operation, fn {version_spec, changes}, acc ->
        if version_matches?(version, version_spec) do
          struct(acc, changes)
        else
          acc
        end
      end)

    updated_operation
  end

  @spec maybe_invoke_callback(Operation.t(), API.t(), keyword()) ::
          {Operation.t(), API.t(), keyword()}
  def maybe_invoke_callback(%{before_step: nil} = operation, client, options) do
    {operation, client, options}
  end

  def maybe_invoke_callback(%{before_step: callback} = operation, client, options) do
    callback.(operation, client, options)
  end

  @spec maybe_invoke_session_callback(API.t(), Response.t()) :: :ok
  def maybe_invoke_session_callback(%API{session_callback: nil}, _response), do: :ok

  def maybe_invoke_session_callback(%API{session_callback: callback}, response) when is_function(callback, 1) do
    %Response{headers: headers} = response

    case extract_csrf(headers) do
      {:ok, token} ->
        callback.(%{csrf_token: token})
        :ok

      _ ->
        :ok
    end
  rescue
    _ -> :ok
  end

  @spec maybe_override_transformer(keyword(), (term() -> term())) :: (term() -> term())
  def maybe_override_transformer(options, transformer) when is_function(transformer, 1) do
    if Keyword.get(options, :transform, true) do
      transformer
    else
      &Function.identity/1
    end
  end

  @spec normalize_result(term()) :: {:ok, term()} | {:error, term()}
  def normalize_result({:ok, _} = result), do: result
  def normalize_result({:error, _} = error), do: error
  def normalize_result(error) when is_exception(error), do: {:error, error}
  def normalize_result(result), do: {:ok, result}

  # Private helpers

  defp extract_csrf(%{"dspace-xsrf-token" => [token | _]}) when is_nonempty_binary(token) do
    {:ok, token}
  end

  defp extract_csrf(_response), do: :error

  defp version_matches?(version, spec) do
    case Version.parse_requirement(spec) do
      {:ok, requirement} -> Version.match?(version, requirement)
      :error -> false
    end
  end
end
