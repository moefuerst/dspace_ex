defmodule DSpace.API.CommunityTest do
  use DSpace.API.Case, async: true

  alias DSpace.API.Community

  describe "retrieving a community by UUID" do
    test "returns community when it exists", %{sham: sham, api: api} do
      uuid = "7669c72a-3f2a-451f-a3b9-9210e7a4c02f"
      community_fixture = load_fixture("fetch_community.json")

      Sham.expect_once(sham, "GET", "/api/core/communities/#{uuid}", fn conn ->
        respond_with_json(conn, 200, community_fixture)
      end)

      {:ok, result} =
        uuid
        |> Community.fetch()
        |> API.request(api)

      assert_valid_dspace_resource(result, "community", ["name", "handle", "metadata"])
      assert result["uuid"] == uuid
      assert result["name"] == "OR2017 - Demonstration"
      assert result["handle"] == "10673/11"
    end
  end

  describe "retrieving multiple communities" do
    test "lists communities with pagination support", %{sham: sham, api: api} do
      communities_fixture = load_fixture("fetch_communities.json")

      Sham.expect_once(sham, "GET", "/api/core/communities", fn conn ->
        respond_with_json(conn, 200, communities_fixture)
      end)

      {:ok, result} = API.request(Community.list(), api)

      {communities, metadata, next_url} = result
      assert_valid_paginated_response({communities, metadata, next_url})
      assert communities != []

      first_community = Enum.at(communities, 0)
      assert_valid_dspace_resource(first_community, "community", ["name", "metadata"])
    end

    test "supports custom pagination parameters", %{sham: sham, api: api} do
      Sham.expect_once(sham, "GET", "/api/core/communities", fn conn ->
        params = Plug.Conn.fetch_query_params(conn).query_params
        assert params["page"] == "2"
        assert params["size"] == "10"

        respond_with_json(conn, 200, ~s({
          "_embedded": {"communities": []},
          "_links": {},
          "page": {"size": 10, "totalElements": 0, "totalPages": 0, "number": 2}
        }))
      end)

      {:ok, result} =
        [page: 2, size: 10]
        |> Community.list()
        |> API.request(api)

      {_communities, metadata, _next_url} = result
      assert metadata["page"]["number"] == 2
      assert metadata["page"]["size"] == 10
    end

    test "retrieves top-level communities", %{sham: sham, api: api} do
      communities_fixture = load_fixture("fetch_communities.json")

      Sham.expect_once(sham, "GET", "/api/core/communities/search/top", fn conn ->
        params = Plug.Conn.fetch_query_params(conn).query_params
        assert params["page"] == "1"
        assert params["size"] == "20"

        respond_with_json(conn, 200, communities_fixture)
      end)

      {:ok, result} =
        [page: 1, size: 20]
        |> Community.list_toplevel()
        |> API.request(api)

      {communities, metadata, next_url} = result
      assert_valid_paginated_response({communities, metadata, next_url})
      assert is_list(communities)
    end
  end

  describe "searching for communities" do
    test "finds all communities when no search criteria provided", %{sham: sham, api: api} do
      search_fixture = load_fixture("search_objects.json")

      Sham.expect_once(sham, "GET", "/api/discover/search/objects", fn conn ->
        params = Plug.Conn.fetch_query_params(conn).query_params

        assert params["dsoType"] == "Community"
        assert params["configuration"] == "communityOrCollection"
        refute Map.has_key?(params, "query")

        respond_with_json(conn, 200, search_fixture)
      end)

      {:ok, result} = API.request(Community.find(), api)

      {objects, _metadata, _next_url} = result
      assert is_list(objects)
    end

    test "searches communities by query term", %{sham: sham, api: api} do
      search_term = "research community"
      search_fixture = load_fixture("search_objects.json")

      Sham.expect_once(sham, "GET", "/api/discover/search/objects", fn conn ->
        params = Plug.Conn.fetch_query_params(conn).query_params

        assert params["query"] == search_term
        assert params["dsoType"] == "Community"
        assert params["configuration"] == "communityOrCollection"

        respond_with_json(conn, 200, search_fixture)
      end)

      {:ok, result} =
        [query: search_term]
        |> Community.find()
        |> API.request(api)

      {objects, _metadata, _next_url} = result
      assert is_list(objects)
    end

    test "applies filters and pagination to search", %{sham: sham, api: api} do
      search_fixture = load_fixture("search_objects.json")

      options = [
        page: 1,
        size: 5,
        scope: "parent-community-uuid",
        filters: [%{filter: "subject", operator: "contains", value: "science"}]
      ]

      Sham.expect_once(sham, "GET", "/api/discover/search/objects", fn conn ->
        params = Plug.Conn.fetch_query_params(conn).query_params

        assert params["dsoType"] == "Community"
        assert params["configuration"] == "communityOrCollection"
        assert params["page"] == "1"
        assert params["size"] == "5"
        assert params["scope"] == "parent-community-uuid"
        assert params["f.subject"] == "science,contains"

        respond_with_json(conn, 200, search_fixture)
      end)

      {:ok, _result} = options |> Community.find() |> API.request(api)
    end
  end

  describe "creating communities" do
    test "creates top-level community without parent", %{sham: sham, api: api} do
      community_data = test_community_data(%{"name" => "New Top Level Community"})
      community_fixture = load_fixture("fetch_community.json")

      Sham.expect_once(sham, "POST", "/api/core/communities", fn conn ->
        params = Plug.Conn.fetch_query_params(conn).query_params
        {:ok, body, conn} = Plug.Conn.read_body(conn)
        request_data = JSON.decode!(body)

        refute Map.has_key?(params, "parent")
        assert request_data["name"] == "New Top Level Community"

        respond_with_json(conn, 201, community_fixture)
      end)

      {:ok, result} =
        community_data
        |> Community.create()
        |> API.request(api)

      assert_valid_dspace_resource(result, "community")
      assert result["uuid"] == "7669c72a-3f2a-451f-a3b9-9210e7a4c02f"
    end

    test "creates subcommunity with parent", %{sham: sham, api: api} do
      parent_uuid = "parent-community-uuid"
      community_data = test_community_data(%{"name" => "Sub Community"})
      community_fixture = load_fixture("fetch_community.json")

      Sham.expect_once(sham, "POST", "/api/core/communities", fn conn ->
        params = Plug.Conn.fetch_query_params(conn).query_params
        {:ok, body, conn} = Plug.Conn.read_body(conn)
        request_data = JSON.decode!(body)

        assert params["parent"] == parent_uuid
        assert request_data["name"] == "Sub Community"

        respond_with_json(conn, 201, community_fixture)
      end)

      {:ok, result} =
        community_data
        |> Community.create(parent: parent_uuid)
        |> API.request(api)

      assert_valid_dspace_resource(result, "community")
      assert result["uuid"] == "7669c72a-3f2a-451f-a3b9-9210e7a4c02f"
    end
  end

  describe "modifying existing communities" do
    test "updates community with patch operations", %{sham: sham, api: api} do
      uuid = "7669c72a-3f2a-451f-a3b9-9210e7a4c02f"
      update_operations = test_update_operations("dc.title", "Updated Community")
      community_fixture = load_fixture("fetch_community.json")

      Sham.expect_once(sham, "PATCH", "/api/core/communities/#{uuid}", fn conn ->
        {:ok, body, conn} = Plug.Conn.read_body(conn)
        request_operations = JSON.decode!(body)

        assert request_operations == update_operations

        respond_with_json(conn, 200, community_fixture)
      end)

      {:ok, result} =
        uuid
        |> Community.update(update_operations)
        |> API.request(api)

      assert_valid_dspace_resource(result, "community")
      assert result["uuid"] == uuid
    end

    test "replaces entire community content", %{sham: sham, api: api} do
      uuid = "7669c72a-3f2a-451f-a3b9-9210e7a4c02f"
      replacement_data = test_community_data(%{"name" => "Replaced Community"})
      community_fixture = load_fixture("fetch_community.json")

      Sham.expect_once(sham, "PUT", "/api/core/communities/#{uuid}", fn conn ->
        {:ok, body, conn} = Plug.Conn.read_body(conn)
        request_data = JSON.decode!(body)

        assert request_data == replacement_data

        respond_with_json(conn, 200, community_fixture)
      end)

      {:ok, result} =
        uuid
        |> Community.replace(replacement_data)
        |> API.request(api)

      assert_valid_dspace_resource(result, "community")
      assert result["uuid"] == uuid
    end
  end

  describe "removing communities" do
    test "deletes community successfully", %{sham: sham, api: api} do
      uuid = "7669c72a-3f2a-451f-a3b9-9210e7a4c02f"

      Sham.expect_once(sham, "DELETE", "/api/core/communities/#{uuid}", fn conn ->
        respond_with_json(conn, 204, "")
      end)

      {:ok, result} =
        uuid
        |> Community.delete()
        |> API.request(api)

      assert result == :ok
    end
  end

  describe "retrieving related resources" do
    test "retrieves collections within community", %{sham: sham, api: api} do
      uuid = "community-uuid"
      collections_fixture = load_fixture("fetch_collections.json")

      Sham.expect_once(sham, "GET", "/api/core/communities/#{uuid}/collections", fn conn ->
        params = Plug.Conn.fetch_query_params(conn).query_params
        assert params["page"] == "1"
        assert params["size"] == "5"

        respond_with_json(conn, 200, collections_fixture)
      end)

      {:ok, result} =
        uuid
        |> Community.list_collections(page: 1, size: 5)
        |> API.request(api)

      {collections, metadata, next_url} = result
      assert_valid_paginated_response({collections, metadata, next_url})
      assert is_list(collections)
    end

    test "retrieves subcommunities within community", %{sham: sham, api: api} do
      uuid = "community-uuid"
      communities_fixture = load_fixture("fetch_communities.json")

      Sham.expect_once(sham, "GET", "/api/core/communities/#{uuid}/subcommunities", fn conn ->
        params = Plug.Conn.fetch_query_params(conn).query_params
        assert params["page"] == "2"
        assert params["size"] == "15"

        respond_with_json(conn, 200, communities_fixture)
      end)

      {:ok, result} =
        uuid
        |> Community.list_subcommunities(page: 2, size: 15)
        |> API.request(api)

      {subcommunities, metadata, next_url} = result
      assert_valid_paginated_response({subcommunities, metadata, next_url})
      assert is_list(subcommunities)
    end

    test "retrieves parent community", %{sham: sham, api: api} do
      uuid = "child-community-uuid"
      community_fixture = load_fixture("fetch_community.json")

      Sham.expect_once(
        sham,
        "GET",
        "/api/core/communities/#{uuid}/parentCommunity",
        fn conn ->
          respond_with_json(conn, 200, community_fixture)
        end
      )

      {:ok, result} =
        uuid
        |> Community.fetch_parent()
        |> API.request(api)

      assert_valid_dspace_resource(result, "community")
      assert result["uuid"] == "7669c72a-3f2a-451f-a3b9-9210e7a4c02f"
    end

    test "handles missing parent community", %{sham: sham, api: api} do
      uuid = "top-level-community-uuid"

      Sham.expect_once(
        sham,
        "GET",
        "/api/core/communities/#{uuid}/parentCommunity",
        fn conn ->
          respond_with_json(conn, 204, "")
        end
      )

      {:ok, result} =
        uuid
        |> Community.fetch_parent()
        |> API.request(api)

      assert result == %{}
    end
  end

  # Private helpers

  defp test_community_data(overrides) do
    base_data = %{
      "name" => "Test Community",
      "metadata" => %{
        "dc.title" => [%{"value" => "Test Community"}]
      }
    }

    Map.merge(base_data, overrides)
  end
end
