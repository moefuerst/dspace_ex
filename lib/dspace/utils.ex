defmodule DSpace.Utils do
  @moduledoc false

  # Guards

  @doc guard: true
  @doc """
  Checks if the term is a binary with a non-zero byte size, and returns `true` if so.
  """
  defguard is_nonempty_binary(term) when is_binary(term) and byte_size(term) > 0

  # Functions

  @doc """
  If the given path is not a full URL already, adds the given base URL to it.
  """
  @spec maybe_add_base_url(url_or_path, base_url) :: URI.t()
        when url_or_path: URI.t() | binary(), base_url: URI.t() | binary() | (-> term())
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

  @doc """
  Pops API pagination options out of a keyword list.

  Pulls pagination options from the given list and returns a tuple
  `{pagination_params, other_options}`, where `pagination_params` is a keyword list of normalized
  pagination params ready to be concatenated into an operation's query params.
  """
  @spec pop_pagination(keyword()) :: {keyword(), keyword()}
  def pop_pagination(options) when is_list(options) do
    {pagination, other_options} = Keyword.split(options, [:page, :size, :sort])

    {Enum.map(pagination, &normalize_pagination_param/1), other_options}
  end

  @doc """
  Wraps the given term in a result tuple.

    * If the term is already a result tuple, it is returned as-is
    * If the term is an exception, it is wrapped in an `{:error, exception}` tuple
    * Otherwise, the term is wrapped in an `{:ok, value}` tuple
  """
  @spec wrap({:ok, value} | {:error, reason} | value | exception) :: {:ok, value} | {:error, reason}
        when value: term(), reason: term(), exception: Exception.t()
  def wrap({:ok, value}), do: {:ok, value}
  def wrap({:error, reason}), do: {:error, reason}
  def wrap(error) when is_exception(error), do: {:error, error}
  def wrap(value), do: {:ok, value}

  # Private helpers

  defp normalize_pagination_param({:page, page}) when is_integer(page) and page >= 0 do
    {:page, page}
  end

  defp normalize_pagination_param({:size, size}) when is_integer(size) and size > 0 do
    {:size, size}
  end

  defp normalize_pagination_param({:sort, {field, direction}})
       when (is_nonempty_binary(field) or is_atom(field)) and direction in [:asc, :desc] do
    {:sort, to_string(field) <> "," <> Atom.to_string(direction)}
  end

  defp normalize_pagination_param({:sort, {field, direction}})
       when (is_nonempty_binary(field) or is_atom(field)) and direction in ["asc", "desc"] do
    {:sort, to_string(field) <> "," <> direction}
  end

  defp normalize_pagination_param({:sort, field}) when is_nonempty_binary(field) or is_atom(field) do
    {:sort, to_string(field) <> ",asc"}
  end
end
