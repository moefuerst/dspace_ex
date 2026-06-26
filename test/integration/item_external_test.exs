defmodule DSpace.ItemExternalTest do
  use DSpace.ExternalCase

  alias DSpace.API
  alias DSpace.API.Item

  @moduletag :requires_auth

  setup do
    client = dspace_test_api(authenticate: true)
    hierarchy = Fixtures.create_item_hierarchy(client, item: [metadata: item_metadata()])

    {:ok, client: client, item: hierarchy.item}
  end

  describe "update/3" do
    test "replaces metadata values given their full path", %{client: client, item: item} do
      uuid = item["uuid"]

      update_operations = [
        %{"op" => "replace", "path" => "/metadata/dc.title/0/value", "value" => "Updated External Title"},
        %{"op" => "replace", "path" => "/metadata/dc.date.issued/0/value", "value" => "2024-01-15"},
        %{"op" => "replace", "path" => "/metadata/dc.type/0/value", "value" => "Article"}
      ]

      updated_item =
        uuid
        |> Item.update(update_operations)
        |> API.request!(client)

      metadata = updated_item["metadata"]

      assert updated_item["uuid"] == uuid
      assert [%{"value" => "Updated External Title"} | _] = metadata["dc.title"]
      assert [%{"value" => "2024-01-15"} | _] = metadata["dc.date.issued"]
      assert [%{"value" => "Article"} | _] = metadata["dc.type"]
    end

    test "adds new metadata array", %{client: client, item: item} do
      uuid = item["uuid"]

      update_operations = [
        %{
          "op" => "add",
          "path" => "/metadata/dc.contributor.author",
          "value" => [
            %{"value" => "Author One"},
            %{"value" => "Author Two"}
          ]
        }
      ]

      updated_item =
        uuid
        |> Item.update(update_operations)
        |> API.request!(client)

      metadata = updated_item["metadata"]

      assert updated_item["uuid"] == uuid
      assert [%{"value" => "Author One"} | _] = metadata["dc.contributor.author"]
      assert [_ | %{"value" => "Author Two"}] = metadata["dc.contributor.author"]
    end
  end

  # Private helpers

  defp item_metadata do
    %{
      "dc.title" => [
        %{
          "value" => "Test Title",
          "language" => nil,
          "authority" => nil,
          "confidence" => -1
        }
      ],
      "dc.date.issued" => [
        %{
          "value" => "2023-03-15",
          "language" => nil,
          "authority" => nil,
          "confidence" => -1
        }
      ],
      "dc.type" => [
        %{
          "value" => "Publication",
          "language" => nil,
          "authority" => nil,
          "confidence" => -1
        }
      ]
    }
  end
end
