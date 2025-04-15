defmodule DSpace.Api.Community do
  @moduledoc """
  Represents a DSpace Community, which is a container for collections.
  Communities form the hierarchical structure of a DSpace repository.
  """

  defstruct [
    :dspace_object,
    :archived_items_count,
    :metadata
  ]

  @typedoc """
  A DSpace Community struct.

  ## Fields:
  * `dspace_object`: `t:DSpace.Api.Object.t/0` with common attributes like UUID, name and modification date
  * `archived_items_count`: Number of archived items in this community and its sub-communities (-1 if not calculated)
  * `metadata`: `t:DSpace.Api.Metadata.t/0` map where keys are metadata field names and values are lists of metadata value and props
  """
  @type t :: %__MODULE__{
          dspace_object: DSpace.Api.Object.t(),
          archived_items_count: integer(),
          metadata: DSpace.Api.Metadata.t()
        }

  @ep_url "/api/core/communities"

  @doc """
  Creates a Community struct from API response data.
  """
  @spec from_response(map()) :: t()
  def from_response(body) when is_map(body) do
    %__MODULE__{
      dspace_object: DSpace.Api.Object.from_response(body),
      archived_items_count: Map.get(body, "archivedItemsCount", -1),
      metadata: DSpace.Api.Metadata.normalize(body["metadata"])
    }
  end

  def from_response(_), do: %__MODULE__{}

  @doc """
  Fetches a single community by UUID.
  """
  @spec fetch(DSpace.Api.t(), binary()) ::
          {:ok, t()} | {:error, DSpace.Api.Error.t() | Exception.t()}
  def fetch(%DSpace.Api{} = client, uuid) when is_binary(uuid) do
    case DSpace.Api.request(client, url: "#{@ep_url}/#{uuid}") do
      {:ok, response} -> {:ok, from_response(response.body)}
      {:error, _} = error -> error
    end
  end

  @doc """
  Fetches all communities.
  """
  @spec fetch_all(DSpace.Api.t()) ::
          {:ok, [t()]} | {:error, DSpace.Api.Error.t() | Exception.t()}
  def fetch_all(%DSpace.Api{} = client) do
    client
    |> DSpace.Api.stream(
      [url: @ep_url],
      &DSpace.Api.Response.extract_resources(&1, ["_embedded", "communities"]),
      &from_response/1
    )
    |> then(&{:ok, Enum.to_list(&1)})
  end

  @doc """
  Fetches all top-level communities.
  """
  @spec fetch_top(DSpace.Api.t()) :: {:ok, [t()]} | {:error, DSpace.Api.Error.t() | Exception.t()}
  def fetch_top(%DSpace.Api{} = client) do
    client
    |> DSpace.Api.stream(
      [url: "#{@ep_url}/search/top"],
      &DSpace.Api.Response.extract_resources(&1, ["_embedded", "communities"]),
      &from_response/1
    )
    |> then(&{:ok, Enum.to_list(&1)})
  end

  @doc """
  Creates a new top-level community.

  Requires admin authentication.
  """
  @spec create(DSpace.Api.t(), map()) ::
          {:ok, t()} | {:error, DSpace.Api.Error.t() | Exception.t()}
  def create(%DSpace.Api{} = client, body) when is_map(body) do
    case DSpace.Api.request(client, method: :post, url: @ep_url, json: body) do
      {:ok, response} -> {:ok, from_response(response.body)}
      {:error, _} = error -> error
    end
  end

  @doc """
  Creates a new sub-community under the specified parent community.
  """
  @spec create_sub(DSpace.Api.t(), map(), binary()) ::
          {:ok, t()} | {:error, DSpace.Api.Error.t() | Exception.t()}
  def create_sub(%DSpace.Api{} = client, body, parent_uuid)
      when is_map(body) and is_binary(parent_uuid) do
    case DSpace.Api.request(client,
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
  Updates a community's metadata.
  """
  @spec update_metadata(DSpace.Api.t(), binary(), map()) ::
          {:ok, t()} | {:error, DSpace.Api.Error.t() | Exception.t()}
  def update_metadata(%DSpace.Api{} = client, uuid, patch_op) do
    case DSpace.Api.request(client,
           method: :patch,
           url: "#{@ep_url}/#{uuid}",
           headers: [{"content-type", "application/json-patch+json"}],
           json: [patch_op]
         ) do
      {:ok, response} -> {:ok, from_response(response.body)}
      {:error, _} = error -> error
    end
  end

  @doc """
  Replaces a community with the provided data.

  Note: This is a full replacement operation. All fields must be included and non-editable fields (id, uuid, handle, type) must remain unchanged if specified. For updating metadata only, use `update_metadata/3` instead.
  """
  @spec replace(DSpace.Api.t(), binary(), map()) ::
          {:ok, t()} | {:error, DSpace.Api.Error.t() | Exception.t()}
  def replace(%DSpace.Api{} = client, uuid, body) when is_binary(uuid) and is_map(body) do
    case DSpace.Api.request(client,
           method: :put,
           url: "#{@ep_url}/#{uuid}",
           json: body
         ) do
      {:ok, response} -> {:ok, from_response(response.body)}
      {:error, _} = error -> error
    end
  end

  @doc """
  Deletes a community.
  """
  @spec delete(DSpace.Api.t(), binary()) :: :ok | {:error, DSpace.Api.Error.t() | Exception.t()}
  def delete(%DSpace.Api{} = client, uuid) when is_binary(uuid) do
    case DSpace.Api.request(client, method: :delete, url: "#{@ep_url}/#{uuid}") do
      {:ok, _} -> :ok
      {:error, _} = error -> error
    end
  end
end
