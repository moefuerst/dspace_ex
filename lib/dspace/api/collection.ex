defmodule DSpace.API.Collection do
  @moduledoc """
  Functions for working with DSpace Collections.

  Collections are containers for Items in the DSpace hierarchy.
  """

  @behaviour DSpace.API.Resource

  import DSpace.Utils, only: [is_nonempty_binary: 1, pop_pagination: 1]

  alias DSpace.API.Operation
  alias DSpace.API.Resource
  alias DSpace.API.Search
  alias DSpace.API.StreamBuilder
  alias DSpace.API.Transform

  @ep_core "/api/core/collections"

  # Public API

  @doc """
  Fetches the parent community of a collection.
  """
  @spec fetch_parent_community(binary()) :: Operation.t()
  def fetch_parent_community(uuid) when is_nonempty_binary(uuid) do
    %Operation.JSON{path: @ep_core <> "/" <> uuid <> "/parentCommunity"}
  end

  @doc """
  Lists items that belong to the collection.

  This operation can be streamed.

  ## Options

    * `:page` - Page number (0-based, defaults to 0)
    * `:size` - Number of items per page (usually defaults to 20)
  """
  @spec list_items(binary(), keyword()) :: Operation.t()
  def list_items(uuid, options \\ []) when is_nonempty_binary(uuid) do
    {pagination, other_options} = pop_pagination(options)

    op = %Operation.JSON{
      path: @ep_core <> "/" <> uuid <> "/mappedItems",
      params: pagination ++ other_options,
      transformer:
        &Transform.transform_collection(&1,
          extract: ["_embedded", "items"]
        )
    }

    %{op | stream_impl: &StreamBuilder.new(&1, op, &2)}
  end

  @doc """
  Fetches the default access conditions for a collection.
  """
  @spec fetch_default_access_conditions(binary()) :: Operation.t()
  def fetch_default_access_conditions(uuid) when is_nonempty_binary(uuid) do
    %Operation.JSON{path: @ep_core <> "/" <> uuid <> "/defaultAccessConditions"}
  end

  # Callbacks

  @doc """
  Fetches a single collection by UUID.
  """
  @impl Resource
  @spec fetch(binary(), keyword()) :: Operation.t()
  def fetch(uuid, _options \\ []) when is_nonempty_binary(uuid) do
    %Operation.JSON{path: @ep_core <> "/" <> uuid}
  end

  @doc """
  Finds collections using Discovery search.

  This operation can be streamed.

  ## Parameters

    * `options` - Search options, see `DSpace.API.Search.query/1` for details

  ## Examples

      # Find all collections
      iex> Collection.find([])
      %DSpace.API.Operation.JSON{path: "/api/discover/search/objects", ...}

      # Find all collections with filters
      iex> Collection.find(filters: [%{filter: "title", operator: "contains", value: "special"}])
      %DSpace.API.Operation.JSON{...}

      # Simple collection search with text query
      iex> Collection.find(query: "digital archives")
      %DSpace.API.Operation.JSON{path: "/api/discover/search/objects", ...}

      # Search with additional filters
      iex> Collection.find(query: "library", filters: [%{filter: "title", operator: "contains", value: "special"}])
      %DSpace.API.Operation.JSON{...}

      # Search within a specific community
      iex> Collection.find(query: "research", scope: "community-uuid")
      %DSpace.API.Operation.JSON{...}
  """
  @impl Resource
  @spec find(keyword()) :: Operation.t()
  def find(options \\ []) when is_list(options) do
    search_options =
      options
      |> Keyword.put(:dsoType, "Collection")
      # The CRIS fork disables communities and collections in the default configuration
      |> Keyword.put(:configuration, "communityOrCollection")

    Search.query(search_options)
  end

  @doc """
  Lists all collections from the repository.

  This operation can be streamed.

  ## Options

    * `:page` - Page number (0-based, defaults to 0)
    * `:size` - Number of items per page (usually defaults to 20)
  """
  @impl Resource
  @spec list(keyword()) :: Operation.t()
  def list(options \\ []) do
    {pagination, other_options} = pop_pagination(options)

    op = %Operation.JSON{
      path: @ep_core,
      params: pagination ++ other_options,
      transformer:
        &Transform.transform_collection(&1,
          extract: ["_embedded", "collections"]
        )
    }

    %{op | stream_impl: &StreamBuilder.new(&1, op, &2)}
  end

  @doc """
  Creates a new collection.

  Collections *must* have a parent (a community or another collection).

  ## Options

    * `:parent` - UUID of the parent community or collection
  """
  @impl Resource
  @spec create(map(), keyword()) :: Operation.t()
  def create(collection, options \\ []) when is_map(collection) do
    params = add_parent([], options[:parent])

    %Operation.JSON{
      path: @ep_core,
      http_method: :post,
      params: params,
      data: collection
    }
  end

  @doc """
  Updates an existing collection.
  """
  @impl Resource
  @spec update(binary(), list(), keyword()) :: Operation.t()
  def update(uuid, updates, _options \\ []) when is_nonempty_binary(uuid) and is_list(updates) do
    %Operation.JSON{
      path: @ep_core <> "/" <> uuid,
      http_method: :patch,
      data: updates
    }
  end

  @doc """
  Replaces an existing collection.
  """
  @impl Resource
  @spec replace(binary(), map(), keyword()) :: Operation.t()
  def replace(uuid, collection, _options \\ []) when is_nonempty_binary(uuid) and is_map(collection) do
    %Operation.JSON{
      path: @ep_core <> "/" <> uuid,
      http_method: :put,
      data: collection
    }
  end

  @doc """
  Deletes a collection.
  """
  @impl Resource
  @spec delete(binary(), keyword()) :: Operation.t()
  def delete(uuid, _options \\ []) when is_nonempty_binary(uuid) do
    %Operation.JSON{
      path: @ep_core <> "/" <> uuid,
      http_method: :delete,
      transformer: fn _ -> :ok end
    }
  end

  # Private helpers

  defp add_parent(params, parent_uuid) when is_nonempty_binary(parent_uuid) do
    Keyword.put(params, :parent, parent_uuid)
  end
end
