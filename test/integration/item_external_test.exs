defmodule DSpace.ItemExternalTest do
  use DSpace.ExternalCase

  alias DSpace.API
  alias DSpace.API.Item

  @moduletag :requires_auth

  describe "create_draft/1" do
    setup do
      client = dspace_test_api(authenticate: true)
      hierarchy = Fixtures.create_collection_hierarchy(client)

      {:ok, client: client, collection: hierarchy.collection}
    end

    test "creates a draft from an external source", %{client: client, collection: collection} do
      parent = collection["uuid"]

      draft =
        [parent: parent, from: %{id: "42391361", source: :pubmed}]
        |> Item.create_draft()
        |> API.request!(client)

      assert is_integer(draft["id"])
      assert draft["type"] == "workspaceitem"
    end
  end

  describe "update/3" do
    setup do
      client = dspace_test_api(authenticate: true)
      hierarchy = Fixtures.create_item_hierarchy(client, item: [metadata: item_metadata()])

      {:ok, client: client, item: hierarchy.item}
    end

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

    # https://github.com/DSpace/DSpace/issues/12419
    @tag :bug
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

      # actually expected: Item now has two authors
      # [_ | %{"value" => "Author Two"}] = metadata["dc.contributor.author"]

      assert [%{"value" => "Author One"}] = metadata["dc.contributor.author"],
             "Metadata PATCH add/replace with array values bug appears to be fixed"
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
