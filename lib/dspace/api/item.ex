defmodule DSpace.API.Item do
  @moduledoc """
  Functions for working with DSpace Items.

  An Item represents a discrete record. It has metadata, files ("Bitstreams") and file bundles,
  permissions and policies (who can view, edit, or manage the item), and relations to Collections
  (an Item must belong to at least one Collection). Items can represent different entity types
  (Publication, Person, Project, etc.).

  In DSpace-speak, draft state data associated with an item is called a "workspace item" and
  modelled as a separate entity from the underlying main item. The same goes for workflow state
  data, which is called a "workflow item" and also modelled as a separate entity from the main
  item.
  """

  @behaviour DSpace.API.Resource

  import DSpace.Utils, only: [is_nonempty_binary: 1, maybe_add_base_url: 2, pop_pagination: 1]

  alias DSpace.API.Error
  alias DSpace.API.HTTP.Response
  alias DSpace.API.Operation
  alias DSpace.API.Resource
  alias DSpace.API.Search
  alias DSpace.API.StreamBuilder
  alias DSpace.API.Transform

  @ep_core "/api/core/items"
  @ep_core_by_id @ep_core <> "/search/findAllByIds"
  @ep_pids "/api/pid/identifiers"
  @ep_workspace "/api/submission/workspaceitems"
  @ep_workflow "/api/workflow/workflowitems"

  @default_file_bundle_name DSpace.API.File.default_bundle_name()

  # Public API

  @doc """
  Fetches the access status of an item
  """
  @spec access_status(binary()) :: Operation.JSON.t()
  def access_status(uuid) when is_nonempty_binary(uuid) do
    %Operation.JSON{
      path: @ep_core <> "/" <> uuid <> "/accessStatus",
      transformer: &Transform.get(&1, "status")
    }
  end

  @doc """
  Fetches stored metrics of an item.

  This operation can be streamed.
  """
  @spec metrics(binary()) :: Operation.JSON.t()
  def metrics(uuid) when is_nonempty_binary(uuid) do
    %Operation.JSON{
      path: @ep_core <> "/" <> uuid <> "/metrics",
      transformer: &Transform.transform_collection(&1, extract: ["_embedded", "metrics"])
    }
  end

  @doc """
  Fetches the parent collection of an item.
  """
  @spec parent(binary()) :: Operation.JSON.t()
  def parent(uuid) when is_nonempty_binary(uuid) do
    %Operation.JSON{path: @ep_core <> "/" <> uuid <> "/owningCollection"}
  end

  @doc """
  Fetches all persistent identifiers associated with an item.
  """
  @spec pids(binary()) :: Operation.JSON.t()
  def pids(uuid) when is_nonempty_binary(uuid) do
    %Operation.JSON{
      path: @ep_core <> "/" <> uuid <> "/identifiers",
      transformer: &Transform.get(&1, "identifiers")
    }
  end

  @doc """
  Mints and queues a DOI for registration for a given item.
  """
  @spec register_doi(binary()) :: Operation.JSON.t()
  def register_doi(uuid) when is_nonempty_binary(uuid) do
    %Operation.JSON{
      path: @ep_pids,
      http_method: :post,
      params: [type: "doi"],
      content_type: :uri_list,
      data: uuid,
      # The API expects a full "core" URL for the item, not just the UUID
      before_step: &build_uri_payload/3
    }
  end

  @doc """
  Withdraws an item from the archive, making it no longer publicly accessible.

  This is a convenience wrapper around `update/3` that sets the `withdrawn` flag to `true`.
  """
  @spec withdraw(binary()) :: Operation.JSON.t()
  def withdraw(uuid) when is_nonempty_binary(uuid) do
    update(uuid, [%{"op" => "replace", "path" => "/withdrawn", "value" => true}])
  end

  @doc """
  Hides an item from discovery, making it no longer findable via search.

  This is a convenience wrapper around `update/3` that sets the `discoverable` flag to `false`.
  """
  @spec hide(binary()) :: Operation.JSON.t()
  def hide(uuid) when is_nonempty_binary(uuid) do
    update(uuid, [%{"op" => "replace", "path" => "/discoverable", "value" => false}])
  end

  @doc """
  Fetches the draft associated with an item.

  In DSpace-speak, draft state data associated with an item is called a "workspace item" and
  modelled as a separate entity from the main item. Executing this operation will return that data
  structure.
  """
  @spec fetch_draft(binary()) :: Operation.JSON.t()
  def fetch_draft(uuid) when is_nonempty_binary(uuid) do
    %Operation.JSON{
      path: @ep_workspace <> "/search/item",
      params: [uuid: uuid],
      expected_status: [200, 204],
      transformer: &not_found_on_no_content(&1, "No draft found for this item")
    }
  end

  @doc """
  Fetches a draft by its workspace ID.

  Note: The ID of the item in the workspace is an integer and *different* from the Item's UUID.
  If you want to fetch a draft via Item UUID, see `fetch_draft/1`.
  """
  @spec fetch_draft_by_id(pos_integer()) :: Operation.JSON.t()
  def fetch_draft_by_id(ws_id) when is_integer(ws_id) and ws_id > 0 do
    %Operation.JSON{path: @ep_workspace <> "/" <> Integer.to_string(ws_id)}
  end

  @doc """
  Creates a new draft item, starting a submission.

  In DSpace-speak, draft state data associated with an item is called a "workspace item" and
  modelled as a separate entity from the main item. Executing this operation will return that
  data structure.

  ## Options

    * `:parent` - Required. UUID of the collection that will own this item.
  """
  @spec create_draft(keyword()) :: Operation.JSON.t()
  def create_draft(options) when is_list(options) do
    params = add_parent([], options[:parent])

    %Operation.JSON{
      path: @ep_workspace,
      http_method: :post,
      params: params
    }
  end

  @doc """
  Updates a draft in the workspace.

  Note: The `ws_id` param is the workspace ID, not the Item's UUID.
  """
  @spec update_draft(pos_integer(), list()) :: Operation.JSON.t()
  def update_draft(ws_id, patch_operations) when is_integer(ws_id) and is_list(patch_operations) do
    %Operation.JSON{
      path: @ep_workspace <> "/" <> Integer.to_string(ws_id),
      http_method: :patch,
      data: patch_operations
    }
  end

  @doc """
  Deletes a draft item from the workspace.

  Note: The `ws_id` param is the workspace ID, not the Item's UUID.
  """
  @spec delete_draft(pos_integer()) :: Operation.JSON.t()
  def delete_draft(ws_id) when is_integer(ws_id) do
    %Operation.JSON{
      path: @ep_workspace <> "/" <> Integer.to_string(ws_id),
      http_method: :delete,
      transformer: fn _ -> :ok end
    }
  end

  @doc """
  Submits one or more draft items.

  This is the bridge from what in DSpace is called "workspace" to "workflow". Call this when an
  item is ready for editorial review or archiving. Accepts either a single workspace item ID or a
  list of IDs.

  If no editorial workflow is configured for the collection, the item is published immediately and
  `:archived` is returned instead of a "workflow item" map.
  """
  @spec submit(pos_integer() | [pos_integer()], keyword()) :: Operation.JSON.t()
  def submit(ws_id, options \\ [])

  def submit(ws_id, options) when is_integer(ws_id) and ws_id > 0 do
    submit([ws_id], options)
  end

  def submit(ws_id, _options) when is_list(ws_id) and ws_id != [] do
    transformer = fn
      %Response{body: body} when is_map(body) and map_size(body) > 0 -> body
      _ -> :archived
    end

    %Operation.JSON{
      path: @ep_workflow,
      http_method: :post,
      content_type: :uri_list,
      data: ws_id,
      transformer: transformer,
      before_step: &build_workflow_payload/3
    }
  end

  @doc """
  Fetches the workflow data associated with a given item UUID.

  In DSpace-speak, workflow state data associated with an item is called a "workflow item" and
  modelled as a separate entity from the main item. There is at most one "workflow item" per item.
  """
  @spec fetch_workflow(binary()) :: Operation.JSON.t()
  def fetch_workflow(item_uuid) when is_nonempty_binary(item_uuid) do
    %Operation.JSON{
      path: @ep_workflow <> "/search/item",
      params: [uuid: item_uuid],
      expected_status: [200, 204],
      transformer: &not_found_on_no_content(&1, "No workflow data found for this item")
    }
  end

  @doc """
  Fetches a "workflow item" by its ID.

  Note: The "workflow item" ID is an integer and *different* from the Item's UUID. To find a
  workflow item via Item UUID, see `fetch_workflow/1`.
  """
  @spec fetch_workflow_by_id(pos_integer()) :: Operation.JSON.t()
  def fetch_workflow_by_id(wf_id) when is_integer(wf_id) and wf_id > 0 do
    %Operation.JSON{path: @ep_workflow <> "/" <> Integer.to_string(wf_id)}
  end

  @doc """
  Lists "workflow items", optionally filtered by submitter.

  This operation can be streamed.

  ## Options

    * `:submitter` - UUID of the submitter (user) to filter by; must be a non-empty binary
    * `:page` - Page number (0-based)
    * `:size` - Items per page
  """
  @spec list_in_workflow(keyword()) :: Operation.JSON.t()
  def list_in_workflow(options \\ []) when is_list(options) do
    {maybe_submitter, options} = Keyword.pop(options, :submitter)
    {pagination, options} = pop_pagination(options)

    params = pagination ++ options

    transformer = &Transform.transform_collection(&1, extract: ["_embedded", "workflowitems"])

    op =
      if is_nonempty_binary(maybe_submitter) do
        %Operation.JSON{
          path: @ep_workflow <> "/search/findBySubmitter",
          params: [uuid: maybe_submitter] ++ params,
          transformer: transformer
        }
      else
        %Operation.JSON{
          path: @ep_workflow,
          params: params,
          transformer: transformer
        }
      end

    %{op | stream_impl: &StreamBuilder.new(&1, op, &2)}
  end

  @doc """
  Deletes a workflow item.

  By default, this sends the item back to the submitter's "workspace". With the `:expunge` option,
  it permanently destroys the workflow item and its associated item.

  ## Options

    * `:expunge` - If `true`, permanently deletes the item instead of returning it to the
      submitter's workspace (defaults to `false`)
  """
  @spec delete_from_workflow(pos_integer(), keyword()) :: Operation.JSON.t()
  def delete_from_workflow(wf_id, options \\ []) when is_integer(wf_id) and wf_id > 0 do
    params = if options[:expunge], do: [expunge: "true"], else: []

    %Operation.JSON{
      path: @ep_workflow <> "/" <> Integer.to_string(wf_id),
      http_method: :delete,
      params: params,
      transformer: fn _ -> :ok end
    }
  end

  @doc """
  Creates a new file bundle in an item.

  Executing this operation will return an error if a bundle with the same name already exists in
  the item.

  ## Parameters

    * `uuid` - UUID of the item
    * `bundle` - bundle attributes as a map. Supports `"name"` (defaults to `"ORIGINAL"`) and
      `"metadata"`.
  """
  @spec create_file_bundle(binary(), map()) :: Operation.JSON.t()
  def create_file_bundle(uuid, bundle \\ %{}) when is_nonempty_binary(uuid) and is_map(bundle) do
    %Operation.JSON{
      path: @ep_core <> "/" <> uuid <> "/bundles",
      http_method: :post,
      data:
        bundle
        |> Map.put_new("name", @default_file_bundle_name)
        |> Map.put_new("metadata", %{})
    }
  end

  @doc """
  Lists the file bundles of an item.

  This operation can be streamed.
  """
  @spec list_file_bundles(binary(), keyword()) :: Operation.JSON.t()
  def list_file_bundles(uuid, _options \\ []) when is_nonempty_binary(uuid) do
    op = %Operation.JSON{
      path: @ep_core <> "/" <> uuid <> "/bundles",
      transformer: &Transform.transform_collection(&1, extract: ["_embedded", "bundles"])
    }

    %{op | stream_impl: &StreamBuilder.new(&1, op, &2)}
  end

  @doc """
  Fetches the "workspace item" associated with an item.

  Alias, prefer `fetch_draft/1`.
  """
  @spec fetch_workspace(binary()) :: Operation.JSON.t()
  def fetch_workspace(uuid), do: fetch_draft(uuid)

  @doc """
  Creates a "workspace item".

  Alias, prefer `create_draft/1`.
  """
  @spec create_in_workspace(keyword()) :: Operation.JSON.t()
  def create_in_workspace(options), do: create_draft(options)

  @doc """
  Updates a "workspace item".

  Alias, prefer `update_draft/2`.
  """
  @spec update_in_workspace(pos_integer(), list()) :: Operation.JSON.t()
  def update_in_workspace(ws_id, patch_operations), do: update_draft(ws_id, patch_operations)

  @doc """
  Deletes a "workspace item".

  Alias, prefer `delete_draft/1`.
  """
  @spec delete_from_workspace(pos_integer()) :: Operation.JSON.t()
  def delete_from_workspace(ws_id), do: delete_draft(ws_id)

  # Callbacks

  @doc """
  Fetches a single item by UUID.
  """
  @impl Resource
  @spec fetch(binary(), keyword()) :: Operation.JSON.t()
  def fetch(uuid, _options \\ []) when is_nonempty_binary(uuid) do
    %Operation.JSON{path: @ep_core <> "/" <> uuid}
  end

  @doc """
  Finds items using Discovery search.

  This operation can be streamed.

  ## Parameters

    * `options` - Search options, see `DSpace.API.Search.query/1` for details

  ## Examples

      # Find all items
      Item.find()

      # Find all items with filters
      Item.find(filters: [%{filter: "author", operator: "contains", value: "Smith"}])

      # Simple item search with text query
      Item.find(query: "elixir programming")

      # Search with additional filters
      Item.find(query: "research", filters: [%{filter: "author", operator: "contains", value: "Armstrong"}])

      # Search within a specific collection
      Item.find(query: "data", scope: "collection-uuid")
  """
  @impl Resource
  @spec find(keyword()) :: Operation.JSON.t()
  def find(options \\ []) when is_list(options) do
    search_options = Keyword.put(options, :dsoType, "Item")

    Search.query(search_options)
  end

  @doc """
  List items from the repository.

  Note: Unless you pass a list of specific item UUIDs, this operation requires administrator
  privileges as it uses the direct database access endpoint. To fetch all items publicly, use
  `find/1` instead. Passing a list of item UUIDs will only work with the CRIS fork of DSpace.

  Due to ["API limitations"](https://github.com/DSpace/DSpace/issues/3325), the core endpoint
  currently only returns *published* items.

  This operation can be streamed.

  ## Options

    * `:id` - Specific item UUIDs as a list
    * `:page` - Page number (0-based, defaults to 0)
    * `:size` - Number of items per page (usually defaults to 20)
  """
  @impl Resource
  @spec list(keyword()) :: Operation.JSON.t()
  def list(options \\ []) do
    {maybe_ids, options} = Keyword.pop(options, :id)
    {pagination, options} = pop_pagination(options)

    params = pagination ++ options

    transformer = &Transform.transform_collection(&1, extract: ["_embedded", "items"])

    op =
      if maybe_ids do
        %Operation.JSON{
          path: @ep_core_by_id,
          params: params ++ Enum.map(maybe_ids, &{:id, &1}),
          transformer: transformer
        }
      else
        %Operation.JSON{
          path: @ep_core,
          params: params,
          transformer: transformer
        }
      end

    %{op | stream_impl: &StreamBuilder.new(&1, op, &2)}
  end

  @doc """
  Creates a new item in the archive.

  This operation requires administrator privileges.

  ## Options

    * `:parent` - Required. UUID of the collection that will own this item
  """
  @impl Resource
  @spec create(map(), keyword()) :: Operation.JSON.t()
  def create(item, options \\ []) when is_map(item) do
    params = add_parent([], options[:parent])

    %Operation.JSON{
      path: @ep_core,
      http_method: :post,
      params: params,
      data: item
    }
  end

  @doc """
  Updates an existing item.
  """
  @impl Resource
  @spec update(binary(), list(), keyword()) :: Operation.JSON.t()
  def update(uuid, updates, _options \\ []) when is_nonempty_binary(uuid) and is_list(updates) do
    %Operation.JSON{
      path: @ep_core <> "/" <> uuid,
      http_method: :patch,
      data: updates
    }
  end

  @doc """
  Replaces an existing item.
  """
  @impl Resource
  @spec replace(binary(), map(), keyword()) :: Operation.JSON.t()
  def replace(uuid, item, _options \\ []) when is_nonempty_binary(uuid) and is_map(item) do
    %Operation.JSON{
      path: @ep_core <> "/" <> uuid,
      http_method: :put,
      data: item
    }
  end

  @doc """
  Deletes an item.

  ## Options

    * `:copy_virtual_metadata` - Turn virtual metadata to actual metadata in related items
      * `nil` - no virtual metadata is expanded (default)
      * `:all` - all relationships are verified and virtual metadata is migrated
      * `:configured` - behavior retrieved from configuration
      * `"relationship_type_id"` - only specific relationship type IDs are migrated
  """
  @impl Resource
  @spec delete(binary(), keyword()) :: Operation.JSON.t()
  def delete(uuid, options \\ []) when is_nonempty_binary(uuid) do
    params = maybe_copy_virtual_metadata([], options[:copy_virtual_metadata])

    %Operation.JSON{
      path: @ep_core <> "/" <> uuid,
      params: params,
      http_method: :delete,
      transformer: fn _ -> :ok end
    }
  end

  # Private helpers

  # Sic, DSpace returns 204 if these requested resources are not found
  defp not_found_on_no_content(%Response{status: 204} = response, message) do
    Error.exception(type: :not_found, status: 404, message: message, response: response)
  end

  defp not_found_on_no_content(response, _message), do: Transform.from_response(response)

  defp add_parent(params, parent_uuid) when is_nonempty_binary(parent_uuid) do
    Keyword.put(params, :owningCollection, parent_uuid)
  end

  defp maybe_copy_virtual_metadata(params, nil), do: params

  defp maybe_copy_virtual_metadata(params, :all) do
    Keyword.put(params, :copyVirtualMetadata, "all")
  end

  defp maybe_copy_virtual_metadata(params, :configured) do
    Keyword.put(params, :copyVirtualMetadata, "configured")
  end

  defp maybe_copy_virtual_metadata(params, value) when is_nonempty_binary(value) do
    Keyword.put(params, :copyVirtualMetadata, value)
  end

  defp build_uri_payload(operation, %DSpace.API{endpoint: endpoint} = client, options) do
    item_uri = maybe_add_base_url(@ep_core <> "/" <> operation.data, endpoint)

    {%{operation | data: [item_uri]}, client, options}
  end

  defp build_workflow_payload(operation, %DSpace.API{endpoint: endpoint} = client, options) do
    uri_list =
      Enum.map(operation.data, fn id ->
        maybe_add_base_url(@ep_workspace <> "/" <> Integer.to_string(id), endpoint)
      end)

    {%{operation | data: uri_list}, client, options}
  end
end
