defmodule DSpace.API.TransformTest do
  use ExUnit.Case, async: true

  alias DSpace.API.HTTP.Response
  alias DSpace.API.Transform

  describe "from_response/1" do
    test "extracts body from Response struct" do
      response = %Response{body: %{"id" => "123", "name" => "Test Item"}}

      result = Transform.from_response(response)

      assert result == %{"id" => "123", "name" => "Test Item"}
    end

    test "returns empty map for Response with nil body" do
      response = %Response{body: nil}

      result = Transform.from_response(response)

      assert result == %{}
    end

    test "returns empty map for non-Response input" do
      result = Transform.from_response("invalid")

      assert result == %{}
    end

    test "handles Response with non-map body" do
      response = %Response{body: "text response"}

      result = Transform.from_response(response)

      assert result == %{}
    end
  end

  describe "transform/2" do
    test "applies identity transformer to single resource" do
      resource = %{"id" => "123", "name" => "Test Item"}

      result = Transform.transform(resource, [])

      assert result == [%{"id" => "123", "name" => "Test Item"}]
    end

    test "applies custom transformer to single resource" do
      resource = %{"id" => "123", "name" => "Test Item"}
      uppercase_name = fn item -> Map.put(item, "name", String.upcase(item["name"])) end

      result = Transform.transform(resource, transform: uppercase_name)

      assert result == [%{"id" => "123", "name" => "TEST ITEM"}]
    end

    test "extracts nested resources via path" do
      response = %{
        "_embedded" => %{
          "items" => [
            %{"id" => "1", "name" => "Item 1"},
            %{"id" => "2", "name" => "Item 2"}
          ]
        }
      }

      result = Transform.transform(response, extract: ["_embedded", "items"])

      assert length(result) == 2
      assert Enum.at(result, 0) == %{"id" => "1", "name" => "Item 1"}
      assert Enum.at(result, 1) == %{"id" => "2", "name" => "Item 2"}
    end

    test "handles missing extraction paths gracefully" do
      response = %{"data" => "something"}

      result = Transform.transform(response, extract: ["_embedded", "items"])

      assert result == []
    end

    test "applies transformer to each extracted resource" do
      response = %{
        "_embedded" => %{
          "items" => [
            %{"id" => "1", "name" => "item 1"},
            %{"id" => "2", "name" => "item 2"}
          ]
        }
      }

      uppercase_name = fn item -> Map.put(item, "name", String.upcase(item["name"])) end

      result =
        Transform.transform(response,
          extract: ["_embedded", "items"],
          transform: uppercase_name
        )

      assert length(result) == 2
      assert Enum.at(result, 0) == %{"id" => "1", "name" => "ITEM 1"}
      assert Enum.at(result, 1) == %{"id" => "2", "name" => "ITEM 2"}
    end

    test "works with Response struct input" do
      response = %Response{
        body: %{
          "_embedded" => %{
            "items" => [%{"id" => "1", "name" => "Item 1"}]
          }
        }
      }

      result = Transform.transform(response, extract: ["_embedded", "items"])

      assert result == [%{"id" => "1", "name" => "Item 1"}]
    end
  end

  describe "transform_collection/2" do
    test "returns three-element tuple with data, meta, and next" do
      response = %{
        "page" => %{"size" => 20, "totalElements" => 100},
        "_embedded" => %{
          "items" => [
            %{"id" => "1", "name" => "Item 1"},
            %{"id" => "2", "name" => "Item 2"}
          ]
        },
        "_links" => %{
          "next" => %{"href" => "http://example.com/api/core/items?page=2"}
        }
      }

      {data, meta, next} =
        Transform.transform_collection(response,
          extract: ["_embedded", "items"],
          next: ["_links", "next", "href"]
        )

      assert length(data) == 2
      assert Enum.at(data, 0) == %{"id" => "1", "name" => "Item 1"}
      assert Enum.at(data, 1) == %{"id" => "2", "name" => "Item 2"}

      assert meta == %{
               "page" => %{"size" => 20, "totalElements" => 100},
               "_links" => %{"next" => %{"href" => "http://example.com/api/core/items?page=2"}}
             }

      assert next == "http://example.com/api/core/items?page=2"
    end

    test "extracts metadata excluding _embedded and _links" do
      response = %{
        "page" => %{"size" => 20, "totalElements" => 100, "number" => 1},
        "facets" => [%{"name" => "author", "values" => ["Smith", "Jones"]}],
        "sort" => %{"field" => "name", "direction" => "asc"},
        "_embedded" => %{"items" => []},
        "_links" => %{"self" => %{"href" => "http://example.com"}}
      }

      {_data, meta, _next} =
        Transform.transform_collection(response,
          extract: ["_embedded", "items"],
          next: ["_links", "next", "href"]
        )

      expected_meta = %{
        "page" => %{"size" => 20, "totalElements" => 100, "number" => 1},
        "facets" => [%{"name" => "author", "values" => ["Smith", "Jones"]}],
        "sort" => %{"field" => "name", "direction" => "asc"},
        "_links" => %{"self" => %{"href" => "http://example.com"}}
      }

      assert meta == expected_meta
    end

    test "handles missing next link by returning nil" do
      response = %{
        "_embedded" => %{"items" => [%{"id" => "1"}]},
        "_links" => %{"self" => %{"href" => "http://example.com"}}
      }

      {_data, _meta, next} =
        Transform.transform_collection(response,
          extract: ["_embedded", "items"],
          next: ["_links", "next", "href"]
        )

      assert next == nil
    end

    test "applies custom transformer to each item" do
      response = %{
        "_embedded" => %{
          "items" => [
            %{"id" => "1", "name" => "item 1"},
            %{"id" => "2", "name" => "item 2"}
          ]
        }
      }

      uppercase_name = fn item -> Map.put(item, "name", String.upcase(item["name"])) end

      {data, _meta, _next} =
        Transform.transform_collection(response,
          extract: ["_embedded", "items"],
          next: ["_links", "next", "href"],
          transform: uppercase_name
        )

      assert length(data) == 2
      assert Enum.at(data, 0) == %{"id" => "1", "name" => "ITEM 1"}
      assert Enum.at(data, 1) == %{"id" => "2", "name" => "ITEM 2"}
    end

    test "handles empty collections" do
      response = %{
        "page" => %{"totalElements" => 0},
        "_embedded" => %{"items" => []},
        "_links" => %{"self" => %{"href" => "http://example.com"}}
      }

      {data, meta, next} =
        Transform.transform_collection(response,
          extract: ["_embedded", "items"],
          next: ["_links", "next", "href"]
        )

      assert data == []

      assert meta == %{
               "page" => %{"totalElements" => 0},
               "_links" => %{"self" => %{"href" => "http://example.com"}}
             }

      assert next == nil
    end

    test "handles missing extraction path" do
      response = %{
        "page" => %{"totalElements" => 0}
      }

      {data, meta, next} =
        Transform.transform_collection(response,
          extract: ["_embedded", "items"],
          next: ["_links", "next", "href"]
        )

      assert data == []
      assert meta == %{"page" => %{"totalElements" => 0}}
      assert next == nil
    end

    test "works with Response struct input" do
      response = %Response{
        body: %{
          "_embedded" => %{"items" => [%{"id" => "1", "name" => "Item 1"}]},
          "_links" => %{"next" => %{"href" => "http://example.com/next"}}
        }
      }

      {data, _meta, next} =
        Transform.transform_collection(response,
          extract: ["_embedded", "items"],
          next: ["_links", "next", "href"]
        )

      assert data == [%{"id" => "1", "name" => "Item 1"}]
      assert next == "http://example.com/next"
    end
  end
end
