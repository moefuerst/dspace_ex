defmodule DSpace.API.Community do
  @moduledoc """
  Functions for working with DSpace Communities.

  Communities are top-level organizational units containing Collections of Items.
  """

  @behaviour DSpace.API.Resource

  import DSpace.Utils, only: [is_nonempty_binary: 1, pop_pagination: 1]

  alias DSpace.API.Operation
  alias DSpace.API.Resource
  alias DSpace.API.Search
  alias DSpace.API.StreamBuilder
  alias DSpace.API.Transform

  @ep_core "/api/core/communities"
  @ep_core_toplevel @ep_core <> "/search/top"

  # Public API

  @doc """
  Lists collections within a community.

  This operation can be streamed.

  ## Options

    * `:page` - Page number (0-based, defaults to 0)
    * `:size` - Number of items per page (usually defaults to 20)
  """
  @spec list_collections(binary(), keyword()) :: Operation.t()
  def list_collections(uuid, options \\ []) when is_nonempty_binary(uuid) do
    {pagination, other_options} = pop_pagination(options)

    op = %Operation.JSON{
      path: @ep_core <> "/" <> uuid <> "/collections",
      params: pagination ++ other_options,
      transformer:
        &Transform.transform_collection(&1,
          extract: ["_embedded", "collections"]
        )
    }

    %{op | stream_impl: &StreamBuilder.new(&1, op, &2)}
  end

  @doc """
  Lists subcommunities within a community.

  This operation can be streamed.

  ## Options

    * `:page` - Page number (0-based, defaults to 0)
    * `:size` - Number of items per page (usually defaults to 20)
  """
  @spec list_subcommunities(binary(), keyword()) :: Operation.t()
  def list_subcommunities(uuid, options \\ []) when is_nonempty_binary(uuid) do
    {pagination, other_options} = pop_pagination(options)

    op = %Operation.JSON{
      path: @ep_core <> "/" <> uuid <> "/subcommunities",
      params: pagination ++ other_options,
      transformer:
        &Transform.transform_collection(&1,
          extract: ["_embedded", "subcommunities"]
        )
    }

    %{op | stream_impl: &StreamBuilder.new(&1, op, &2)}
  end

  @doc """
  Fetches the parent community of a community.
  """
  @spec fetch_parent(binary()) :: Operation.t()
  def fetch_parent(uuid) when is_nonempty_binary(uuid) do
    %Operation.JSON{
      path: @ep_core <> "/" <> uuid <> "/parentCommunity",
      expected_status: [200, 204]
    }
  end

  @doc """
  Lists top-level communities (communities without a parent).

  This operation can be streamed.

  ## Options

    * `:page` - Page number (0-based, defaults to 0)
    * `:size` - Number of items per page (usually defaults to 20)
  """
  @spec list_toplevel(keyword()) :: Operation.t()
  def list_toplevel(options \\ []) do
    {pagination, other_options} = pop_pagination(options)

    op = %Operation.JSON{
      path: @ep_core_toplevel,
      params: pagination ++ other_options,
      transformer:
        &Transform.transform_collection(&1,
          extract: ["_embedded", "communities"]
        )
    }

    %{op | stream_impl: &StreamBuilder.new(&1, op, &2)}
  end

  # Callbacks

  @doc """
  Fetches a single community by UUID.
  """
  @impl Resource
  @spec fetch(binary(), keyword()) :: Operation.t()
  def fetch(uuid, _options \\ []) when is_nonempty_binary(uuid) do
    %Operation.JSON{path: @ep_core <> "/" <> uuid}
  end

  @doc """
  Finds communities using Discovery search.

  This operation can be streamed.

  ## Parameters

    * `options` - Search options, see `DSpace.API.Search.query/1` for details

  ## Examples

      # Find all communities
      iex> Community.find([])
      %DSpace.API.Operation.JSON{path: "/api/discover/search/objects", ...}

      # Find all communities with filters
      iex> Community.find(filters: [%{filter: "subject", operator: "contains", value: "science"}])
      %DSpace.API.Operation.JSON{...}

      # Simple community search with text query
      iex> Community.find(query: "research community")
      %DSpace.API.Operation.JSON{...}

      # Search with additional filters
      iex> Community.find(query: "library", filters: [%{filter: "subject", operator: "contains", value: "science"}])
      %DSpace.API.Operation.JSON{...}

      # Search within a specific parent community
      iex> Community.find(query: "academic", scope: "parent-community-uuid")
      %DSpace.API.Operation.JSON{...}
  """
  @impl Resource
  @spec find(keyword()) :: Operation.t()
  def find(options \\ []) when is_list(options) do
    search_options =
      options
      |> Keyword.put(:dsoType, "Community")
      # The CRIS fork disables communities and collections in the default configuration
      |> Keyword.put(:configuration, "communityOrCollection")

    Search.query(search_options)
  end

  @doc """
  Lists all communities from the repository.

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
          extract: ["_embedded", "communities"]
        )
    }

    %{op | stream_impl: &StreamBuilder.new(&1, op, &2)}
  end

  @doc """
  Creates a new community.

  Communities can be top-level or subcommunities with a parent.

  ## Options

    * `:parent` - UUID of the parent community
  """
  @impl Resource
  @spec create(map(), keyword()) :: Operation.t()
  def create(community, options \\ []) when is_map(community) do
    params = maybe_add_parent([], options[:parent])

    %Operation.JSON{
      path: @ep_core,
      http_method: :post,
      params: params,
      data: community
    }
  end

  @doc """
  Updates an existing community.
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
  Replaces an existing community.
  """
  @impl Resource
  @spec replace(binary(), map(), keyword()) :: Operation.t()
  def replace(uuid, community, _options \\ []) when is_nonempty_binary(uuid) and is_map(community) do
    %Operation.JSON{
      path: @ep_core <> "/" <> uuid,
      http_method: :put,
      data: community
    }
  end

  @doc """
  Deletes a community.
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

  defp maybe_add_parent(params, nil), do: params

  defp maybe_add_parent(params, parent_uuid) when is_nonempty_binary(parent_uuid) do
    [{:parent, parent_uuid} | params]
  end
end
