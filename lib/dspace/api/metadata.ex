defmodule DSpace.API.Metadata do
  @moduledoc """
  Functions for working with metadata schemas and fields.
  """

  import DSpace.Utils, only: [is_nonempty_binary: 1, pop_pagination: 1]

  alias DSpace.API.Operation
  alias DSpace.API.StreamBuilder
  alias DSpace.API.Transform

  @ep_fields "/api/core/metadatafields"
  @ep_fields_search @ep_fields <> "/search/byFieldName"
  @ep_fields_by_schema @ep_fields <> "/search/bySchema"
  @ep_schemas "/api/core/metadataschemas"

  # Public API

  @doc """
  Fetches a single metadata field by ID.
  """
  @spec fetch_field(binary()) :: Operation.t()
  def fetch_field(id) when is_nonempty_binary(id) do
    %Operation.JSON{path: @ep_fields <> "/" <> id}
  end

  @doc """
  Lists metadata fields of the repository.

  Providing a schema option limits the results to the fields defined by the schema. The API
  currently doesn't support providing several schemas at once.

  This operation can be streamed.

  ## Options

    * `:schema` - prefix of a metadata schema (e.g., "dc")
    * `:page` - Page number (0-based, defaults to 0)
    * `:size` - Number of items per page (usually defaults to 20)
  """
  @spec list_fields(keyword()) :: Operation.t()
  def list_fields(options \\ []) when is_list(options) do
    {maybe_schema, options} = Keyword.pop(options, :schema)
    {pagination, options} = pop_pagination(options)

    params = pagination ++ options

    transformer = &Transform.transform_collection(&1, extract: ["_embedded", "metadatafields"])

    op =
      if is_nonempty_binary(maybe_schema) do
        %Operation.JSON{
          path: @ep_fields_by_schema,
          params: Keyword.merge([schema: maybe_schema], params),
          transformer: transformer
        }
      else
        %Operation.JSON{
          path: @ep_fields,
          params: params,
          transformer: transformer
        }
      end

    %{op | stream_impl: &StreamBuilder.new(&1, op, &2)}
  end

  @doc """
  Finds metadata fields based on the given options.

  This operation can be streamed.

  ## Options

    * `:name` - exact fully qualified field (e.g., "dc.title", "dc.contributor.author")
    * `:schema` - prefix of the metadata schema (e.g., "dc", "eperson")
    * `:element` - a field's element (e.g., "contributor", "title")
    * `:qualifier` - a field's qualifier (e.g., "author")
    * `:query` – search term (e.g., "dc.ti", "contributor", "auth", "contributor.ot")
    * `:page` - Page number (0-based, defaults to 0)
    * `:size` - Number of items per page (usually defaults to 20)
  """
  @spec find_fields(keyword()) :: Operation.t()
  def find_fields(options \\ []) when is_list(options) do
    {pagination, other_options} = pop_pagination(options)

    %Operation.JSON{
      path: @ep_fields_search,
      params: pagination ++ other_options
    }
  end

  @doc """
  Creates a metadata field under the given schema.

  Executing this operation requires administrator privileges.
  """
  @spec create_field(map(), keyword()) :: Operation.t()
  def create_field(field, options \\ []) when is_map(field) and is_list(options) do
    params = add_parent([], options[:schema_id])
    data = normalize_field_payload(field)

    %Operation.JSON{
      path: @ep_fields,
      http_method: :post,
      params: params,
      data: data
    }
  end

  @doc """
  Updates a metadata field.

  The API only supports updating the scope note of a field.
  """
  @spec update_field(binary(), map()) :: Operation.t()
  def update_field(id, updates) when is_nonempty_binary(id) and is_map(updates) do
    data = normalize_field_payload(updates)

    %Operation.JSON{
      path: @ep_fields <> "/" <> id,
      http_method: :put,
      data: data
    }
  end

  @doc """
  Deletes a metadata field.
  """
  @spec delete_field(binary()) :: Operation.t()
  def delete_field(id) when is_nonempty_binary(id) do
    %Operation.JSON{
      path: @ep_fields <> "/" <> id,
      http_method: :delete,
      transformer: fn _ -> :ok end
    }
  end

  @doc """
  Fetches a single metadata schema by ID.
  """
  @spec fetch_schema(binary()) :: Operation.t()
  def fetch_schema(id) when is_nonempty_binary(id) do
    %Operation.JSON{path: @ep_schemas <> "/" <> id}
  end

  @doc """
  Lists all metadata schemas of the repository.

  This operation can be streamed.

  ## Options

    * `:page` - Page number (0-based, defaults to 0)
    * `:size` - Number of items per page (usually defaults to 20)
  """
  @spec list_schemas(keyword()) :: Operation.t()
  def list_schemas(options \\ []) when is_list(options) do
    {pagination, other_options} = pop_pagination(options)

    op = %Operation.JSON{
      path: @ep_schemas,
      params: pagination ++ other_options,
      transformer: &Transform.transform_collection(&1, extract: ["_embedded", "metadataschemas"])
    }

    %{op | stream_impl: &StreamBuilder.new(&1, op, &2)}
  end

  @doc """
  Creates a metadata schema.
  """
  @spec create_schema(map(), keyword()) :: Operation.t()
  def create_schema(schema, _options \\ []) when is_map(schema) do
    %Operation.JSON{
      path: @ep_schemas,
      http_method: :post,
      data: schema
    }
  end

  @doc """
  Updates a metadata schema.
  """
  @spec update_schema(binary(), map()) :: Operation.t()
  def update_schema(id, updates) when is_nonempty_binary(id) and is_map(updates) do
    %Operation.JSON{
      path: @ep_schemas <> "/" <> id,
      http_method: :put,
      data: updates
    }
  end

  @doc """
  Deletes a metadata schema.
  """
  @spec delete_schema(binary()) :: Operation.t()
  def delete_schema(id) when is_nonempty_binary(id) do
    %Operation.JSON{
      path: @ep_schemas <> "/" <> id,
      http_method: :delete,
      transformer: fn _ -> :ok end
    }
  end

  # Private helpers

  defp add_parent(params, parent_id) when is_nonempty_binary(parent_id) do
    Keyword.put(params, :schemaId, parent_id)
  end

  defp normalize_field_payload(map) do
    {scope_note, rest} = Map.pop(map, :scope_note)

    rest
    |> Map.new(fn {k, v} -> {to_string(k), v} end)
    |> Map.put("scopeNote", scope_note)
  end
end
