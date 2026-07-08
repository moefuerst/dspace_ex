defmodule DSpace.FileExternalTest do
  use DSpace.ExternalCase

  alias DSpace.API
  alias DSpace.API.File

  @moduletag :requires_auth

  setup do
    client = dspace_test_api(authenticate: true)
    hierarchy = Fixtures.create_item_hierarchy(client)

    {:ok, client: client, item: hierarchy.item}
  end

  describe "create_in_bundle/3" do
    test "uploads a file to an item", %{client: client, item: item} do
      parent = item["uuid"]

      bundle =
        %{}
        |> File.create_bundle(parent: parent)
        |> API.request!(client)

      file_path = Path.join(["test", "support", "fixtures", "blank.pdf"])

      file_metadata = %{
        "metadata" => %{"dc.description" => [%{"value" => "Final report"}]}
      }

      file =
        bundle["uuid"]
        |> File.create_in_bundle(file_path, properties: file_metadata)
        |> API.request!(client)

      description = get_in(file, ["metadata", "dc.description", Access.at(0), "value"])

      assert file["type"] == "bitstream"
      assert file["name"] == "blank.pdf"
      assert description == "Final report"
    end
  end
end
