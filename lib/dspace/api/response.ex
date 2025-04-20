defmodule DSpace.Api.Response do
  @moduledoc """
  Provides utilities for handling API responses.
  """

  alias DSpace.Api.Error
  alias DSpace.Api.Response.Page

  @typedoc """
  Response containing body data, HTTP headers and trailers, and status code.
  """
  @type t :: %{
          status: non_neg_integer(),
          headers: %{optional(binary()) => [binary()]},
          body: map() | nil,
          trailers: %{optional(binary()) => [binary()]} | nil
        }

  @doc """
  Extracts API resources from a response body using a path.

  For collection endpoints, pass a list of keys to navigate to the resources. For single-item endpoints, pass `nil` as the path.
  """
  @spec extract_resources(map(), list() | nil) :: list()
  def extract_resources(body, path \\ nil)

  def extract_resources(body, nil), do: [body]

  def extract_resources(body, path) when is_list(path) do
    get_in(body, path) || []
  end

  @doc """
  Extracts API resources from a search result response.
  """
  @spec extract_search_results(response :: map()) :: list()
  def extract_search_results(response) do
    extract_resources(response, ["_embedded", "searchResult", "_embedded", "objects"])
  end

  @doc """
  Extracts pagination information from a response.
  """
  @spec pagination(response :: map()) :: DSpace.Api.Response.Page.t() | nil
  def pagination(%{body: body}) do
    Page.from_response(body)
  end

  def pagination(_), do: nil

  @doc """
  Processes a single resource using the provided transformer function.
  """
  @spec transform_resource(map(), (map() -> struct())) :: struct()
  def transform_resource(resource, transformer) when is_function(transformer, 1) do
    transformer.(resource)
  end

  @doc """
  Processes a collection of resources using the provided transformer function.
  """
  @spec transform_collection(list(), (map() -> struct())) :: list(struct())
  def transform_collection(resources, transformer) when is_function(transformer, 1) do
    Enum.map(resources, transformer)
  end

  @doc """
  Normalizes API responses.

  Errors are normalized using `DSpace.Api.Error`.
  """
  @spec normalize({:ok, map()} | {:error, term()}) ::
          {:ok, map()} | {:error, DSpace.Api.Error.t() | Exception.t()}
  def normalize({:ok, %{status: status} = response}) when status >= 400 do
    {:error, Error.from_response(response)}
  end

  # Req, Finch, Mint-style timeout
  def normalize({:error, %{reason: :timeout} = _exception}) do
    {:error, Error.timeout_error()}
  end

  # Hackney-style timeout
  def normalize({:error, :connect_timeout}) do
    {:error, Error.timeout_error()}
  end

  # Other transport, protocol, argument etc. errors bubble up
  def normalize({:error, %{reason: reason} = _exception}) do
    {:error, Error.connection_error(reason)}
  end

  def normalize(response), do: response
end
