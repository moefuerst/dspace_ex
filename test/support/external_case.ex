defmodule DSpace.ExternalCase do
  @moduledoc """
  Defines the setup for tests that require a real DSpace instance.
  """

  use ExUnit.CaseTemplate

  alias DSpace.API.Error

  using do
    quote do
      import DSpace.ExternalCase

      alias DSpace.ExternalCase.Fixtures

      @moduletag :external
    end
  end

  setup do
    endpoint = System.fetch_env!("DSPACE_ENDPOINT")
    {:ok, endpoint: endpoint}
  end

  @doc """
  Returns a DSpace API client structure.

  ## Options

    * `:authenticate` - whether to authenticate the client with DSpace admin credentials from
      the environment (default: `false`)
  """
  def dspace_test_api(options \\ []) do
    endpoint = System.fetch_env!("DSPACE_ENDPOINT")
    version = System.get_env("DSPACE_VERSION", "9.2.0")

    client =
      DSpace.API.new(
        endpoint: endpoint,
        api_version: version,
        # Disable retry to fail fast in all tests
        http_impl: {DSpace.API.HTTP.Req, [retry: false]}
      )

    if Keyword.get(options, :authenticate, false) do
      email = System.fetch_env!("DSPACE_ADMIN_EMAIL")
      password = System.fetch_env!("DSPACE_ADMIN_PASSWORD")

      DSpace.API.login!(client, email, password)
    else
      client
    end
  end

  @doc """
  Asserts that a core API resource has the expected structure.
  """
  def assert_valid_dspace_resource(resource, expected_type, required_fields \\ []) do
    assert Map.has_key?(resource, "uuid")
    assert Map.has_key?(resource, "type")
    assert resource["type"] == expected_type

    if Map.has_key?(resource, "_links") do
      assert is_map(resource["_links"])
    end

    Enum.each(required_fields, fn field ->
      assert Map.has_key?(resource, field), "Resource missing required field: #{field}"
    end)
  end

  @doc """
  Asserts that a paginated API response has the expected structure.
  """
  def assert_valid_paginated_response({items, metadata, next_url}) when is_list(items) do
    assert is_list(items)
    assert is_map(metadata)
    assert Map.has_key?(metadata, "page")
    assert is_binary(next_url) or is_nil(next_url)
  end

  defmodule Fixtures do
    @moduledoc """
    Fixture functions for creating API resources with cleanup.
    """
    alias DSpace.API
    alias DSpace.API.Collection
    alias DSpace.API.Community
    alias DSpace.API.Item
    alias ExUnit.Callbacks

    require Logger

    def community(client, opts \\ []) do
      parent =
        Community.list_toplevel()
        |> API.stream!(client)
        |> Enum.at(0)
        |> Map.fetch!("uuid")

      name = Keyword.get(opts, :name, "Test Community #{unique_id()}")

      metadata = Keyword.get(opts, :metadata, dc_title(name))

      test_community =
        %{
          "name" => name,
          "metadata" => metadata
        }
        |> Community.create(parent: parent)
        |> API.request(client)

      case test_community do
        {:ok, community} ->
          Callbacks.on_exit({:cleanup_community, community["uuid"]}, fn ->
            cleanup_resource(community, Community, client)
          end)

          community

        {:error, reason} ->
          raise "Failed to create test community: #{inspect(reason)}"
      end
    end

    def collection(client, community, opts \\ []) do
      name = Keyword.get(opts, :name, "Test Collection #{unique_id()}")
      parent = community["uuid"]

      metadata =
        Keyword.get(opts, :metadata, dc_title(name))

      test_collection =
        %{
          "name" => name,
          "metadata" => metadata
        }
        |> Collection.create(parent: parent)
        |> API.request(client)

      case test_collection do
        {:ok, collection} ->
          Callbacks.on_exit({:cleanup_collection, collection["uuid"]}, fn ->
            cleanup_resource(collection, Collection, client)
          end)

          collection

        {:error, reason} ->
          raise "Failed to create test collection: #{inspect(reason)}"
      end
    end

    def item(client, collection, opts \\ []) do
      name = Keyword.get(opts, :name, "Test Item #{unique_id()}")
      entity_type = Keyword.get(opts, :entity_type, "Publication")
      parent = collection["uuid"]

      metadata = Keyword.get(opts, :metadata, dc_title(name))

      test_item =
        %{
          "name" => name,
          "metadata" => metadata,
          "entityType" => entity_type,
          "inArchive" => true,
          "discoverable" => true,
          "withdrawn" => false
        }
        |> Item.create(parent: parent)
        |> API.request(client)

      case test_item do
        {:ok, item} ->
          Callbacks.on_exit({:cleanup_item, item["uuid"]}, fn ->
            cleanup_resource(item, Item, client)
          end)

          item

        {:error, reason} ->
          raise "Failed to create test item: #{inspect(reason)}"
      end
    end

    @doc """
    Creates a hierarchy of resources: community -> collection.
    """
    def create_collection_hierarchy(client, opts \\ []) do
      community = community(client, Keyword.get(opts, :community, []))
      collection = collection(client, community, Keyword.get(opts, :collection, []))

      %{
        community: community,
        collection: collection
      }
    end

    @doc """
    Creates a hierarchy of resources: community -> collection -> item.
    """
    def create_item_hierarchy(client, opts \\ []) do
      community = community(client, Keyword.get(opts, :community, []))
      collection = collection(client, community, Keyword.get(opts, :collection, []))
      item = item(client, collection, Keyword.get(opts, :item, []))

      %{
        community: community,
        collection: collection,
        item: item
      }
    end

    # Private helpers

    defp cleanup_resource(resource, module, client) do
      case resource["uuid"] |> module.delete() |> API.request(client) do
        {:ok, _} ->
          :ok

        {:error, %Error{type: :not_found}} ->
          :ok

        {:error, reason} ->
          Logger.warning("Failed to cleanup #{module} #{resource["uuid"]}: #{inspect(reason)}")
      end
    end

    defp dc_title(name, opts \\ []) do
      %{
        "dc.title" => [
          %{
            "value" => name,
            "language" => Keyword.get(opts, :language, nil),
            "authority" => Keyword.get(opts, :authority, nil),
            "confidence" => Keyword.get(opts, :confidence, -1)
          }
        ]
      }
    end

    defp unique_id, do: System.unique_integer([:positive, :monotonic])
  end
end
