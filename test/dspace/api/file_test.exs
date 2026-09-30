defmodule DSpace.API.FileTest do
  use DSpace.API.Case, async: true

  alias DSpace.API.Error
  alias DSpace.API.File
  alias DSpace.API.Model.ResourceUpdate

  describe "create_in_bundle/3" do
    test "uploads multipart file and properties payload", %{sham: sham, api: api} do
      Sham.expect_once(sham, "POST", "/api/core/bundles/bundle-id/bitstreams", fn conn ->
        [content_type] = Plug.Conn.get_req_header(conn, "content-type")
        assert String.starts_with?(content_type, "multipart/form-data")
        assert String.contains?(content_type, "boundary=")

        {:ok, body, conn} = Plug.Conn.read_body(conn)
        assert String.contains?(body, ~s(name="file"))
        assert String.contains?(body, ~s(filename="report.pdf"))
        assert String.contains?(body, "file_content")
        assert String.contains?(String.downcase(body), "content-type: application/pdf")
        assert String.contains?(body, ~s("name":"Stored report"))
        assert String.contains?(body, ~s(name="properties"))
        assert String.contains?(body, "Final report")

        respond_with_json(conn, 201, ~s({"type":"bitstream","uuid":"bitstream-id","name":"report.pdf"}))
      end)

      properties = %{
        "name" => "Stored report",
        "metadata" => %{"dc.description" => [%{"value" => "Final report"}]}
      }

      {:ok, file} =
        "bundle-id"
        |> File.create_in_bundle(
          {"report.pdf", "file_content", "application/pdf"},
          properties: properties
        )
        |> API.request(api)

      assert file["type"] == "bitstream"
      assert file["name"] == "report.pdf"
    end
  end

  describe "download/2" do
    test "returns JSON files verbatim even when response decoding is requested", %{sham: sham, api: api} do
      contents = ~s({"name":"report","values":[1,2]})

      Sham.expect_once(sham, "GET", "/api/core/bitstreams/file-id/content", fn conn ->
        respond_with_json(conn, 200, contents)
      end)

      result =
        "file-id"
        |> File.download()
        |> API.request(api, decode_body: true)

      assert {:ok, ^contents} = result
    end

    test "passes the short-lived token for a restricted download", %{sham: sham, api: api} do
      Sham.expect_once(sham, "GET", "/api/core/bitstreams/file-id/content", fn conn ->
        params = Plug.Conn.fetch_query_params(conn).query_params
        assert params["authentication-token"] == "download-token"
        Plug.Conn.resp(conn, 200, "file bytes")
      end)

      result =
        "file-id"
        |> File.download(auth_token: "download-token")
        |> API.request(api)

      assert {:ok, "file bytes"} = result
    end
  end

  describe "finding files by item" do
    test "includes hidden files by default", %{sham: sham, api: api} do
      Sham.expect_once(sham, "GET", "/api/core/bitstreams/search/byItemId", fn conn ->
        params = Plug.Conn.fetch_query_params(conn).query_params
        assert params["uuid"] == "item-id"
        assert params["name"] == "ORIGINAL"
        respond_with_json(conn, 200, ~s({"_embedded":{"bitstreams":[{"uuid":"file-id"}]}}))
      end)

      result =
        "item-id"
        |> File.find_by_item("ORIGINAL")
        |> API.request(api)

      assert {:ok, {[%{"uuid" => "file-id"}], _meta, nil}} = result
    end

    test "can exclude hidden files", %{sham: sham, api: api} do
      Sham.expect_once(sham, "GET", "/api/core/bitstreams/search/showableByItem", fn conn ->
        respond_with_json(conn, 200, ~s({"_embedded":{"bitstreams":[{"uuid":"visible-id"}]}}))
      end)

      result =
        "item-id"
        |> File.find_by_item("ORIGINAL", exclude_hidden: true)
        |> API.request(api)

      assert {:ok, {[%{"uuid" => "visible-id"}], _meta, nil}} = result
    end

    test "retains all metadata filter pairs and pagination" do
      operation =
        File.find_by_item("item-id", "ORIGINAL",
          filters: [{"dc.title", "Report"}, {"dc.description", "Final"}],
          page: 2,
          size: 5
        )

      assert Keyword.get_values(operation.params, :filterMetadata) == ["dc.title", "dc.description"]
      assert Keyword.get_values(operation.params, :filterMetadataValue) == ["Report", "Final"]
      assert operation.params[:page] == 2
      assert operation.params[:size] == 5
    end
  end

  describe "file changes" do
    test "serializes metadata updates as JSON Patch", %{sham: sham, api: api} do
      Sham.expect_once(sham, "PATCH", "/api/core/bitstreams/file-id", fn conn ->
        {:ok, body, conn} = Plug.Conn.read_body(conn)

        assert JSON.decode!(body) == [
                 %{"op" => "replace", "path" => "/name", "value" => "Renamed report"}
               ]

        respond_with_json(conn, 200, ~s({"uuid":"file-id","name":"Renamed report"}))
      end)

      result =
        "file-id"
        |> File.update([ResourceUpdate.replace("/name", "Renamed report")], [])
        |> API.request(api)

      assert {:ok, %{"name" => "Renamed report"}} = result
    end

    test "deletes a single file", %{sham: sham, api: api} do
      Sham.expect_once(sham, "DELETE", "/api/core/bitstreams/file-id", fn conn ->
        Plug.Conn.resp(conn, 204, "")
      end)

      result =
        "file-id"
        |> File.delete()
        |> API.request(api)

      assert {:ok, :ok} = result
    end

    test "bulk deletion removes every requested file and accepts a no-content response", %{sham: sham, api: api} do
      Sham.expect_once(sham, "PATCH", "/api/core/bitstreams", fn conn ->
        {:ok, body, conn} = Plug.Conn.read_body(conn)

        assert JSON.decode!(body) == [
                 %{"op" => "remove", "path" => "/bitstreams/first-id"},
                 %{"op" => "remove", "path" => "/bitstreams/second-id"}
               ]

        Plug.Conn.resp(conn, 204, "")
      end)

      result =
        ["first-id", "second-id"]
        |> File.delete()
        |> API.request(api)

      assert {:ok, :ok} = result
    end
  end

  describe "uploads without an explicit MIME type" do
    test "defaults to binary content and derives the stored name from the filename", %{sham: sham, api: api} do
      Sham.expect_once(sham, "POST", "/api/core/bundles/bundle-id/bitstreams", fn conn ->
        {:ok, body, conn} = Plug.Conn.read_body(conn)
        assert body =~ ~r/content-type: application\/octet-stream/i
        assert String.contains?(body, ~s(filename="report.bin"))
        assert String.contains?(body, ~s("name":"report.bin"))
        assert String.contains?(body, "binary-content")
        respond_with_json(conn, 201, ~s({"uuid":"file-id"}))
      end)

      result =
        "bundle-id"
        |> File.create_in_bundle({"report.bin", "binary-content"})
        |> API.request(api)

      assert {:ok, %{"uuid" => "file-id"}} = result
    end
  end

  describe "listing files" do
    test "lists the requested bundle with pagination", %{sham: sham, api: api} do
      Sham.expect_once(sham, "GET", "/api/core/bundles/bundle-id/bitstreams", fn conn ->
        params = Plug.Conn.fetch_query_params(conn).query_params
        assert params["page"] == "2"
        assert params["size"] == "5"
        refute Map.has_key?(params, "bundle")
        respond_with_json(conn, 200, ~s({"_embedded":{"bitstreams":[{"uuid":"file-id"}]}}))
      end)

      result =
        [bundle: "bundle-id", page: 2, size: 5]
        |> File.list()
        |> API.request(api)

      assert {:ok, {[%{"uuid" => "file-id"}], _meta, nil}} = result
    end

    test "explains that a bundle is required" do
      options = []

      assert_raise ArgumentError, "listing files requires a :bundle option (a bundle UUID)", fn ->
        File.list(options)
      end
    end
  end

  describe "fetch_by_item_handle/2" do
    test "returns the file when found", %{sham: sham, api: api} do
      handle = "20.500.12345/67890"
      file_fixture = load_fixture("fetch_file.json")

      Sham.expect_once(sham, "GET", "/api/core/bitstreams/search/byItemHandle", fn conn ->
        params = Plug.Conn.fetch_query_params(conn).query_params
        assert params["handle"] == handle
        assert params["sequence"] == "1"
        respond_with_json(conn, 200, file_fixture)
      end)

      {:ok, result} =
        handle
        |> File.fetch_by_item_handle(sequence: 1)
        |> API.request(api)

      assert_valid_dspace_resource(result, "bitstream", ["name", "sequenceId"])
    end

    test "returns a :not_found error when no file matches (204)", %{sham: sham, api: api} do
      Sham.expect_once(sham, "GET", "/api/core/bitstreams/search/byItemHandle", fn conn ->
        respond_with_json(conn, 204, "")
      end)

      {:error, error} =
        "20.500.12345/67890"
        |> File.fetch_by_item_handle(sequence: 99)
        |> API.request(api)

      assert %Error{type: :not_found} = error
    end
  end
end
