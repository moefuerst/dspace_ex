defmodule DSpace.API.ItemTest do
  use DSpace.API.Case, async: true

  alias DSpace.API.Error
  alias DSpace.API.Item

  describe "retrieving an item by UUID" do
    test "returns item when it exists", %{sham: sham, api: api} do
      uuid = "8f62713a-c495-467b-a918-2e392f781d2e"
      item_fixture = load_fixture("fetch_item.json")

      Sham.expect_once(sham, "GET", "/api/core/items/#{uuid}", fn conn ->
        respond_with_json(conn, 200, item_fixture)
      end)

      {:ok, result} =
        uuid
        |> Item.fetch()
        |> API.request(api)

      assert_valid_dspace_resource(result, "item", ["name", "handle", "metadata"])
      assert result["uuid"] == uuid
    end
  end

  describe "retrieving multiple items" do
    test "lists items with pagination support", %{sham: sham, api: api} do
      items_fixture = load_fixture("fetch_items.json")

      Sham.expect_once(sham, "GET", "/api/core/items", fn conn ->
        respond_with_json(conn, 200, items_fixture)
      end)

      {:ok, result} = API.request(Item.list(), api)

      {items, metadata, next_url} = result
      assert_valid_paginated_response({items, metadata, next_url})
      assert items != []

      first_item = Enum.at(items, 0)
      assert_valid_dspace_resource(first_item, "item")
    end

    test "retrieves specific items by UUIDs", %{sham: sham, api: api} do
      uuids = ["uuid1", "uuid2", "uuid3"]
      items_fixture = load_fixture("fetch_items.json")

      Sham.expect_once(sham, "GET", "/api/core/items/search/findAllByIds", fn conn ->
        params = Plug.Conn.fetch_query_params(conn).query_params

        case params["id"] do
          id_list when is_list(id_list) ->
            assert length(id_list) == 3

            Enum.each(uuids, fn uuid ->
              assert uuid in id_list
            end)

          single_id when is_binary(single_id) ->
            assert single_id in uuids
        end

        respond_with_json(conn, 200, items_fixture)
      end)

      {:ok, result} =
        [id: uuids]
        |> Item.list()
        |> API.request(api)

      {items, _metadata, _next_url} = result
      assert is_list(items)
    end

    test "supports custom pagination parameters", %{sham: sham, api: api} do
      Sham.expect_once(sham, "GET", "/api/core/items", fn conn ->
        params = Plug.Conn.fetch_query_params(conn).query_params
        assert params["page"] == "2"
        assert params["size"] == "10"

        response = ~s({
          "_embedded": {"items": []},
          "_links": {},
          "page": {
            "size": 10,
            "totalElements": 0,
            "totalPages": 0,
            "number": 2
          }
        })

        respond_with_json(conn, 200, response)
      end)

      {:ok, result} =
        [page: 2, size: 10]
        |> Item.list()
        |> API.request(api)

      {_items, metadata, _next_url} = result
      assert metadata["page"]["number"] == 2
      assert metadata["page"]["size"] == 10
    end
  end

  describe "searching for items" do
    test "finds all items when no search criteria provided", %{sham: sham, api: api} do
      search_fixture = load_fixture("search_objects.json")

      Sham.expect_once(sham, "GET", "/api/discover/search/objects", fn conn ->
        params = Plug.Conn.fetch_query_params(conn).query_params

        assert params["dsoType"] == "Item"
        refute Map.has_key?(params, "query")

        respond_with_json(conn, 200, search_fixture)
      end)

      {:ok, result} = API.request(Item.find(), api)

      {objects, _metadata, _next_url} = result
      assert is_list(objects)
    end

    test "searches items by query term", %{sham: sham, api: api} do
      search_term = "elixir programming"
      search_fixture = load_fixture("search_objects.json")

      Sham.expect_once(sham, "GET", "/api/discover/search/objects", fn conn ->
        params = Plug.Conn.fetch_query_params(conn).query_params

        assert params["query"] == search_term
        assert params["dsoType"] == "Item"

        respond_with_json(conn, 200, search_fixture)
      end)

      {:ok, result} =
        [query: search_term]
        |> Item.find()
        |> API.request(api)

      {objects, _metadata, _next_url} = result
      assert is_list(objects)
    end

    test "applies filters and pagination to search", %{sham: sham, api: api} do
      search_fixture = load_fixture("search_objects.json")

      options = [
        query: "research",
        page: 1,
        size: 5,
        scope: "collection-uuid-123",
        filters: [%{filter: "author", operator: "contains", value: "Smith"}]
      ]

      Sham.expect_once(sham, "GET", "/api/discover/search/objects", fn conn ->
        params = Plug.Conn.fetch_query_params(conn).query_params

        assert params["query"] == "research"
        assert params["dsoType"] == "Item"
        assert params["page"] == "1"
        assert params["size"] == "5"
        assert params["scope"] == "collection-uuid-123"
        assert params["f.author"] == "Smith,contains"

        respond_with_json(conn, 200, search_fixture)
      end)

      {:ok, result} =
        options
        |> Item.find()
        |> API.request(api)

      {objects, _metadata, _next_url} = result
      assert is_list(objects)
    end
  end

  describe "creating items" do
    test "creates item in specified collection", %{sham: sham, api: api} do
      collection_uuid = "parent-collection-uuid"
      item_data = test_item_data(%{"name" => "New Research Item"})
      item_fixture = load_fixture("fetch_item.json")

      Sham.expect_once(sham, "POST", "/api/core/items", fn conn ->
        params = Plug.Conn.fetch_query_params(conn).query_params
        {:ok, body, conn} = Plug.Conn.read_body(conn)
        request_data = JSON.decode!(body)

        assert params["owningCollection"] == collection_uuid
        assert request_data["name"] == "New Research Item"

        respond_with_json(conn, 201, item_fixture)
      end)

      {:ok, result} =
        item_data
        |> Item.create(parent: collection_uuid)
        |> API.request(api)

      assert_valid_dspace_resource(result, "item")
      assert result["uuid"] == "8f62713a-c495-467b-a918-2e392f781d2e"
    end

    test "requires owning collection for creation" do
      item_data = test_item_data()

      assert_raise KeyError, fn ->
        Item.create(item_data, [])
      end
    end
  end

  describe "modifying existing items" do
    test "updates item with patch operations", %{sham: sham, api: api} do
      uuid = "8f62713a-c495-467b-a918-2e392f781d2e"
      update_operations = test_update_operations("dc.title", "Updated Item Title")
      item_fixture = load_fixture("fetch_item.json")

      Sham.expect_once(sham, "PATCH", "/api/core/items/#{uuid}", fn conn ->
        {:ok, body, conn} = Plug.Conn.read_body(conn)
        request_operations = JSON.decode!(body)

        assert request_operations == update_operations

        respond_with_json(conn, 200, item_fixture)
      end)

      {:ok, result} =
        uuid
        |> Item.update(update_operations)
        |> API.request(api)

      assert_valid_dspace_resource(result, "item")
      assert result["uuid"] == uuid
    end

    test "replaces entire item content", %{sham: sham, api: api} do
      uuid = "8f62713a-c495-467b-a918-2e392f781d2e"
      replacement_data = test_item_data(%{"name" => "Completely New Item"})
      item_fixture = load_fixture("fetch_item.json")

      Sham.expect_once(sham, "PUT", "/api/core/items/#{uuid}", fn conn ->
        {:ok, body, conn} = Plug.Conn.read_body(conn)
        request_data = JSON.decode!(body)

        assert request_data == replacement_data

        respond_with_json(conn, 200, item_fixture)
      end)

      {:ok, result} =
        uuid
        |> Item.replace(replacement_data)
        |> API.request(api)

      assert_valid_dspace_resource(result, "item")
      assert result["uuid"] == uuid
    end
  end

  describe "removing items" do
    test "deletes item successfully", %{sham: sham, api: api} do
      uuid = "8f62713a-c495-467b-a918-2e392f781d2e"

      Sham.expect_once(sham, "DELETE", "/api/core/items/#{uuid}", fn conn ->
        respond_with_json(conn, 204, "")
      end)

      {:ok, result} =
        uuid
        |> Item.delete()
        |> API.request(api)

      assert result == :ok
    end

    test "handles virtual metadata when deleting", %{sham: sham, api: api} do
      uuid = "8f62713a-c495-467b-a918-2e392f781d2e"

      Sham.expect_once(sham, "DELETE", "/api/core/items/#{uuid}", fn conn ->
        params = Plug.Conn.fetch_query_params(conn).query_params

        assert params["copyVirtualMetadata"] == "all"

        respond_with_json(conn, 204, "")
      end)

      {:ok, result} =
        uuid
        |> Item.delete(copy_virtual_metadata: :all)
        |> API.request(api)

      assert result == :ok
    end
  end

  describe "DOI registration" do
    test "registers DOI for existing item", %{sham: sham, api: api} do
      uuid = "8f62713a-c495-467b-a918-2e392f781d2e"
      expected_item_url = url(sham) <> "/api/core/items/#{uuid}"

      Sham.expect_once(sham, "POST", "/api/pid/identifiers", fn conn ->
        params = Plug.Conn.fetch_query_params(conn).query_params
        {:ok, body, conn} = Plug.Conn.read_body(conn)

        assert params["type"] == "doi"
        assert body == expected_item_url

        respond_with_json(conn, 201, ~s({"status": "created"}))
      end)

      {:ok, result} =
        uuid
        |> Item.register_doi()
        |> API.request(api)

      assert result["status"] == "created"
    end
  end

  describe "creating workspace items" do
    test "returns operation with correct path, method, and collection param" do
      collection_uuid = "05457c63-b392-4629-a373-f2d66ee9ee33"
      operation = Item.create_draft(parent: collection_uuid)

      assert operation.path == "/api/submission/workspaceitems"
      assert operation.http_method == :post
      assert Keyword.get(operation.params, :owningCollection) == collection_uuid
    end

    test "creates workspace item in specified collection", %{sham: sham, api: api} do
      collection_uuid = "05457c63-b392-4629-a373-f2d66ee9ee33"
      ws_fixture = load_fixture("workspace_item.json")

      Sham.expect_once(sham, "POST", "/api/submission/workspaceitems", fn conn ->
        params = Plug.Conn.fetch_query_params(conn).query_params
        assert params["owningCollection"] == collection_uuid
        respond_with_json(conn, 201, ws_fixture)
      end)

      {:ok, result} =
        [parent: collection_uuid]
        |> Item.create_draft()
        |> API.request(api)

      assert result["id"] == 239_514
      assert result["type"] == "workspaceitem"
      assert is_map(result["sections"])
    end

    test "requires a collection option" do
      assert_raise KeyError, fn ->
        Item.create_draft([])
      end
    end

    test "requires collection to be a non-empty binary" do
      assert_raise FunctionClauseError, fn ->
        Item.create_draft(parent: "")
      end
    end
  end

  describe "fetching workspace items" do
    test "returns operation with integer ID in path" do
      operation = Item.fetch_draft_by_id(239_514)

      assert operation.path == "/api/submission/workspaceitems/239514"
      assert operation.http_method == :get
    end

    test "fetches workspace item by integer ID", %{sham: sham, api: api} do
      ws_fixture = load_fixture("workspace_item.json")

      Sham.expect_once(sham, "GET", "/api/submission/workspaceitems/239514", fn conn ->
        respond_with_json(conn, 200, ws_fixture)
      end)

      {:ok, result} =
        239_514
        |> Item.fetch_draft_by_id()
        |> API.request(api)

      assert result["id"] == 239_514
      assert result["type"] == "workspaceitem"
      assert is_map(result["sections"])
    end
  end

  describe "fetching workspace items by item UUID" do
    test "returns operation with correct search path and uuid param" do
      item_uuid = "cd67ce0e-7f9a-42fc-b8e7-c8bb83ef58ca"
      operation = Item.fetch_draft(item_uuid)

      assert operation.path == "/api/submission/workspaceitems/search/item"
      assert Keyword.get(operation.params, :uuid) == item_uuid
    end

    test "finds workspace item for an item UUID", %{sham: sham, api: api} do
      item_uuid = "cd67ce0e-7f9a-42fc-b8e7-c8bb83ef58ca"
      ws_fixture = load_fixture("workspace_item.json")

      Sham.expect_once(sham, "GET", "/api/submission/workspaceitems/search/item", fn conn ->
        params = Plug.Conn.fetch_query_params(conn).query_params
        assert params["uuid"] == item_uuid
        respond_with_json(conn, 200, ws_fixture)
      end)

      {:ok, result} =
        item_uuid
        |> Item.fetch_draft()
        |> API.request(api)

      assert result["id"] == 239_514
      assert result["type"] == "workspaceitem"
    end

    test "returns nil when no workspace item exists for the item", %{sham: sham, api: api} do
      item_uuid = "cd67ce0e-7f9a-42fc-b8e7-c8bb83ef58ca"

      Sham.expect_once(sham, "GET", "/api/submission/workspaceitems/search/item", fn conn ->
        respond_with_json(conn, 204, "")
      end)

      {:error, reason} =
        item_uuid
        |> Item.fetch_draft()
        |> API.request(api)

      assert %Error{type: :not_found} = reason
    end
  end

  describe "updating workspace items" do
    test "returns operation with correct path, method, and patch body" do
      patch_ops = [
        %{"op" => "add", "path" => "/sections/publication/dc.title", "value" => [%{"value" => "New Title"}]}
      ]

      operation = Item.update_draft(239_514, patch_ops)

      assert operation.path == "/api/submission/workspaceitems/239514"
      assert operation.http_method == :patch
      assert operation.data == patch_ops
    end

    test "patches workspace item with JSON Patch operations", %{sham: sham, api: api} do
      ws_fixture = load_fixture("workspace_item.json")

      patch_ops = [
        %{"op" => "add", "path" => "/sections/publication/dc.title", "value" => [%{"value" => "Updated Title"}]}
      ]

      Sham.expect_once(sham, "PATCH", "/api/submission/workspaceitems/239514", fn conn ->
        {:ok, body, conn} = Plug.Conn.read_body(conn)
        request_ops = JSON.decode!(body)
        assert request_ops == patch_ops
        respond_with_json(conn, 200, ws_fixture)
      end)

      {:ok, result} =
        239_514
        |> Item.update_draft(patch_ops)
        |> API.request(api)

      assert result["id"] == 239_514
      assert result["type"] == "workspaceitem"
    end
  end

  describe "deleting workspace items" do
    test "returns operation with correct path and method" do
      operation = Item.delete_draft(239_514)

      assert operation.path == "/api/submission/workspaceitems/239514"
      assert operation.http_method == :delete
    end

    test "transformer returns :ok regardless of response" do
      operation = Item.delete_draft(239_514)

      assert operation.transformer.(nil) == :ok
    end

    test "deletes workspace item and associated item", %{sham: sham, api: api} do
      Sham.expect_once(sham, "DELETE", "/api/submission/workspaceitems/239514", fn conn ->
        respond_with_json(conn, 204, "")
      end)

      {:ok, result} =
        239_514
        |> Item.delete_draft()
        |> API.request(api)

      assert result == :ok
    end
  end

  describe "submitting workspace items to workflow" do
    test "returns operation with correct path, method, and content_type" do
      operation = Item.submit(1234)

      assert operation.path == "/api/workflow/workflowitems"
      assert operation.http_method == :post
      assert operation.content_type == :uri_list
    end

    test "before_step callback is set" do
      operation = Item.submit(1234)

      assert operation.before_step
      assert is_function(operation.before_step, 3)
    end

    test "single integer is normalized to a list in data" do
      operation = Item.submit(1234)

      assert operation.data == [1234]
    end

    test "list of integers is stored as-is in data" do
      operation = Item.submit([1234, 5678])

      assert operation.data == [1234, 5678]
    end

    test "before_step callback builds full workspace item URI for single ID", %{sham: sham, api: api} do
      ws_id = 1234
      expected_uri = url(sham) <> "/api/submission/workspaceitems/#{ws_id}"
      wf_fixture = load_fixture("workflow_item.json")

      Sham.expect_once(sham, "POST", "/api/workflow/workflowitems", fn conn ->
        {:ok, body, conn} = Plug.Conn.read_body(conn)

        assert body == expected_uri

        respond_with_json(conn, 201, wf_fixture)
      end)

      {:ok, result} =
        ws_id
        |> Item.submit()
        |> API.request(api)

      assert result["id"] == 1911
      assert result["step"] == "editstep"
      assert result["type"] == "workflowitem"
    end

    test "before_step callback builds multiple workspace item URIs newline-separated", %{sham: sham, api: api} do
      ws_ids = [1234, 5678]

      expected_body =
        Enum.map_join(ws_ids, "\n", fn id ->
          url(sham) <> "/api/submission/workspaceitems/#{id}"
        end)

      wf_fixture = load_fixture("workflow_item.json")

      Sham.expect_once(sham, "POST", "/api/workflow/workflowitems", fn conn ->
        {:ok, body, conn} = Plug.Conn.read_body(conn)

        assert body == expected_body

        respond_with_json(conn, 201, wf_fixture)
      end)

      {:ok, result} =
        ws_ids
        |> Item.submit()
        |> API.request(api)

      assert result["id"] == 1911
    end

    test "returns :published when 201 response body is empty (no workflow configured)", %{sham: sham, api: api} do
      Sham.expect_once(sham, "POST", "/api/workflow/workflowitems", fn conn ->
        respond_with_json(conn, 201, "")
      end)

      {:ok, result} =
        1234
        |> Item.submit()
        |> API.request(api)

      assert result == :published
    end
  end

  describe "fetching workflow items by id" do
    test "returns operation with integer ID in path" do
      operation = Item.fetch_workflow_by_id(1911)

      assert operation.path == "/api/workflow/workflowitems/1911"
      assert operation.http_method == :get
    end

    test "fetches workflow item by integer ID", %{sham: sham, api: api} do
      wf_fixture = load_fixture("workflow_item.json")

      Sham.expect_once(sham, "GET", "/api/workflow/workflowitems/1911", fn conn ->
        respond_with_json(conn, 200, wf_fixture)
      end)

      {:ok, result} =
        1911
        |> Item.fetch_workflow_by_id()
        |> API.request(api)

      assert result["id"] == 1911
      assert result["step"] == "editstep"
      assert result["type"] == "workflowitem"
    end
  end

  describe "fetching workflow items by item UUID" do
    test "returns operation with correct search path and uuid param" do
      item_uuid = "cd67ce0e-7f9a-42fc-b8e7-c8bb83ef58ca"
      operation = Item.fetch_workflow(item_uuid)

      assert operation.path == "/api/workflow/workflowitems/search/item"
      assert Keyword.get(operation.params, :uuid) == item_uuid
    end

    test "finds workflow item for an item UUID", %{sham: sham, api: api} do
      item_uuid = "cd67ce0e-7f9a-42fc-b8e7-c8bb83ef58ca"
      wf_fixture = load_fixture("workflow_item.json")

      Sham.expect_once(sham, "GET", "/api/workflow/workflowitems/search/item", fn conn ->
        params = Plug.Conn.fetch_query_params(conn).query_params
        assert params["uuid"] == item_uuid
        respond_with_json(conn, 200, wf_fixture)
      end)

      {:ok, result} =
        item_uuid
        |> Item.fetch_workflow()
        |> API.request(api)

      assert result["id"] == 1911
      assert result["step"] == "editstep"
      assert result["type"] == "workflowitem"
    end

    test "returns error when no workflow item exists for the item", %{sham: sham, api: api} do
      item_uuid = "cd67ce0e-7f9a-42fc-b8e7-c8bb83ef58ca"

      Sham.expect_once(sham, "GET", "/api/workflow/workflowitems/search/item", fn conn ->
        respond_with_json(conn, 204, "")
      end)

      {:error, reason} =
        item_uuid
        |> Item.fetch_workflow()
        |> API.request(api)

      assert %Error{type: :not_found} = reason
    end
  end

  describe "listing workflow items" do
    test "default operation hits GET /api/workflow/workflowitems" do
      operation = Item.list_in_workflow()

      assert operation.path == "/api/workflow/workflowitems"
      assert operation.http_method == :get
    end

    test "operation has correct transformer for workflowitems collection" do
      operation = Item.list_in_workflow()

      wf_fixture = parse_fixture("workflow_items.json")
      result = operation.transformer.(%DSpace.API.HTTP.Response{status: 200, body: wf_fixture})

      {items, metadata, _next} = result
      assert is_list(items)
      assert length(items) == 2
      assert is_map(metadata)
      assert Enum.at(items, 0)["type"] == "workflowitem"
    end

    test "with :submitter option hits the findBySubmitter endpoint" do
      submitter_uuid = "a1b2c3d4-e5f6-7890-abcd-ef1234567890"
      operation = Item.list_in_workflow(submitter: submitter_uuid)

      assert operation.path == "/api/workflow/workflowitems/search/findBySubmitter"
      assert Keyword.get(operation.params, :uuid) == submitter_uuid
    end

    test "pagination params are forwarded in default mode" do
      operation = Item.list_in_workflow(page: 2, size: 10)

      assert Keyword.get(operation.params, :page) == 2
      assert Keyword.get(operation.params, :size) == 10
    end

    test "pagination params are forwarded in submitter mode" do
      submitter_uuid = "a1b2c3d4-e5f6-7890-abcd-ef1234567890"
      operation = Item.list_in_workflow(submitter: submitter_uuid, page: 1, size: 5)

      assert operation.path == "/api/workflow/workflowitems/search/findBySubmitter"
      assert Keyword.get(operation.params, :uuid) == submitter_uuid
      assert Keyword.get(operation.params, :page) == 1
      assert Keyword.get(operation.params, :size) == 5
    end

    test "lists workflow items with pagination", %{sham: sham, api: api} do
      wf_list_fixture = load_fixture("workflow_items.json")

      Sham.expect_once(sham, "GET", "/api/workflow/workflowitems", fn conn ->
        respond_with_json(conn, 200, wf_list_fixture)
      end)

      {:ok, result} = API.request(Item.list_in_workflow(), api)

      {items, metadata, next_url} = result
      assert_valid_paginated_response({items, metadata, next_url})
      assert length(items) == 2

      first_item = Enum.at(items, 0)
      assert first_item["id"] == 1911
      assert first_item["type"] == "workflowitem"
    end

    test "filters by submitter UUID", %{sham: sham, api: api} do
      submitter_uuid = "a1b2c3d4-e5f6-7890-abcd-ef1234567890"
      wf_list_fixture = load_fixture("workflow_items.json")

      Sham.expect_once(sham, "GET", "/api/workflow/workflowitems/search/findBySubmitter", fn conn ->
        params = Plug.Conn.fetch_query_params(conn).query_params
        assert params["uuid"] == submitter_uuid
        respond_with_json(conn, 200, wf_list_fixture)
      end)

      {:ok, result} =
        [submitter: submitter_uuid]
        |> Item.list_in_workflow()
        |> API.request(api)

      {items, _metadata, _next} = result
      assert length(items) == 2
    end
  end

  describe "deleting workflow items" do
    test "returns operation with correct path and method" do
      operation = Item.delete_from_workflow(1911)

      assert operation.path == "/api/workflow/workflowitems/1911"
      assert operation.http_method == :delete
    end

    test "without :expunge option does not include expunge query param" do
      operation = Item.delete_from_workflow(1911)

      refute Keyword.has_key?(operation.params, :expunge)
    end

    test "with expunge: true includes expunge query param set to \"true\"" do
      operation = Item.delete_from_workflow(1911, expunge: true)

      assert Keyword.get(operation.params, :expunge) == "true"
    end

    test "transformer returns :ok regardless of response" do
      operation = Item.delete_from_workflow(1911)

      assert operation.transformer.(nil) == :ok
    end

    test "deletes workflow item and returns it to workspace", %{sham: sham, api: api} do
      Sham.expect_once(sham, "DELETE", "/api/workflow/workflowitems/1911", fn conn ->
        respond_with_json(conn, 204, "")
      end)

      {:ok, result} =
        1911
        |> Item.delete_from_workflow()
        |> API.request(api)

      assert result == :ok
    end

    test "expunge permanently deletes the workflow item", %{sham: sham, api: api} do
      Sham.expect_once(sham, "DELETE", "/api/workflow/workflowitems/1911", fn conn ->
        params = Plug.Conn.fetch_query_params(conn).query_params
        assert params["expunge"] == "true"
        respond_with_json(conn, 204, "")
      end)

      {:ok, result} =
        1911
        |> Item.delete_from_workflow(expunge: true)
        |> API.request(api)

      assert result == :ok
    end
  end

  # Private helpers

  defp test_item_data(overrides \\ %{}) do
    base_data = %{
      "name" => "Test Item",
      "metadata" => %{
        "dc.title" => [%{"value" => "Test Item"}]
      }
    }

    Map.merge(base_data, overrides)
  end
end
