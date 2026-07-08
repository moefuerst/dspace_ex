defmodule DSpace.AuthExternalTest do
  use DSpace.ExternalCase

  alias DSpace.API

  @moduletag :requires_auth

  setup do
    client = dspace_test_api(authenticate: true)

    {:ok, client: client}
  end

  describe "credential management" do
    test "repeated login does not invalidate previously issued tokens", %{client: client} do
      # setup logs in an retrieves authenticated client struct
      assert API.authenticated?(client),
             "Expected first client to be authenticated with DSpace API"

      # log in again
      new_client = dspace_test_api(authenticate: true)

      assert API.authenticated?(new_client),
             "Expected second client to be authenticated with DSpace API"

      # the token from first login is still valid
      assert API.authenticated?(client),
             "Expected first client to still be authenticated with first token"
    end
  end
end
