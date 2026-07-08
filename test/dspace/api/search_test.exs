defmodule DSpace.API.SearchTest do
  use DSpace.API.Case, async: true

  alias DSpace.API
  alias DSpace.API.HTTP.Response
  alias DSpace.API.Operation
  alias DSpace.API.Search

  test "query with empty query string raises FunctionClauseError" do
    assert_raise FunctionClauseError, fn ->
      Search.query("")
    end
  end

  describe "parameter handling" do
    test "query/1 with keyword list containing query" do
      operation = Search.query(query: "test", scope: "some-uuid")

      assert operation.params[:query] == "test"
      assert operation.params[:scope] == "some-uuid"
    end

    test "query/1 with keyword list without query" do
      operation = Search.query(scope: "some-uuid", configuration: "workspace")

      assert operation.params[:scope] == "some-uuid"
      assert operation.params[:configuration] == "workspace"
      refute Map.has_key?(Map.new(operation.params), :query)
    end

    test "query/1 with scope parameter" do
      uuid = "community-uuid-123"
      operation = Search.query(scope: uuid)

      assert operation.params[:scope] == uuid
    end

    test "query/1 with configuration parameter" do
      config = "workspace"
      operation = Search.query(configuration: config)

      assert operation.params[:configuration] == config
    end

    test "query/1 with special configurations" do
      for config <- ["workspace", "workflow"] do
        operation = Search.query(configuration: config)
        assert operation.params[:configuration] == config
      end
    end

    test "query/1 with custom configuration" do
      config = "custom-discovery-config"
      operation = Search.query(configuration: config)

      assert operation.params[:configuration] == config
    end

    test "query/1 with both scope and configuration" do
      uuid = "collection-uuid-456"
      config = "workflow"

      operation = Search.query(scope: uuid, configuration: config)

      assert operation.params[:scope] == uuid
      assert operation.params[:configuration] == config
    end

    test "query/1 with query, scope, and configuration" do
      query_text = "test search"
      uuid = "community-uuid-789"
      config = "workspace"

      operation = Search.query(query: query_text, scope: uuid, configuration: config)

      assert operation.params[:query] == query_text
      assert operation.params[:scope] == uuid
      assert operation.params[:configuration] == config
    end

    test "query/1 with single filter using equals operator" do
      operation = Search.query(filters: [%{filter: "title", operator: "equals", value: "test"}])

      assert List.keyfind(operation.params, "f.title", 0) == {"f.title", "test,equals"}
    end

    test "query/1 with single filter using contains operator" do
      operation =
        Search.query(filters: [%{filter: "author", operator: "contains", value: "smith"}])

      assert List.keyfind(operation.params, "f.author", 0) == {"f.author", "smith,contains"}
    end

    test "query/1 with single filter using authority operator" do
      operation =
        Search.query(filters: [%{filter: "author", operator: "authority", value: "123-uuid"}])

      assert List.keyfind(operation.params, "f.author", 0) == {"f.author", "123-uuid,authority"}
    end

    test "query/1 with multiple different filters" do
      filters = [
        %{filter: "title", operator: "contains", value: "test"},
        %{filter: "author", operator: "equals", value: "smith"}
      ]

      operation = Search.query(filters: filters)

      assert List.keyfind(operation.params, "f.title", 0) == {"f.title", "test,contains"}
      assert List.keyfind(operation.params, "f.author", 0) == {"f.author", "smith,equals"}
    end

    test "query/1 with multiple filters on same filter" do
      filters = [
        %{filter: "subject", operator: "equals", value: "science"},
        %{filter: "subject", operator: "notequals", value: "math"}
      ]

      operation = Search.query(filters: filters)

      # Should handle multiple filters on same field by creating multiple parameters
      params = operation.params

      subject_filters =
        Enum.filter(params, fn {key, _value} -> String.starts_with?(key, "f.subject") end)

      assert length(subject_filters) == 2
    end

    test "query/1 with all supported operators" do
      operators = ["equals", "notequals", "contains", "notcontains", "authority", "notauthority"]

      for operator <- operators do
        operation = Search.query(filters: [%{filter: "title", operator: operator, value: "test"}])
        assert List.keyfind(operation.params, "f.title", 0) == {"f.title", "test,#{operator}"}
      end
    end

    test "query/1 with filters combined with other parameters" do
      operation =
        Search.query(
          query: "search term",
          scope: "collection-uuid",
          configuration: "workspace",
          filters: [%{filter: "author", operator: "contains", value: "doe"}]
        )

      assert operation.params[:query] == "search term"
      assert operation.params[:scope] == "collection-uuid"
      assert operation.params[:configuration] == "workspace"
      assert List.keyfind(operation.params, "f.author", 0) == {"f.author", "doe,contains"}
    end

    test "query/1 with hierarchical filter (subject)" do
      operation =
        Search.query(filters: [%{filter: "subject", operator: "equals", value: "Computer Science"}])

      assert List.keyfind(operation.params, "f.subject", 0) ==
               {"f.subject", "Computer Science,equals"}
    end

    test "query/1 with date filter" do
      operation =
        Search.query(filters: [%{filter: "dateIssued", operator: "equals", value: "2023"}])

      assert List.keyfind(operation.params, "f.dateIssued", 0) == {"f.dateIssued", "2023,equals"}
    end

    test "query/1 with single sort field" do
      operation = Search.query(query: "test", sort: "title")

      assert operation.params[:sort] == "title,asc"
    end

    test "query/1 with sort field and direction" do
      operation = Search.query(query: "test", sort: {"title", :desc})

      assert operation.params[:sort] == "title,desc"
    end

    test "query/1 with sort field and asc direction" do
      operation = Search.query(query: "test", sort: {"dateIssued", :asc})

      assert operation.params[:sort] == "dateIssued,asc"
    end

    test "query/1 with atom sort field" do
      operation = Search.query(query: "test", sort: :title)

      assert operation.params[:sort] == "title,asc"
    end

    test "facet operations support sort parameter" do
      operation = Search.fetch_facet_values("author", sort: {"count", :desc})

      assert operation.params[:sort] == "count,desc"
    end
  end

  describe "facet operations" do
    test "fetch_facets/1 returns JSON operation" do
      operation = Search.fetch_facets(configuration: "default")
      assert %Operation.JSON{} = operation
    end

    test "fetch_facets/1 has correct path" do
      operation = Search.fetch_facets()
      assert operation.path == "/api/discover/search/facets"
    end

    test "fetch_facets/1 accepts same parameters as search" do
      operation =
        Search.fetch_facets(
          query: "test",
          scope: "collection-uuid",
          configuration: "workspace",
          filters: [%{filter: "author", operator: "contains", value: "smith"}]
        )

      assert operation.params[:query] == "test"
      assert operation.params[:scope] == "collection-uuid"
      assert operation.params[:configuration] == "workspace"
      assert List.keyfind(operation.params, "f.author", 0) == {"f.author", "smith,contains"}
    end

    test "fetch_facets/1 has facet transformer" do
      operation = Search.fetch_facets()
      assert is_function(operation.transformer, 1)
    end

    test "fetch_facet_values/2 returns JSON operation" do
      operation = Search.fetch_facet_values("author")
      assert %Operation.JSON{} = operation
    end

    test "fetch_facet_values/2 has correct path" do
      operation = Search.fetch_facet_values("subject")
      assert operation.path == "/api/discover/search/facets/subject"
    end

    test "fetch_facet_values/2 accepts search parameters" do
      operation =
        Search.fetch_facet_values("author",
          query: "smith",
          page: 1,
          size: 20,
          scope: "collection-uuid"
        )

      assert operation.params[:query] == "smith"
      assert operation.params[:page] == 1
      assert operation.params[:size] == 20
      assert operation.params[:scope] == "collection-uuid"
    end

    test "fetch_facet_values/2 has facet values transformer" do
      operation = Search.fetch_facet_values("author")
      assert is_function(operation.transformer, 1)
    end
  end

  describe "transformers" do
    test "search transformer extracts data and comprehensive metadata", %{
      sham: sham,
      api: api
    } do
      search_fixture = load_fixture("search_objects.json")

      Sham.expect_once(sham, "GET", "/api/discover/search/objects", fn conn ->
        respond_with_json(conn, 200, search_fixture)
      end)

      {:ok, result} = API.request(Search.query("test"), api)

      {data, meta, next_url} = result

      # Data
      assert length(data) == 1
      first_item = Enum.at(data, 0)
      assert_valid_dspace_resource(first_item, "item")

      # Meta
      assert is_map(meta)
      assert Map.has_key?(meta, "scope")
      assert Map.has_key?(meta, "query")
      assert Map.has_key?(meta, "appliedFilters")
      assert Map.has_key?(meta, "sort")
      assert Map.has_key?(meta, "configuration")
      assert Map.has_key?(meta, "facets")
      assert is_list(meta["facets"])
      assert length(meta["facets"]) == 5
      assert Map.has_key?(meta, "page")
      assert Map.has_key?(meta, "_links")
      search_links = meta["_links"]
      assert search_links["next"]["href"] =~ "page=1&size=1"

      # Next
      assert is_binary(next_url)
    end

    test "query/1 has search result transformer" do
      operation = Search.query("test")
      assert is_function(operation.transformer, 1)
    end

    test "facet transformer extracts from _embedded.facets" do
      response = %Response{
        body: %{
          "_embedded" => %{
            "facets" => [
              %{"name" => "author", "facetType" => "text"},
              %{"name" => "subject", "facetType" => "text"}
            ]
          }
        }
      }

      operation = Search.fetch_facets()
      {result, _meta, _next} = operation.transformer.(response)

      assert length(result) == 2
      assert Enum.any?(result, &(&1["name"] == "author"))
      assert Enum.any?(result, &(&1["name"] == "subject"))
    end

    test "facet values transformer extracts from _embedded.values" do
      response = %Response{
        body: %{
          "_embedded" => %{
            "values" => [
              %{"label" => "Smith, John", "count" => 5},
              %{"label" => "Doe, Jane", "count" => 3}
            ]
          }
        }
      }

      operation = Search.fetch_facet_values("author")
      {result, _meta, _next} = operation.transformer.(response)

      assert length(result) == 2
      assert Enum.any?(result, &(&1["label"] == "Smith, John"))
      assert Enum.any?(result, &(&1["count"] == 5))
    end

    test "facet transformer returns empty list for missing facets" do
      response = %Response{
        body: %{"_embedded" => %{}}
      }

      operation = Search.fetch_facets()
      {result, _meta, _next} = operation.transformer.(response)

      assert result == []
    end

    test "facet values transformer returns empty list for missing values" do
      response = %Response{
        body: %{}
      }

      operation = Search.fetch_facet_values("author")
      {result, _meta, _next} = operation.transformer.(response)

      assert result == []
    end
  end

  describe "integration verification" do
    setup do
      api = %API{http_impl: {TestHelper.HTTP, []}}
      {:ok, api: api}
    end

    test "query searches for items with text query", %{api: api} do
      query = "test search"

      expected_response = %{
        "_embedded" => %{
          "searchResult" => %{
            "_embedded" => %{"objects" => []}
          }
        }
      }

      operation = Search.query(query)
      {:ok, _result} = Operation.perform(operation, api, test_return_body: expected_response)

      assert_received {:http_request, options}
      assert to_string(options[:url]) =~ "/api/discover/search/objects"
      assert options[:method] == :get
      assert options[:params][:query] == query
    end

    test "query searches within specific collection or community scope", %{api: api} do
      scope_uuid = "test-scope-uuid"

      expected_response = %{
        "_embedded" => %{"searchResult" => %{"_embedded" => %{"objects" => []}}}
      }

      operation = Search.query(scope: scope_uuid)
      {:ok, _result} = Operation.perform(operation, api, test_return_body: expected_response)

      assert_received {:http_request, options}
      assert to_string(options[:url]) =~ "/api/discover/search/objects"
      assert options[:method] == :get
      assert options[:params][:scope] == scope_uuid
    end

    test "query searches using discovery configuration", %{api: api} do
      config = "workspace"

      expected_response = %{
        "_embedded" => %{"searchResult" => %{"_embedded" => %{"objects" => []}}}
      }

      operation = Search.query(configuration: config)
      {:ok, _result} = Operation.perform(operation, api, test_return_body: expected_response)

      assert_received {:http_request, options}
      assert to_string(options[:url]) =~ "/api/discover/search/objects"
      assert options[:method] == :get
      assert options[:params][:configuration] == config
    end

    test "query applies metadata filters to search results", %{api: api} do
      filters = [%{filter: "author", operator: "contains", value: "smith"}]

      expected_response = %{
        "_embedded" => %{"searchResult" => %{"_embedded" => %{"objects" => []}}}
      }

      operation = Search.query(filters: filters)
      {:ok, _result} = Operation.perform(operation, api, test_return_body: expected_response)

      assert_received {:http_request, options}
      assert to_string(options[:url]) =~ "/api/discover/search/objects"
      assert options[:method] == :get
      assert List.keyfind(options[:params], "f.author", 0) == {"f.author", "smith,contains"}
    end

    test "query sorts search results by specified field", %{api: api} do
      expected_response = %{
        "_embedded" => %{"searchResult" => %{"_embedded" => %{"objects" => []}}}
      }

      operation = Search.query(query: "test", sort: "title")
      {:ok, _result} = Operation.perform(operation, api, test_return_body: expected_response)

      assert_received {:http_request, options}
      assert options[:params][:sort] == "title,asc"
    end

    test "query sorts search results in descending order", %{api: api} do
      expected_response = %{
        "_embedded" => %{"searchResult" => %{"_embedded" => %{"objects" => []}}}
      }

      operation = Search.query(query: "test", sort: {"dateIssued", :desc})
      {:ok, _result} = Operation.perform(operation, api, test_return_body: expected_response)

      assert_received {:http_request, options}
      assert options[:params][:sort] == "dateIssued,desc"
    end

    test "fetch_facet_values sorts facet values by count", %{api: api} do
      expected_response = %{"_embedded" => %{"values" => []}}

      operation = Search.fetch_facet_values("author", sort: {"count", :desc})
      {:ok, _result} = Operation.perform(operation, api, test_return_body: expected_response)

      assert_received {:http_request, options}
      assert options[:params][:sort] == "count,desc"
    end
  end

  describe "resource type isolation" do
    alias DSpace.API.Collection
    alias DSpace.API.Community
    alias DSpace.API.Item
    alias DSpace.API.User

    test "Item.find returns operation with correct type filter" do
      search_term = "elixir programming"

      operation = Item.find(query: search_term)

      assert operation.path == "/api/discover/search/objects"
      assert operation.params[:query] == search_term
      assert operation.params[:dsoType] == "Item"
    end

    test "Collection.find returns operation with correct type filter" do
      search_term = "digital archives"

      operation = Collection.find(query: search_term)

      assert operation.path == "/api/discover/search/objects"
      assert operation.params[:query] == search_term
      assert operation.params[:dsoType] == "Collection"
      assert operation.params[:configuration] == "communityOrCollection"
    end

    test "Community.find returns operation with correct type filter" do
      search_term = "research community"

      operation = Community.find(query: search_term)

      assert operation.path == "/api/discover/search/objects"
      assert operation.params[:query] == search_term
      assert operation.params[:dsoType] == "Community"
      assert operation.params[:configuration] == "communityOrCollection"
    end

    test "User.find uses different endpoint for user metadata search" do
      search_term = "john doe"

      operation = User.find(query: search_term)

      assert operation.path == "/api/eperson/epersons/search/byMetadata"
      assert operation.params[:query] == search_term
    end
  end

  describe "common search features across resources" do
    alias DSpace.API.Collection
    alias DSpace.API.Community
    alias DSpace.API.Item
    alias DSpace.API.User

    test "all resource find operations support streaming" do
      item_op = Item.find(query: "test")
      collection_op = Collection.find(query: "test")
      community_op = Community.find(query: "test")
      user_op = User.find(query: "test")

      assert item_op.stream_impl
      assert collection_op.stream_impl
      assert community_op.stream_impl
      assert user_op.stream_impl
    end

    test "all resource find operations support pagination options" do
      options = [query: "test", page: 1, size: 10]

      item_op = Item.find(options)
      collection_op = Collection.find(options)
      community_op = Community.find(options)
      user_op = User.find(options)

      # Discovery search resources support pagination
      assert item_op.params[:page] == 1
      assert item_op.params[:size] == 10
      assert collection_op.params[:page] == 1
      assert collection_op.params[:size] == 10
      assert community_op.params[:page] == 1
      assert community_op.params[:size] == 10

      # User metadata search also supports pagination
      assert user_op.params[:page] == 1
      assert user_op.params[:size] == 10
    end

    test "all resource find/1 operations (no search term) support streaming" do
      item_op = Item.find([])
      collection_op = Collection.find([])
      community_op = Community.find([])
      user_op = User.find([])

      assert item_op.stream_impl
      assert collection_op.stream_impl
      assert community_op.stream_impl
      assert user_op.stream_impl
    end

    test "all resource find/1 operations use correct endpoints and type filters" do
      item_op = Item.find([])
      collection_op = Collection.find([])
      community_op = Community.find([])
      user_op = User.find([])

      # Discovery search resources use search endpoint with type filters
      assert item_op.path == "/api/discover/search/objects"
      assert item_op.params[:dsoType] == "Item"

      assert collection_op.path == "/api/discover/search/objects"
      assert collection_op.params[:dsoType] == "Collection"
      assert collection_op.params[:configuration] == "communityOrCollection"

      assert community_op.path == "/api/discover/search/objects"
      assert community_op.params[:dsoType] == "Community"
      assert community_op.params[:configuration] == "communityOrCollection"

      # User uses specialized metadata search endpoint
      assert user_op.path == "/api/eperson/epersons/search/byMetadata"
    end

    test "all resource find/1 operations do not include query parameter" do
      item_op = Item.find([])
      collection_op = Collection.find([])
      community_op = Community.find([])
      user_op = User.find([])

      refute Keyword.has_key?(item_op.params, :query)
      refute Keyword.has_key?(collection_op.params, :query)
      refute Keyword.has_key?(community_op.params, :query)
      refute Keyword.has_key?(user_op.params, :query)
    end

    test "all resource find/1 operations pass through pagination options" do
      options = [page: 2, size: 15]

      item_op = Item.find(options)
      collection_op = Collection.find(options)
      community_op = Community.find(options)
      user_op = User.find(options)

      # All operations should include pagination parameters
      assert item_op.params[:page] == 2
      assert item_op.params[:size] == 15
      assert collection_op.params[:page] == 2
      assert collection_op.params[:size] == 15
      assert community_op.params[:page] == 2
      assert community_op.params[:size] == 15
      assert user_op.params[:page] == 2
      assert user_op.params[:size] == 15
    end
  end
end
