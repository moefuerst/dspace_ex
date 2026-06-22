defmodule DSpace.API.FileTest do
  use DSpace.API.Case, async: true

  alias DSpace.API.Error
  alias DSpace.API.File

  describe "fetch_by_item_handle/2" do
    test "returns the file when found", %{bypass: bypass, api: api} do
      handle = "20.500.12345/67890"
      file_fixture = load_fixture("fetch_file_by_handle.json")

      Bypass.expect_once(bypass, "GET", "/api/core/bitstreams/search/byItemHandle", fn conn ->
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

    test "returns a :not_found error when no file matches (204)", %{bypass: bypass, api: api} do
      Bypass.expect_once(bypass, "GET", "/api/core/bitstreams/search/byItemHandle", fn conn ->
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
