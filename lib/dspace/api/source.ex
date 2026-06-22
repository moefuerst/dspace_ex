defmodule DSpace.API.Source do
  @moduledoc """
  Operations for working with external authority sources.
  """

  import DSpace.Utils, only: [is_nonempty_binary: 1, pop_pagination: 1]

  alias DSpace.API.Operation
  alias DSpace.API.StreamBuilder
  alias DSpace.API.Transform

  @ep_externalsource "/api/integration/externalsources"

  # Public API

  @doc """
  Fetches the configuration for the given external authority source.
  """
  @spec config(binary(), keyword()) :: Operation.JSON.t()
  def config(name, _options) when is_nonempty_binary(name) do
    %Operation.JSON{path: @ep_externalsource <> "/" <> name}
  end

  @doc """
  Lists all configured external authority sources.

  This operation can be streamed.

  ## Options

    * `:page` - Page number (0-based, defaults to 0)
    * `:size` - Number of items per page (usually defaults to 20)
  """
  @spec list(keyword()) :: Operation.JSON.t()
  def list(options \\ []) do
    {pagination, _other_options} = pop_pagination(options)

    op = %Operation.JSON{
      path: @ep_externalsource,
      params: pagination,
      transformer: &Transform.transform_collection(&1, extract: ["_embedded", "externalsources"])
    }

    %{op | stream_impl: &StreamBuilder.new(&1, op, &2)}
  end

  @doc """
  Searches an external authority source for entries matching the given query.

  This operation can be streamed.

  ## Options

    * `:source` - The external source name as an atom or string (required)
    * `:page` - Page number (0-based, defaults to 0)
    * `:size` - Number of items per page (usually defaults to 20)
  """
  @spec find_entries(binary(), keyword()) :: Operation.JSON.t()
  def find_entries(query, options \\ []) when is_nonempty_binary(query) do
    {pagination, other_options} = pop_pagination(options)

    source =
      other_options
      |> Keyword.validate!([:source])
      |> Keyword.get(:source)
      |> to_string()

    params = [query: query] ++ pagination

    op = %Operation.JSON{
      path: @ep_externalsource <> "/" <> source <> "/entries",
      params: params,
      transformer:
        &Transform.transform_collection(&1,
          extract: ["_embedded", "externalSourceEntries"]
        )
    }

    %{op | stream_impl: &StreamBuilder.new(&1, op, &2)}
  end

  @doc """
  Fetches an entry from an external source by ID.

  ## Options

    * `:source` - The external source name as an atom or string (required)
  """
  @spec fetch(binary(), keyword()) :: Operation.JSON.t()
  def fetch(id, options) when is_nonempty_binary(id) and is_list(options) do
    source =
      options
      |> Keyword.validate!([:source])
      |> Keyword.get(:source)
      |> to_string()

    %Operation.JSON{path: @ep_externalsource <> "/" <> source <> "/entryValues/" <> id}
  end
end
