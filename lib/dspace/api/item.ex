defmodule DSpace.Api.Item do
  @moduledoc """
  Represents a DSpace Item, which is a type of DSpace Object that represents a discrete record with metadata, files ("bitstreams"), permissions and policies (who can view, edit, or manage the item) and relations to collections (an item must belong to at least one collection).

  In DSpace-CRIS, items represent different entity types (Publication, Person, Project, etc.) as defined by the `entityType` field.
  """

  defstruct [
    :dspace_object,
    :in_archive,
    :discoverable,
    :withdrawn,
    :entity_type,
    :metadata
  ]

  @typedoc """
  A DSpace Item struct.

  ## Fields:
  * `dspace_object`: `t:DSpace.Api.Object.t/0` with common attributes like UUID, name and modification date
  * `in_archive`: Whether the item is successfully deposited in the repository and has passed all workflow steps (i.e. not a draft or in submission anymore)
  * `discoverable`: Whether the item is discoverable in search/browse/OAI results
  * `withdrawn`: Whether the item has been withdrawn (if true, only accessible to admins)
  * `entity_type`: Type of entity this item represents ("Publication", "Person", etc.)
  * `metadata`: `t:DSpace.Api.Metadata.t/0` map where keys are metadata field names and values are lists of metadata value and props
  """
  @type t :: %__MODULE__{
          dspace_object: DSpace.Api.Object.t(),
          in_archive: boolean(),
          discoverable: boolean(),
          withdrawn: boolean(),
          entity_type: binary(),
          metadata: DSpace.Api.Metadata.t()
        }

  @typedoc """
  Options for fetching multiple items.
  """
  @type fetch_all_opts :: [
          limit: pos_integer(),
          entity_type: binary(),
          sort: binary() | atom() | {binary(), :asc | :desc},
          include: atom() | [atom()]
        ]

  @ep_url "/api/core/items"

  # Public API

  @doc """
  Creates an Item struct from API response data.
  """
  @spec from_response(map()) :: t()
  def from_response(body) when is_map(body) do
    {normalized_metadata, entity_type} = DSpace.Api.Metadata.normalize_with_type(body["metadata"])

    # TODO: extract embeds

    %__MODULE__{
      dspace_object: DSpace.Api.Object.from_response(body),
      in_archive: Map.get(body, "inArchive", false),
      discoverable: Map.get(body, "discoverable", true),
      withdrawn: Map.get(body, "withdrawn", false),
      entity_type: entity_type,
      metadata: normalized_metadata
    }
  end

  def from_response(_), do: %__MODULE__{}

  @doc """
  Fetches a single item by UUID.
  """
  @spec fetch(DSpace.Api.t(), binary()) ::
          {:ok, t()} | {:error, DSpace.Api.Error.t() | Exception.t()}
  def fetch(%DSpace.Api{} = client, uuid) when is_binary(uuid) do
    case DSpace.Api.request(client, url: "#{@ep_url}/#{uuid}") do
      {:ok, response} ->
        {:ok, from_response(response.body)}

      {:error, _} = error ->
        error
    end
  end

  @doc """
  Fetches multiple items from the repository.

  Note: This function requires administrator privileges as it uses the direct database access endpoint. Due to [API "limitations"](https://github.com/DSpace/DSpace/issues/3325), this endpoint currently only returns published items.

  ## Options

  * `:limit` - Maximum number of items to return (optional)
  * `:entity_type` - Filter by entity type (e.g., "Publication")
  * `:sort` - Sorting criteria, such as `:last_modified`
  * `:include` - Related resources to include with each item:
    * `:files` - Include file information ("bundles")
    * `:collections` - Include all collections
    * `:primary_collection` - Only owning collection
    * `:relationships` - Include entity relationships
    * `:thumbnails` - Include thumbnail information
    * `:all` - Include all related resources
  """
  @spec fetch_all(DSpace.Api.t(), fetch_all_opts()) ::
          {:ok, [t()]} | {:error, DSpace.Api.Error.t() | Exception.t()}
  def fetch_all(%DSpace.Api{} = client, opts \\ []) do
    params =
      []
      |> maybe_add_filter(:entityType, opts[:entity_type])
      |> maybe_add_sort(opts[:sort] || :last_modified)
      |> maybe_add_embeds(normalize_includes(opts[:include]))

    client
    |> DSpace.Api.stream(
      [url: @ep_url, params: params],
      &DSpace.Api.Response.extract_resources(&1, ["_embedded", "items"]),
      &from_response/1
    )
    |> maybe_add_limit(opts[:limit])
    |> then(&{:ok, Enum.to_list(&1)})
  end

  # Private Helpers

  defp maybe_add_filter(params, _key, nil), do: params
  defp maybe_add_filter(params, key, value), do: Keyword.put(params, key, value)

  defp maybe_add_sort(params, nil), do: params
  defp maybe_add_sort(params, sort) when is_binary(sort), do: Keyword.put(params, :sort, sort)
  defp maybe_add_sort(params, :name), do: Keyword.put(params, :sort, "name,asc")
  defp maybe_add_sort(params, :title), do: Keyword.put(params, :sort, "name,asc")
  defp maybe_add_sort(params, :last_modified), do: Keyword.put(params, :sort, "lastModified,desc")
  defp maybe_add_sort(params, :handle), do: Keyword.put(params, :sort, "handle,asc")
  defp maybe_add_sort(params, :id), do: Keyword.put(params, :sort, "id,asc")

  defp maybe_add_sort(params, {field, :asc}) when is_binary(field),
    do: Keyword.put(params, :sort, "#{field},asc")

  defp maybe_add_sort(params, {field, :desc}) when is_binary(field),
    do: Keyword.put(params, :sort, "#{field},desc")

  defp maybe_add_sort(params, _), do: params

  defp maybe_add_embeds(params, []), do: params

  defp maybe_add_embeds(params, embeds) when is_list(embeds),
    do: Keyword.put(params, :embed, Enum.join(embeds, ","))

  defp normalize_includes(nil), do: []

  defp normalize_includes(:all),
    do: ["bundles", "owningCollection", "mappedCollections", "relationships", "thumbnail"]

  defp normalize_includes(:files), do: ["bundles"]
  defp normalize_includes(:collections), do: ["owningCollection", "mappedCollections"]
  defp normalize_includes(:primary_collection), do: ["owningCollection"]
  defp normalize_includes(:relationships), do: ["relationships"]
  defp normalize_includes(:thumbnails), do: ["thumbnail"]

  defp normalize_includes(includes) when is_list(includes) do
    Enum.flat_map(includes, &normalize_includes/1)
    |> Enum.uniq()
  end

  defp normalize_includes(_), do: []

  defp maybe_add_limit(stream, nil), do: stream

  defp maybe_add_limit(stream, limit) when is_integer(limit) and limit > 0,
    do: Stream.take(stream, limit)
end
