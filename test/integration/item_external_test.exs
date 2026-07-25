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

    @tag :requires_third_party_api
    # This test depends on the PubMed API being available to the DSpace server.
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
        full_path_replace_operation("dc.title", "Updated External Title"),
        full_path_replace_operation("dc.date.issued", "2024-01-15"),
        full_path_replace_operation("dc.type", "Article")
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

    test "replaces metadata values given their field path", %{client: client, item: item} do
      uuid = item["uuid"]

      update_operations = [
        field_path_replace_operation("dc.title", "Updated External Title", {"en", nil, -1}),
        field_path_replace_operation("dc.date.issued", "2024-01-15"),
        field_path_replace_operation("dc.type", "Article", {nil, nil, 600})
      ]

      updated_item =
        uuid
        |> Item.update(update_operations)
        |> API.request!(client)

      metadata = updated_item["metadata"]

      assert updated_item["uuid"] == uuid
      assert [%{"value" => "Updated External Title"} | _] = metadata["dc.title"]
      assert [%{"language" => "en"} | _] = metadata["dc.title"]
      assert [%{"value" => "2024-01-15"} | _] = metadata["dc.date.issued"]
      assert [%{"value" => "Article"} | _] = metadata["dc.type"]
      assert [%{"confidence" => 600} | _] = metadata["dc.type"]
    end

    @tag :bug
    # https://github.com/DSpace/DSpace/issues/12419
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

  defp multilingual_metadata do
    Map.put(item_metadata(), "dc.title", [
      %{"value" => "Test Title", "language" => "en", "authority" => nil, "confidence" => -1},
      %{"value" => "American Title", "language" => "en_US", "authority" => nil, "confidence" => -1},
      %{"value" => "Testtitel", "language" => "de", "authority" => nil, "confidence" => -1},
      %{"value" => "Österreichischer Titel", "language" => "de_AT", "authority" => nil, "confidence" => -1},
      %{"value" => "Untitled", "language" => nil, "authority" => nil, "confidence" => -1}
    ])
  end

  def field_path_replace_operation(field, value, {language, authority, confidence} \\ {nil, nil, -1}) do
    %{
      "op" => "replace",
      "path" => "/metadata/#{field}",
      "value" => [
        %{
          "value" => value,
          "language" => language,
          "authority" => authority,
          "confidence" => confidence
        }
      ]
    }
  end

  def full_path_replace_operation(field, value, place \\ 0) do
    %{
      "op" => "replace",
      "path" => "/metadata/#{field}/#{place}/value",
      "value" => %{"value" => value}
    }
  end
end
