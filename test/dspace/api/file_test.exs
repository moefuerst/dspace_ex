defmodule DSpace.API.FileTest do
  use DSpace.API.Case, async: true

  alias DSpace.API.Error
  alias DSpace.API.File

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
        assert String.contains?(body, ~s(name="properties"))
        assert String.contains?(body, "Final report")

        respond_with_json(conn, 201, ~s({"type":"bitstream","uuid":"bitstream-id","name":"report.pdf"}))
      end)

      properties = %{
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
