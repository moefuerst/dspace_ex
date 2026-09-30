defmodule DSpace.API.TransformTest do
  use ExUnit.Case, async: true

  alias DSpace.API.Error
  alias DSpace.API.HTTP.Response
  alias DSpace.API.Model.MetadataValue
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

  describe "get/3" do
    test "extracts the requested field and uses the caller's default for absent fields" do
      response = %Response{body: %{"status" => "restricted", "name" => "Report"}}

      assert Transform.get(response, "status", "unknown") == "restricted"
      assert Transform.get(response, "missing", "unknown") == "unknown"
    end
  end

  describe "access_token_from_response/1" do
    test "extracts the bearer token from the authorization header" do
      response = %Response{headers: %{"authorization" => ["Bearer access-token"]}}

      assert Transform.access_token_from_response(response) == {:ok, "access-token"}
    end

    test "reports a response validation error when the bearer token is absent" do
      response = %Response{headers: %{"content-type" => ["application/json"]}}

      result = Transform.access_token_from_response(response)

      assert {:error, %Error{type: :api_unexpected_payload, response: ^response}} = result
    end
  end

  describe "csrf_token_from_response/1" do
    test "prefers the CSRF response header over the cookie" do
      response = %Response{
        headers: %{
          "dspace-xsrf-token" => ["header-token"],
          "set-cookie" => ["DSPACE-XSRF-COOKIE=cookie-token; Path=/"]
        }
      }

      assert Transform.csrf_token_from_response(response) == {:ok, "header-token"}
    end

    test "finds the CSRF cookie among unrelated cookies and cookie attributes" do
      response = %Response{
        headers: %{
          "set-cookie" => [
            "JSESSIONID=session; Path=/; HttpOnly",
            " DSPACE-XSRF-COOKIE=csrf-token; Path=/; Secure"
          ]
        }
      }

      assert Transform.csrf_token_from_response(response) == {:ok, "csrf-token"}
    end

    test "reports a validation error when cookies contain no CSRF token" do
      response = %Response{headers: %{"set-cookie" => ["JSESSIONID=session; Path=/"]}}

      assert {:error, %Error{type: :api_unexpected_payload, response: ^response}} =
               Transform.csrf_token_from_response(response)
    end

    test "reports a validation error when no token headers are returned" do
      response = %Response{headers: %{}}

      assert {:error, %Error{type: :api_unexpected_payload, response: ^response}} =
               Transform.csrf_token_from_response(response)
    end

    test "extracts both tokens from a login response" do
      response = %Response{
        headers: %{
          "authorization" => ["Bearer access-token"],
          "set-cookie" => ["DSPACE-XSRF-COOKIE=csrf-token; Path=/"]
        }
      }

      assert Transform.tokens_from_response(response) == {:ok, {"access-token", "csrf-token"}}
    end
  end

  describe "tokens_from_response/1" do
    test "does not accept a login response containing only one of the required tokens" do
      for headers <- [
            %{"authorization" => ["Bearer access-token"]},
            %{"dspace-xsrf-token" => ["csrf-token"]}
          ] do
        response = %Response{headers: headers}

        assert {:error, %Error{type: :api_unexpected_payload, response: ^response}} =
                 Transform.tokens_from_response(response)
      end
    end
  end

  describe "token_from_response/1" do
    test "extracts a short-lived token from the body" do
      response = %Response{body: %{"token" => "download-token"}}

      assert Transform.token_from_response(response) == {:ok, "download-token"}
    end

    test "reports a validation error when the short-lived token is missing" do
      response = %Response{body: %{}}

      assert {:error, %Error{type: :api_unexpected_payload, response: ^response}} =
               Transform.token_from_response(response)
    end
  end

  describe "not_found_on_no_content/2" do
    test "normalizes no-content responses and preserves the response context" do
      response = %Response{status: 204}

      assert %Error{type: :not_found, status: 404, message: "Resource not found", response: ^response} =
               Transform.not_found_on_no_content(response)

      assert %Error{message: "No draft found"} =
               Transform.not_found_on_no_content(response, "No draft found")
    end

    test "preserves a found resource" do
      response = %Response{status: 200, body: %{"uuid" => "item-id"}}

      assert Transform.not_found_on_no_content(response) == %{"uuid" => "item-id"}
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

    test "supports a custom continuation path instead of the default next link" do
      response = %{
        "items" => [%{"id" => "1"}],
        "continuation" => %{"url" => "https://example.com/custom-next"},
        "_links" => %{"next" => %{"href" => "https://example.com/default-next"}}
      }

      assert {[%{"id" => "1"}], _meta, "https://example.com/custom-next"} =
               Transform.transform_collection(response,
                 extract: ["items"],
                 next: ["continuation", "url"]
               )
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

  describe "casting response values" do
    test "casts both single and repeated metadata values without losing their keys or order" do
      metadata = %{
        "dc.title" => [%{"value" => "First"}, %{"value" => "Second"}],
        "dc.description" => %{"value" => "Summary"}
      }

      assert %{
               "dc.title" => [%MetadataValue{value: "First"}, %MetadataValue{value: "Second"}],
               "dc.description" => %MetadataValue{value: "Summary"}
             } = Transform.cast_map(metadata, MetadataValue)
    end

    test "normalizes datetime offsets while preserving unparseable response values" do
      assert Transform.datetime("2026-09-30T12:00:00+02:00") == ~U[2026-09-30 10:00:00Z]
      assert Transform.datetime("not-a-datetime") == "not-a-datetime"
      assert Transform.datetime(~U[2026-09-30 10:00:00Z]) == ~U[2026-09-30 10:00:00Z]
      assert Transform.datetime(nil) == nil
    end

    test "preserves an already parsed URI" do
      uri = URI.new!("https://repository.example/items/item-id")

      assert Transform.uri(uri) == uri
    end
  end
end
