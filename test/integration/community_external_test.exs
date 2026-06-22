defmodule DSpace.CommunityExternalTest do
  use DSpace.ExternalCase

  alias DSpace.API
  alias DSpace.API.Community

  @moduletag :skip
  @moduletag :requires_auth

  setup do
    client = dspace_test_api(authenticate: true)
    community = Fixtures.community(client)

    {:ok, client: client, community: community}
  end

  test "creates community under the toplevel community", %{community: community} do
    assert String.starts_with?(community["name"], "Test Community")
  end

  @tag :bug
  test "toplevel community deletion is a no-op", %{client: client} do
    toplevel =
      %{
        "name" => "Test Community",
        "metadata" => %{
          "dc.title" => [
            %{
              "value" => "Test Community",
              "language" => nil,
              "authority" => nil,
              "confidence" => -1
            }
          ]
        }
      }
      |> Community.create()
      |> API.request!(client)

    uuid = toplevel["uuid"]

    assert :ok =
             uuid
             |> Community.delete()
             |> API.request!(client)

    # The API might report success but does not actually delete toplevel communities, even with
    # admin credentials. Unclear if this is a configuration issue, bug or intended behaviour.

    # Re-fetch all toplevel communities and check whether the community is really gone.
    toplevel_uuids =
      Community.list_toplevel()
      |> API.stream!(client)
      |> Stream.map(& &1["uuid"])
      |> Enum.to_list()

    # Assert the buggy behaviour.
    assert uuid in toplevel_uuids,
           "DSpace toplevel deletion bug appears to be fixed, " <>
             "community #{uuid} was actually removed. " <>
             "The sub-community workaround in ExternalCase.Fixtures may no longer be needed."
  end
end
