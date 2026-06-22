defmodule DSpace.API.MetadataTest do
  use DSpace.API.Case, async: true

  alias DSpace.API.Metadata

  describe "retrieving metadata fields" do
    test "fetches a single field by ID", %{bypass: bypass, api: api} do
      field_id = "8"
      field_fixture = load_fixture("fetch_metadata_field.json")

      Bypass.expect_once(bypass, "GET", "/api/core/metadatafields/#{field_id}", fn conn ->
        respond_with_json(conn, 200, field_fixture)
      end)

      {:ok, result} = field_id |> Metadata.fetch_field() |> API.request(api)

      assert result["type"] == "metadatafield"
      assert result["id"] == 8
      assert result["element"] == "contributor"
      assert result["qualifier"] == "advisor"
    end

    test "lists all metadata fields with pagination", %{bypass: bypass, api: api} do
      fields_fixture = load_fixture("fetch_metadata_fields.json")

      Bypass.expect_once(bypass, "GET", "/api/core/metadatafields", fn conn ->
        respond_with_json(conn, 200, fields_fixture)
      end)

      {:ok, result} = API.request(Metadata.list_fields(), api)

      {fields, metadata, next_url} = result
      assert_valid_paginated_response({fields, metadata, next_url})
      assert length(fields) == 3

      first_field = Enum.at(fields, 0)
      assert first_field["type"] == "metadatafield"
      assert first_field["element"] == "contributor"

      assert metadata["page"]["totalElements"] == 85
      assert is_binary(next_url)
    end

    test "lists fields filtered by schema", %{bypass: bypass, api: api} do
      schema_prefix = "dc"
      fields_fixture = load_fixture("fetch_metadata_fields.json")

      Bypass.expect_once(bypass, "GET", "/api/core/metadatafields/search/bySchema", fn conn ->
        params = Plug.Conn.fetch_query_params(conn).query_params
        assert params["schema"] == schema_prefix

        respond_with_json(conn, 200, fields_fixture)
      end)

      {:ok, result} = [schema: schema_prefix] |> Metadata.list_fields() |> API.request(api)

      {fields, _metadata, _next_url} = result
      assert is_list(fields)
      assert length(fields) == 3
    end

    test "supports custom pagination parameters for field listing", %{bypass: bypass, api: api} do
      Bypass.expect_once(bypass, "GET", "/api/core/metadatafields", fn conn ->
        params = Plug.Conn.fetch_query_params(conn).query_params
        assert params["page"] == "1"
        assert params["size"] == "10"

        custom_response = ~s({
          "_embedded": {"metadatafields": []},
          "_links": {},
          "page": {"size": 10, "totalElements": 0, "totalPages": 0, "number": 1}
        })

        respond_with_json(conn, 200, custom_response)
      end)

      {:ok, result} = [page: 1, size: 10] |> Metadata.list_fields() |> API.request(api)

      {_fields, metadata, _next_url} = result
      assert metadata["page"]["number"] == 1
      assert metadata["page"]["size"] == 10
    end
  end

  describe "searching metadata fields" do
    test "finds fields by exact name", %{bypass: bypass, api: api} do
      field_name = "dc.contributor.author"
      fields_fixture = load_fixture("fetch_metadata_fields.json")

      Bypass.expect_once(bypass, "GET", "/api/core/metadatafields/search/byFieldName", fn conn ->
        params = Plug.Conn.fetch_query_params(conn).query_params
        assert params["name"] == field_name

        respond_with_json(conn, 200, fields_fixture)
      end)

      {:ok, result} = [name: field_name] |> Metadata.find_fields() |> API.request(api)

      assert is_map(result)
    end

    test "finds fields by schema prefix", %{bypass: bypass, api: api} do
      schema_prefix = "dc"
      fields_fixture = load_fixture("fetch_metadata_fields.json")

      Bypass.expect_once(bypass, "GET", "/api/core/metadatafields/search/byFieldName", fn conn ->
        params = Plug.Conn.fetch_query_params(conn).query_params
        assert params["schema"] == schema_prefix

        respond_with_json(conn, 200, fields_fixture)
      end)

      {:ok, result} = [schema: schema_prefix] |> Metadata.find_fields() |> API.request(api)

      assert is_map(result)
    end

    test "finds fields by element and qualifier", %{bypass: bypass, api: api} do
      element = "contributor"
      qualifier = "author"
      fields_fixture = load_fixture("fetch_metadata_fields.json")

      Bypass.expect_once(bypass, "GET", "/api/core/metadatafields/search/byFieldName", fn conn ->
        params = Plug.Conn.fetch_query_params(conn).query_params
        assert params["element"] == element
        assert params["qualifier"] == qualifier

        respond_with_json(conn, 200, fields_fixture)
      end)

      {:ok, result} =
        [element: element, qualifier: qualifier] |> Metadata.find_fields() |> API.request(api)

      assert is_map(result)
    end

    test "finds fields by query term", %{bypass: bypass, api: api} do
      query_term = "dc.ti"
      fields_fixture = load_fixture("fetch_metadata_fields.json")

      Bypass.expect_once(bypass, "GET", "/api/core/metadatafields/search/byFieldName", fn conn ->
        params = Plug.Conn.fetch_query_params(conn).query_params
        assert params["query"] == query_term

        respond_with_json(conn, 200, fields_fixture)
      end)

      {:ok, result} = [query: query_term] |> Metadata.find_fields() |> API.request(api)

      assert is_map(result)
    end

    test "supports pagination in field search", %{bypass: bypass, api: api} do
      Bypass.expect_once(bypass, "GET", "/api/core/metadatafields/search/byFieldName", fn conn ->
        params = Plug.Conn.fetch_query_params(conn).query_params
        assert params["query"] == "contributor"
        assert params["page"] == "0"
        assert params["size"] == "5"

        respond_with_json(conn, 200, ~s({"_embedded": {"metadatafields": []}}))
      end)

      {:ok, _result} =
        [query: "contributor", page: 0, size: 5] |> Metadata.find_fields() |> API.request(api)
    end
  end

  describe "creating metadata fields" do
    test "creates field with scope note and validates payload transformation", %{
      bypass: bypass,
      api: api
    } do
      schema_id = "schema-123"

      field_data =
        test_field_data(%{
          element: "subject",
          qualifier: "keyword",
          scope_note: "A custom scope note for testing"
        })

      field_fixture = load_fixture("fetch_metadata_field.json")

      Bypass.expect_once(bypass, "POST", "/api/core/metadatafields", fn conn ->
        params = Plug.Conn.fetch_query_params(conn).query_params
        {:ok, body, conn} = Plug.Conn.read_body(conn)
        request_data = Jason.decode!(body)

        assert params["schemaId"] == schema_id
        assert request_data["element"] == "subject"
        assert request_data["qualifier"] == "keyword"
        assert request_data["scopeNote"] == "A custom scope note for testing"

        respond_with_json(conn, 201, field_fixture)
      end)

      {:ok, result} = field_data |> Metadata.create_field(schema_id: schema_id) |> API.request(api)

      assert result["type"] == "metadatafield"
    end

    test "creates field without scope note and handles nil values", %{bypass: bypass, api: api} do
      schema_id = "schema-456"

      field_data = %{
        element: "title",
        qualifier: "alternative"
      }

      field_fixture = load_fixture("fetch_metadata_field.json")

      Bypass.expect_once(bypass, "POST", "/api/core/metadatafields", fn conn ->
        params = Plug.Conn.fetch_query_params(conn).query_params
        {:ok, body, conn} = Plug.Conn.read_body(conn)
        request_data = Jason.decode!(body)

        assert params["schemaId"] == schema_id
        assert request_data["element"] == "title"
        assert request_data["qualifier"] == "alternative"
        assert request_data["scopeNote"] == nil

        respond_with_json(conn, 201, field_fixture)
      end)

      {:ok, result} = field_data |> Metadata.create_field(schema_id: schema_id) |> API.request(api)

      assert result["type"] == "metadatafield"
    end

    test "transforms field payload from atoms to strings with scopeNote mapping" do
      field_data = %{
        element: "subject",
        qualifier: "keyword",
        scope_note: "Test scope note"
      }

      operation = Metadata.create_field(field_data, schema_id: "1")

      expected_data = %{
        "element" => "subject",
        "qualifier" => "keyword",
        "scopeNote" => "Test scope note"
      }

      assert operation.data == expected_data
    end
  end

  describe "modifying metadata fields" do
    test "updates field scope note", %{bypass: bypass, api: api} do
      field_id = "8"
      updates = %{scope_note: "Updated scope note"}
      field_fixture = load_fixture("fetch_metadata_field.json")

      Bypass.expect_once(bypass, "PUT", "/api/core/metadatafields/#{field_id}", fn conn ->
        {:ok, body, conn} = Plug.Conn.read_body(conn)
        request_data = Jason.decode!(body)

        assert request_data["scopeNote"] == "Updated scope note"

        respond_with_json(conn, 200, field_fixture)
      end)

      {:ok, result} = field_id |> Metadata.update_field(updates) |> API.request(api)

      assert result["type"] == "metadatafield"
    end

    test "handles mixed key types in field updates" do
      field_id = "8"

      updates = %{
        "element" => "title",
        qualifier: "alternative",
        scope_note: "Mixed keys test"
      }

      operation = Metadata.update_field(field_id, updates)

      expected_data = %{
        "element" => "title",
        "qualifier" => "alternative",
        "scopeNote" => "Mixed keys test"
      }

      assert operation.data == expected_data
    end
  end

  describe "removing metadata fields" do
    test "deletes field successfully", %{bypass: bypass, api: api} do
      field_id = "8"

      Bypass.expect_once(bypass, "DELETE", "/api/core/metadatafields/#{field_id}", fn conn ->
        respond_with_json(conn, 204, "")
      end)

      {:ok, result} = field_id |> Metadata.delete_field() |> API.request(api)

      assert result == :ok
    end
  end

  describe "retrieving metadata schemas" do
    test "fetches a single schema by ID", %{bypass: bypass, api: api} do
      schema_id = "1"
      schema_fixture = load_fixture("fetch_metadata_schema.json")

      Bypass.expect_once(bypass, "GET", "/api/core/metadataschemas/#{schema_id}", fn conn ->
        respond_with_json(conn, 200, schema_fixture)
      end)

      {:ok, result} = schema_id |> Metadata.fetch_schema() |> API.request(api)

      assert result["type"] == "metadataschema"
      assert result["id"] == 1
      assert result["prefix"] == "dc"
      assert result["namespace"] == "http://dublincore.org/documents/dcmi-terms/"
    end

    test "lists all metadata schemas with pagination", %{bypass: bypass, api: api} do
      schemas_fixture = load_fixture("fetch_metadata_schemas.json")

      Bypass.expect_once(bypass, "GET", "/api/core/metadataschemas", fn conn ->
        respond_with_json(conn, 200, schemas_fixture)
      end)

      {:ok, result} = API.request(Metadata.list_schemas(), api)

      {schemas, metadata, next_url} = result
      assert_valid_paginated_response({schemas, metadata, next_url})
      assert length(schemas) == 3

      first_schema = Enum.at(schemas, 0)
      assert first_schema["type"] == "metadataschema"
      assert first_schema["prefix"] == "dc"

      assert metadata["page"]["totalElements"] == 3
      assert is_nil(next_url)
    end

    test "supports custom pagination parameters for schema listing", %{bypass: bypass, api: api} do
      Bypass.expect_once(bypass, "GET", "/api/core/metadataschemas", fn conn ->
        params = Plug.Conn.fetch_query_params(conn).query_params
        assert params["page"] == "1"
        assert params["size"] == "5"

        custom_response = ~s({
          "_embedded": {"metadataschemas": []},
          "_links": {},
          "page": {"size": 5, "totalElements": 0, "totalPages": 0, "number": 1}
        })

        respond_with_json(conn, 200, custom_response)
      end)

      {:ok, result} = [page: 1, size: 5] |> Metadata.list_schemas() |> API.request(api)

      {_schemas, metadata, _next_url} = result
      assert metadata["page"]["number"] == 1
      assert metadata["page"]["size"] == 5
    end
  end

  describe "creating metadata schemas" do
    test "creates schema successfully", %{bypass: bypass, api: api} do
      schema_data =
        test_schema_data(%{"prefix" => "example", "namespace" => "http://example.org/"})

      schema_fixture = load_fixture("fetch_metadata_schema.json")

      Bypass.expect_once(bypass, "POST", "/api/core/metadataschemas", fn conn ->
        {:ok, body, conn} = Plug.Conn.read_body(conn)
        request_data = Jason.decode!(body)

        assert request_data["prefix"] == "example"
        assert request_data["namespace"] == "http://example.org/"

        respond_with_json(conn, 201, schema_fixture)
      end)

      {:ok, result} = schema_data |> Metadata.create_schema() |> API.request(api)

      assert result["type"] == "metadataschema"
    end

    test "ignores options parameter in schema creation" do
      schema_data = test_schema_data()
      ignored_options = [some_option: "ignored"]

      operation = Metadata.create_schema(schema_data, ignored_options)

      assert operation.data == schema_data
      assert operation.params == []
    end
  end

  describe "modifying metadata schemas" do
    test "updates schema successfully", %{bypass: bypass, api: api} do
      schema_id = "1"
      updates = %{"namespace" => "http://updated.example.org/"}
      schema_fixture = load_fixture("fetch_metadata_schema.json")

      Bypass.expect_once(bypass, "PUT", "/api/core/metadataschemas/#{schema_id}", fn conn ->
        {:ok, body, conn} = Plug.Conn.read_body(conn)
        request_data = Jason.decode!(body)

        assert request_data["namespace"] == "http://updated.example.org/"

        respond_with_json(conn, 200, schema_fixture)
      end)

      {:ok, result} = schema_id |> Metadata.update_schema(updates) |> API.request(api)

      assert result["type"] == "metadataschema"
    end
  end

  describe "removing metadata schemas" do
    test "deletes schema successfully", %{bypass: bypass, api: api} do
      schema_id = "1"

      Bypass.expect_once(bypass, "DELETE", "/api/core/metadataschemas/#{schema_id}", fn conn ->
        respond_with_json(conn, 204, "")
      end)

      {:ok, result} = schema_id |> Metadata.delete_schema() |> API.request(api)

      assert result == :ok
    end
  end

  describe "edge cases and error scenarios" do
    test "handles empty schema parameter in list_fields" do
      operation = Metadata.list_fields(schema: "")

      # Should use regular list endpoint when schema is empty
      assert operation.path == "/api/core/metadatafields"
    end

    test "handles nil scope note in field creation" do
      field_data = %{
        element: "subject",
        qualifier: "keyword",
        scope_note: nil
      }

      operation = Metadata.create_field(field_data, schema_id: "1")

      expected_data = %{
        "element" => "subject",
        "qualifier" => "keyword",
        "scopeNote" => nil
      }

      assert operation.data == expected_data
    end

    test "find_fields supports multiple search criteria" do
      options = [
        schema: "dc",
        element: "contributor",
        qualifier: "author",
        query: "dc.contrib",
        page: 2,
        size: 5
      ]

      operation = Metadata.find_fields(options)

      assert Keyword.get(operation.params, :schema) == "dc"
      assert Keyword.get(operation.params, :element) == "contributor"
      assert Keyword.get(operation.params, :qualifier) == "author"
      assert Keyword.get(operation.params, :query) == "dc.contrib"
    end

    test "schema filtering preserves other list_fields options" do
      options = [schema: "dc", page: 3, size: 15, sort: "element"]

      operation = Metadata.list_fields(options)

      assert operation.path == "/api/core/metadatafields/search/bySchema"
      assert Keyword.get(operation.params, :schema) == "dc"
      assert Keyword.get(operation.params, :page) == 3
      assert Keyword.get(operation.params, :size) == 15
    end

    test "create_field requires schema_id option" do
      field_data = test_field_data()

      assert_raise FunctionClauseError, fn ->
        Metadata.create_field(field_data, [])
      end
    end
  end

  # Private helpers

  defp test_field_data(overrides \\ %{}) do
    base_data = %{
      element: "contributor",
      qualifier: "author",
      scope_note: "Test scope note"
    }

    Map.merge(base_data, overrides)
  end

  defp test_schema_data(overrides \\ %{}) do
    base_data = %{
      "prefix" => "test",
      "namespace" => "http://test.example.org/"
    }

    Map.merge(base_data, overrides)
  end
end
