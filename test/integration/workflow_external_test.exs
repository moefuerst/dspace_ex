defmodule DSpace.WorkflowExternalTest do
  use DSpace.ExternalCase

  @moduletag :requires_auth

  setup do
    client = dspace_test_api(authenticate: true)
    hierarchy = Fixtures.create_item_hierarchy(client)

    {:ok, client: client, item: hierarchy.item}
  end
end
