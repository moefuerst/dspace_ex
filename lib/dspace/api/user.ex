defmodule DSpace.API.User do
  @moduledoc """
  Functions for working with DSpace Users.

  In DSpace-speak a user is called an "EPerson".
  """

  @behaviour DSpace.API.Resource

  import DSpace.Utils, only: [is_nonempty_binary: 1, pop_pagination: 1]

  alias DSpace.API.Operation
  alias DSpace.API.Resource
  alias DSpace.API.StreamBuilder
  alias DSpace.API.Transform

  @ep_users "/api/eperson/epersons"
  @ep_by_email @ep_users <> "/search/byEmail"
  @ep_by_metadata @ep_users <> "/search/byMetadata"

  # Public API

  @doc """
  Fetches a user by their email address.

  ## Parameters

    * `email` - The email address of the user to fetch
  """
  @spec fetch_by_email(binary()) :: Operation.t()
  def fetch_by_email(email) when is_nonempty_binary(email) do
    %Operation.JSON{
      path: @ep_by_email,
      expected_status: [200, 204],
      params: [email: email]
    }
  end

  @doc """
  Lists groups that a user is a direct member of.

  This operation can be streamed.

  ## Parameters

    * `uuid` - The UUID of the user
    * `options` - Additional options for pagination

  ## Options

    * `:page` - Page number (0-based, defaults to 0)
    * `:size` - Number of items per page (usually defaults to 20)
  """
  @spec list_groups(binary(), keyword()) :: Operation.t()
  def list_groups(uuid, options \\ []) when is_nonempty_binary(uuid) do
    {pagination, other_options} = pop_pagination(options)

    op = %Operation.JSON{
      path: @ep_users <> "/" <> uuid <> "/groups",
      params: pagination ++ other_options,
      transformer: &Transform.transform_collection(&1, extract: ["_embedded", "groups"])
    }

    %{op | stream_impl: &StreamBuilder.new(&1, op, &2)}
  end

  # Callbacks

  @doc """
  Fetches a single user by UUID.
  """
  @impl Resource
  @spec fetch(binary(), keyword()) :: Operation.t()
  def fetch(uuid, _options \\ []) when is_nonempty_binary(uuid) do
    %Operation.JSON{path: @ep_users <> "/" <> uuid}
  end

  @doc """
  Finds users by Metadata.

  This operation can be streamed.

  ## Options

    * `:search_term` - general search term
    * `:page` - Page number (0-based, defaults to 0)
    * `:size` - Number of items per page (usually defaults to 20)
  """
  @impl Resource
  @spec find(keyword()) :: Operation.t()
  def find(options \\ []) when is_list(options) do
    {pagination, other_options} = pop_pagination(options)

    op = %Operation.JSON{
      path: @ep_by_metadata,
      params: pagination ++ other_options,
      transformer: &Transform.transform_collection(&1, extract: ["_embedded", "epersons"])
    }

    %{op | stream_impl: &StreamBuilder.new(&1, op, &2)}
  end

  @doc """
  Lists all users from the repository.

  This operation can be streamed.

  ## Options

    * `:page` - Page number (0-based, defaults to 0)
    * `:size` - Number of items per page (usually defaults to 20)
  """
  @impl Resource
  @spec list(keyword()) :: Operation.t()
  def list(options \\ []) do
    {pagination, other_options} = pop_pagination(options)

    op = %Operation.JSON{
      path: @ep_users,
      params: pagination ++ other_options,
      transformer: &Transform.transform_collection(&1, extract: ["_embedded", "epersons"])
    }

    %{op | stream_impl: &StreamBuilder.new(&1, op, &2)}
  end

  @doc """
  Creates a new user.

  This operation requires administrator privileges.

  Required user data:

    * `"email"` - User's email address (must be unique within the system)
    * `"metadata"` - Map containing user metadata

  ## Parameters

    * `user_data` - Map containing user data and metadata

  ## Examples

      user_data = %{
        "email" => "newuser@example.com",
        "metadata" => %{
          "eperson.firstname" => [%{"value" => "John"}],
          "eperson.lastname" => [%{"value" => "Doe"}]
        },
        "canLogIn" => true,
        "requireCertificate" => false
      }
      {:ok, created_user} =
        User.create(user_data) |> DSpace.API.request(client)
  """
  @impl Resource
  @spec create(map(), keyword()) :: Operation.t()
  def create(user_data, _options \\ []) when is_map(user_data) do
    %Operation.JSON{
      http_method: :post,
      path: @ep_users,
      data: user_data
    }
  end

  @doc """
  Updates an existing user.
  """
  @impl Resource
  @spec update(binary(), list(), keyword()) :: Operation.t()
  def update(uuid, updates, _options \\ []) when is_nonempty_binary(uuid) and is_list(updates) do
    %Operation.JSON{
      path: @ep_users <> "/" <> uuid,
      http_method: :patch,
      data: updates
    }
  end

  @doc """
  Replaces an user.

  Replaces all user data with the provided data.

  This operation requires administrator privileges.

  ## Parameters

    * `uuid` - The UUID of the user to replace
    * `user_data` - Complete user data map
  """
  @impl Resource
  @spec replace(binary(), map(), keyword()) :: Operation.t()
  def replace(uuid, user_data, _options \\ []) when is_nonempty_binary(uuid) and is_map(user_data) do
    %Operation.JSON{
      path: @ep_users <> "/" <> uuid,
      http_method: :put,
      data: user_data
    }
  end

  @doc """
  Deletes a user permanently.

  When a user is deleted, the system handles various references through cascading operations:

    * Items submitted by the user have their submitter set to null
    * Items in the user's workspace are deleted entirely
    * Resource policies are removed
    * Workflow tasks are unclaimed or deleted
    * Group memberships are removed

  This operation has the following constraints:

    * Requires administrator privileges
    * You can't delete users if it would leave workflow groups empty

  ## Parameters

    * `uuid` - The UUID of the user to delete
  """
  @impl Resource
  @spec delete(binary(), keyword()) :: Operation.t()
  def delete(uuid, _options \\ []) when is_nonempty_binary(uuid) do
    %Operation.JSON{
      path: @ep_users <> "/" <> uuid,
      http_method: :delete,
      transformer: fn _ -> :ok end
    }
  end
end
