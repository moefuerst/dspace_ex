defmodule DSpace.QueryExternalTest do
  @moduledoc """
  Tests that query the API for information and do not require credentials.

  These tests assume the target system has at least one existing community, collection, item, etc.

  These tests can run async.
  """

  use DSpace.ExternalCase, async: true

  alias DSpace.API
  alias DSpace.API.Collection
  alias DSpace.API.Community
  alias DSpace.API.Item
  alias DSpace.API.Search

  setup do
    client = DSpace.ExternalCase.dspace_test_api()
    %{client: client}
  end

  describe "core endpoints" do
    test "lists toplevel communities", %{client: client} do
      toplevel_communities =
        Community.list_toplevel()
        |> API.stream!(client)
        |> Stream.take(3)

      for result <- toplevel_communities do
        assert Map.has_key?(result, "uuid")
        assert Map.fetch!(result, "type") == "community"
      end
    end

    test "lists communities", %{client: client} do
      communities =
        Community.list()
        |> API.stream!(client)
        |> Stream.take(3)

      for result <- communities do
        assert Map.has_key?(result, "uuid")
        assert Map.fetch!(result, "type") == "community"
      end
    end

    test "fetches a community", %{client: client} do
      {result, _meta, _next} = API.request!(Community.list(), client)
      [first_community | _] = result
      community_uuid = Map.fetch!(first_community, "uuid")

      community =
        community_uuid
        |> Community.fetch()
        |> API.request!(client)

      assert Map.has_key?(community, "uuid")
      assert Map.fetch!(community, "type") == "community"
    end

    test "lists collections of a community", %{client: client} do
      {result, _meta, _next} = API.request!(Community.list(), client)
      [first_community | _] = result
      community_uuid = Map.fetch!(first_community, "uuid")

      collections =
        community_uuid
        |> Community.list_collections()
        |> API.stream!(client)
        |> Stream.take(3)

      for result <- collections do
        assert Map.has_key?(result, "uuid")
        assert Map.fetch!(result, "type") == "collection"
      end
    end

    test "lists collections", %{client: client} do
      collections =
        Collection.list()
        |> API.stream!(client)
        |> Stream.take(3)

      for result <- collections do
        assert Map.has_key?(result, "uuid")
        assert Map.fetch!(result, "type") == "collection"
      end
    end

    test "fetches a collection", %{client: client} do
      {result, _meta, _next} = API.request!(Collection.list(), client)
      [first_collection | _] = result
      collection_uuid = Map.fetch!(first_collection, "uuid")

      collection =
        collection_uuid
        |> Collection.fetch()
        |> API.request!(client)

      assert Map.has_key?(collection, "uuid")
      assert Map.fetch!(collection, "type") == "collection"
    end

    test "lists items of a collection", %{client: client} do
      {result, _meta, _next} = API.request!(Collection.list(), client)
      [first_collection | _] = result
      collection_uuid = Map.fetch!(first_collection, "uuid")

      items =
        collection_uuid
        |> Collection.list_items()
        |> API.stream!(client)
        |> Stream.take(3)

      for result <- items do
        assert Map.has_key?(result, "uuid")
        assert Map.fetch!(result, "type") == "item"
      end
    end

    test "fetches parent community of a collection", %{client: client} do
      {result, _meta, _next} = API.request!(Collection.list(), client)
      [first_collection | _] = result
      collection_uuid = Map.fetch!(first_collection, "uuid")

      parent_community =
        collection_uuid
        |> Collection.fetch_parent_community()
        |> API.request!(client)

      assert Map.has_key?(parent_community, "uuid")
      assert Map.fetch!(parent_community, "type") == "community"
    end
  end

  describe "search endpoint" do
    test "default search configuration", %{client: client} do
      %{body: result} =
        [configuration: :default]
        |> Search.query()
        |> API.request!(client, transform: false)

      objects = get_in(result, ["_embedded", "searchResult", "_embedded", "objects"])

      assert Map.fetch!(result, "type") == "discover"
      assert Map.fetch!(result, "configuration") == "default"
      assert objects != []
    end

    test "finds communities", %{client: client} do
      communities =
        Community.find()
        |> API.stream!(client)
        |> Stream.take(3)

      for result <- communities do
        assert Map.has_key?(result, "uuid")
        assert Map.fetch!(result, "type") == "community"
      end
    end

    test "finds collections", %{client: client} do
      collections =
        Collection.find()
        |> API.stream!(client)
        |> Stream.take(3)

      for result <- collections do
        assert Map.has_key?(result, "uuid")
        assert Map.fetch!(result, "type") == "collection"
      end
    end

    test "finds items", %{client: client} do
      items =
        Item.find()
        |> API.stream!(client)
        |> Stream.take(3)

      for result <- items do
        assert Map.has_key?(result, "uuid")
        assert Map.fetch!(result, "type") == "item"
      end
    end

    test "scoped search", %{client: client} do
      %{"uuid" => uuid} =
        Community.find()
        |> API.stream!(client)
        |> Stream.take(1)
        |> Enum.at(0)

      result =
        [scope: uuid]
        |> Search.query()
        |> API.stream!(client)
        |> Stream.take(1)
        |> Enum.at(0)

      assert Map.has_key?(result, "uuid")
      assert Map.has_key?(result, "type")
    end
  end
end
