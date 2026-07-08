defmodule DSpace.API.CollectionTest do
  use DSpace.API.Case, async: true

  alias DSpace.API.Collection

  describe "retrieving a collection by UUID" do
    test "returns collection when it exists", %{sham: sham, api: api} do
      uuid = "577d7908-a2a1-4fc4-a1b1-56f691eae28a"
      collection_fixture = load_fixture("fetch_collection.json")

      Sham.expect_once(sham, "GET", "/api/core/collections/#{uuid}", fn conn ->
        respond_with_json(conn, 200, collection_fixture)
      end)

      {:ok, result} =
        uuid
        |> Collection.fetch()
        |> API.request(api)

      assert_valid_dspace_resource(result, "collection", ["name", "handle", "metadata"])
      assert result["uuid"] == uuid
    end
  end

  describe "retrieving multiple collections" do
    test "lists collections with pagination support", %{sham: sham, api: api} do
      collections_fixture = load_fixture("fetch_collections.json")

      Sham.expect_once(sham, "GET", "/api/core/collections", fn conn ->
        respond_with_json(conn, 200, collections_fixture)
      end)

      {:ok, result} = API.request(Collection.list(), api)

      {collections, metadata, next_url} = result
      assert_valid_paginated_response({collections, metadata, next_url})
      assert length(collections) == 7

      first_collection = Enum.at(collections, 0)
      assert_valid_dspace_resource(first_collection, "collection", ["name", "metadata"])

      assert metadata["page"]["size"] == 20
      assert metadata["page"]["totalElements"] == 7
      assert is_nil(next_url)
    end

    test "supports custom pagination parameters", %{sham: sham, api: api} do
      Sham.expect_once(sham, "GET", "/api/core/collections", fn conn ->
        params = Plug.Conn.fetch_query_params(conn).query_params
        assert params["page"] == "2"
        assert params["size"] == "10"

        respond_with_json(conn, 200, ~s({
          "_embedded": {"collections": []},
          "_links": {},
          "page": {"size": 10, "totalElements": 0, "totalPages": 0, "number": 2}
        }))
      end)

      {:ok, result} =
        [page: 2, size: 10]
        |> Collection.list()
        |> API.request(api)

      {_collections, metadata, _next_url} = result
      assert metadata["page"]["number"] == 2
      assert metadata["page"]["size"] == 10
    end
  end

  describe "creating collections" do
    test "creates collection within parent community", %{sham: sham, api: api} do
      parent_uuid = "parent-community-uuid"
      collection_data = test_collection_data(%{"name" => "New Collection"})
      collection_fixture = load_fixture("fetch_collection.json")

      Sham.expect_once(sham, "POST", "/api/core/collections", fn conn ->
        params = Plug.Conn.fetch_query_params(conn).query_params
        {:ok, body, conn} = Plug.Conn.read_body(conn)
        request_data = JSON.decode!(body)

        assert params["parent"] == parent_uuid
        assert request_data["name"] == "New Collection"

        respond_with_json(conn, 201, collection_fixture)
      end)

      {:ok, result} =
        collection_data
        |> Collection.create(parent: parent_uuid)
        |> API.request(api)

      assert_valid_dspace_resource(result, "collection")
    end

    test "requires parent community for creation" do
      collection_data = test_collection_data()

      assert_raise FunctionClauseError, fn ->
        Collection.create(collection_data, [])
      end
    end
  end

  describe "modifying existing collections" do
    test "updates collection with patch operations", %{sham: sham, api: api} do
      uuid = "577d7908-a2a1-4fc4-a1b1-56f691eae28a"
      update_operations = test_update_operations("dc.title", "Updated Community")

      Sham.expect_once(sham, "PATCH", "/api/core/collections/#{uuid}", fn conn ->
        {:ok, body, conn} = Plug.Conn.read_body(conn)
        request_data = JSON.decode!(body)

        operation = List.first(request_data)
        assert operation["op"] == "replace"
        assert operation["path"] == "/metadata/dc.title/0/value"
        assert operation["value"] == %{"value" => "Updated Community"}

        respond_with_json(conn, 200, ~s({
          "uuid": "577d7908-a2a1-4fc4-a1b1-56f691eae28a",
          "name": "Updated Publications Collection",
          "type": "collection"
        }))
      end)

      {:ok, result} =
        uuid
        |> Collection.update(update_operations)
        |> API.request(api)

      assert result["uuid"] == uuid
      assert result["name"] == "Updated Publications Collection"
    end

    test "replaces entire collection content", %{sham: sham, api: api} do
      uuid = "577d7908-a2a1-4fc4-a1b1-56f691eae28a"
      collection_data = test_collection_data(%{"name" => "Replaced Collection"})

      Sham.expect_once(sham, "PUT", "/api/core/collections/#{uuid}", fn conn ->
        {:ok, body, conn} = Plug.Conn.read_body(conn)
        request_data = JSON.decode!(body)

        assert request_data["name"] == "Replaced Collection"

        respond_with_json(conn, 200, ~s({
          "uuid": "577d7908-a2a1-4fc4-a1b1-56f691eae28a",
          "name": "Replaced Collection",
          "type": "collection"
        }))
      end)

      {:ok, result} = uuid |> Collection.replace(collection_data) |> API.request(api)

      assert result["uuid"] == uuid
      assert result["name"] == "Replaced Collection"
    end
  end

  describe "removing collections" do
    test "deletes collection successfully", %{sham: sham, api: api} do
      uuid = "577d7908-a2a1-4fc4-a1b1-56f691eae28a"

      Sham.expect_once(sham, "DELETE", "/api/core/collections/#{uuid}", fn conn ->
        respond_with_json(conn, 204, "")
      end)

      {:ok, result} =
        uuid
        |> Collection.delete()
        |> API.request(api)

      assert result == :ok
    end
  end

  describe "retrieving collection items" do
    test "retrieves items from collection", %{sham: sham, api: api} do
      uuid = "577d7908-a2a1-4fc4-a1b1-56f691eae28a"
      items_fixture = load_fixture("fetch_items.json")

      Sham.expect_once(sham, "GET", "/api/core/collections/#{uuid}/mappedItems", fn conn ->
        params = Plug.Conn.fetch_query_params(conn).query_params
        assert params["page"] == "1"
        assert params["size"] == "20"

        respond_with_json(conn, 200, items_fixture)
      end)

      {:ok, result} =
        uuid
        |> Collection.list_items(page: 1, size: 20)
        |> API.request(api)

      {items, metadata, next_url} = result
      assert_valid_paginated_response({items, metadata, next_url})
      assert items != []

      first_item = Enum.at(items, 0)
      assert Map.has_key?(first_item, "uuid")
      assert Map.has_key?(first_item, "name")
      assert first_item["type"] == "item"
    end
  end

  describe "searching for collections" do
    test "finds all collections when no search criteria provided", %{sham: sham, api: api} do
      search_fixture = load_fixture("search_objects.json")

      Sham.expect_once(sham, "GET", "/api/discover/search/objects", fn conn ->
        params = Plug.Conn.fetch_query_params(conn).query_params

        refute Map.has_key?(params, "query")
        assert params["dsoType"] == "Collection"
        assert params["configuration"] == "communityOrCollection"

        respond_with_json(conn, 200, search_fixture)
      end)

      {:ok, result} = API.request(Collection.find(), api)

      {objects, _metadata, _next_url} = result
      assert is_list(objects)
    end

    test "searches collections with query term", %{sham: sham, api: api} do
      search_term = "publications"
      search_fixture = load_fixture("search_objects.json")

      Sham.expect_once(sham, "GET", "/api/discover/search/objects", fn conn ->
        params = Plug.Conn.fetch_query_params(conn).query_params

        assert params["query"] == search_term
        assert params["dsoType"] == "Collection"
        assert params["configuration"] == "communityOrCollection"

        respond_with_json(conn, 200, search_fixture)
      end)

      {:ok, result} =
        [query: search_term]
        |> Collection.find()
        |> API.request(api)

      {objects, _metadata, _next_url} = result
      assert objects != []

      first_result = Enum.at(objects, 0)
      assert Map.has_key?(first_result, "uuid")
      assert Map.has_key?(first_result, "name")
      assert Map.has_key?(first_result, "handle")
    end

    test "applies filters and pagination to search", %{sham: sham, api: api} do
      options = [
        query: "research",
        page: 0,
        size: 10,
        scope: "community-uuid",
        filters: [%{filter: "title", operator: "contains", value: "data"}]
      ]

      Sham.expect_once(sham, "GET", "/api/discover/search/objects", fn conn ->
        params = Plug.Conn.fetch_query_params(conn).query_params

        assert params["query"] == "research"
        assert params["page"] == "0"
        assert params["size"] == "10"
        assert params["scope"] == "community-uuid"
        assert params["f.title"] == "data,contains"
        assert params["dsoType"] == "Collection"

        respond_with_json(conn, 200, ~s({
          "_embedded": {
            "searchResult": {
              "_embedded": {"objects": []},
              "_links": {"next": {"href": null}}
            }
          }
        }))
      end)

      {:ok, _result} =
        options
        |> Collection.find()
        |> API.request(api)
    end
  end

  # Private helpers

  defp test_collection_data(overrides \\ %{}) do
    base_data = %{
      "name" => "Test Collection",
      "metadata" => %{
        "dc.title" => [%{"value" => "Test Collection"}]
      }
    }

    Map.merge(base_data, overrides)
  end
end
