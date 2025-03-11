defmodule DSpace.Api.Items.Item do
  @moduledoc """
  Represents a DSpace Item, which is a type of DSpace Object that represents a discrete record with
  metadata, files ("bitstreams"), permissions and policies (who can view, edit, or manage the item) and relations to collections (an item must belong to at least one collection).

  In DSpace-CRIS, items represent different entity types (Publication, Person,
  Project, etc.) as defined by the `entityType` field.
  """

  @typedoc """
  A DSpace Item structure.

  ## Fields:
  * `object`: `t:DSpace.Api.Object.t/0` with common attributes like UUID, name and modification date
  * `in_archive`: Whether the item is successfully deposited in the repository and has passed all workflow steps (i.e. not a draft or in submission anymore)
  * `discoverable`: Whether the item is discoverable in search/browse/OAI results
  * `withdrawn`: Whether the item has been withdrawn (if true, only accessible to admins)
  * `entity_type`: Type of entity this item represents ("Publication", "Person", etc.)
  """
  @type t :: %__MODULE__{
          object: DSpace.Api.Object.t(),
          in_archive: boolean(),
          discoverable: boolean(),
          withdrawn: boolean(),
          entity_type: binary(),
          metadata: DSpace.Api.Metadata.t()
        }

  defstruct [
    :object,
    :in_archive,
    :discoverable,
    :withdrawn,
    :entity_type,
    :metadata
  ]

  ### Public API

  @doc """
  Fetches a DSpace item by UUID.

  The /core/items endpoint bypasses SOLR (?), giving us the item data directly.
  """
  @spec fetch(DSpace.Api.t(), binary()) :: {:ok, t()} | {:error, term()}
  def fetch(%DSpace.Api{} = client, uuid) when is_binary(uuid) do
    case DSpace.Api.request(client, url: "/core/items/#{uuid}") do
      {:ok, response} ->
        {:ok, from_response(response.body)}

      {:error, _} = error ->
        error
    end
  end

  @doc """
  Casts a `t:DSpace.Api.Items.Item.t/0` struct from API response data.
  """
  @spec from_response(map()) :: t()
  def from_response(body) when is_map(body) do
    {normalized_metadata, entity_type} = DSpace.Api.Metadata.normalize_with_type(body["metadata"])

    %__MODULE__{
      object: DSpace.Api.Object.from_response(body),
      in_archive: Map.get(body, "inArchive", false),
      discoverable: Map.get(body, "discoverable", true),
      withdrawn: Map.get(body, "withdrawn", false),
      entity_type: entity_type,
      metadata: normalized_metadata
    }
  end

  def from_response(_), do: %__MODULE__{}
end
