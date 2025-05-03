defmodule DSpace.Api.Collection do
  @moduledoc """
  Represents a DSpace Collection, which is a container for items.
  Collections are owned by Communities and organize repository content.
  """

  import DSpace.Utils.Guards

  alias DSpace.Api
  alias DSpace.Api.Error
  alias DSpace.Api.Metadata
  alias DSpace.Api.Object
  alias DSpace.Api.Response

  @ep_url "/api/core/collections"
  @ep_community_url "/api/core/communities"

  defstruct [
    :dspace_object,
    :archived_items_count,
    :metadata
  ]

  @typedoc """
  A DSpace Collection struct.

  ## Fields:
  * `dspace_object`: `t:DSpace.Api.Object.t/0` with common attributes like UUID, name and modification date
  * `archived_items_count`: Number of archived items in this collection (-1 if not calculated)
  * `metadata`: `t:DSpace.Api.Metadata.t/0` map where keys are metadata field names and values are lists of metadata value and props
  """
  @type t :: %__MODULE__{
          dspace_object: Object.t(),
          archived_items_count: integer(),
          metadata: Metadata.t()
        }

  # Public API

  @doc """
  Fetches a single collection by UUID.
  """
  @spec fetch(Api.t(), binary()) ::
          {:ok, t()} | {:error, Error.t() | Exception.t()}
  def fetch(%Api{} = client, uuid) when is_not_empty(uuid) do
    case Api.request(client, url: "#{@ep_url}/#{uuid}") do
      {:ok, response} -> {:ok, from_response(response.body)}
      {:error, _} = error -> error
    end
  end

  @doc """
  Fetches all collections.
  """
  @spec fetch_all(Api.t()) ::
          {:ok, [t()]} | {:error, Api.Error.t() | Exception.t()}
  def fetch_all(%Api{} = client) do
    client
    |> Api.stream(
      [url: @ep_url],
      &Response.extract_resources(&1, ["_embedded", "collections"]),
      &from_response/1
    )
    |> then(&{:ok, Enum.to_list(&1)})
  end

  @doc """
  Fetches collections that match a specific entity type.
  """
  @spec fetch_with_entity_type(Api.t(), binary()) ::
          {:ok, [t()]} | {:error, Error.t() | Exception.t()}
  def fetch_with_entity_type(%Api{} = client, entity_type) when is_not_empty(entity_type) do
    client
    |> Api.stream(
      [url: @ep_url, params: [entityType: entity_type]],
      &Response.extract_resources(&1, ["_embedded", "collections"]),
      &from_response/1
    )
    |> then(&{:ok, Enum.to_list(&1)})
  end

  @doc """
  Fetches all collections for a specific community.
  """
  @spec fetch_for_community(Api.t(), binary()) ::
          {:ok, [t()]} | {:error, Error.t() | Exception.t()}
  def fetch_for_community(%Api{} = client, community_uuid)
      when is_not_empty(community_uuid) do
    client
    |> Api.stream(
      [url: "#{@ep_community_url}/#{community_uuid}/collections"],
      &Response.extract_resources(&1, ["_embedded", "collections"]),
      &from_response/1
    )
    |> then(&{:ok, Enum.to_list(&1)})
  end

  @doc """
  Creates a new collection in the specified parent community.
  """
  @spec create(Api.t(), map(), binary()) :: {:ok, t()} | {:error, Error.t() | Exception.t()}
  def create(%Api{} = client, body, parent_uuid)
      when is_map(body) and is_not_empty(parent_uuid) do
    case Api.request(client,
           method: :post,
           url: @ep_url,
           params: [parent: parent_uuid],
           json: body
         ) do
      {:ok, response} -> {:ok, from_response(response.body)}
      {:error, _} = error -> error
    end
  end

  @doc """
  Updates a collection's metadata.
  """
  @spec update_metadata(Api.t(), binary(), map()) ::
          {:ok, t()} | {:error, Error.t() | Exception.t()}
  def update_metadata(%Api{} = client, uuid, patch_op) do
    case Api.request(client,
           method: :patch,
           url: "#{@ep_url}/#{uuid}",
           json: [patch_op]
         ) do
      {:ok, response} -> {:ok, from_response(response.body)}
      {:error, _} = error -> error
    end
  end

  @doc """
  Replaces a collection with the provided data.

  Note: This is a full replacement operation. All fields must be included and non-editable fields (id, uuid, handle, type) must remain unchanged if specified. For updating metadata only, use `update_metadata/3` instead.
  """
  @spec replace(Api.t(), binary(), map()) ::
          {:ok, t()} | {:error, Error.t() | Exception.t()}
  def replace(%Api{} = client, uuid, body) when is_not_empty(uuid) and is_map(body) do
    case Api.request(client,
           method: :put,
           url: "#{@ep_url}/#{uuid}",
           json: body
         ) do
      {:ok, response} -> {:ok, from_response(response.body)}
      {:error, _} = error -> error
    end
  end

  @doc """
  Deletes a collection.
  """
  @spec delete(Api.t(), binary()) :: :ok | {:error, Error.t() | Exception.t()}
  def delete(%Api{} = client, uuid) when is_not_empty(uuid) do
    case Api.request(client, method: :delete, url: "#{@ep_url}/#{uuid}") do
      {:ok, _} -> :ok
      {:error, _} = error -> error
    end
  end

  @doc false
  @spec from_response(map()) :: t()
  def from_response(body) when is_map(body) do
    %__MODULE__{
      dspace_object: Object.from_response(body),
      archived_items_count: Map.get(body, "archivedItemsCount", -1),
      metadata: Metadata.normalize(body["metadata"])
    }
  end

  def from_response(_), do: %__MODULE__{}
end
