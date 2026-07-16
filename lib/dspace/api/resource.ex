defmodule DSpace.API.Resource do
  @moduledoc """
  Specifies the behaviour of an API resource.
  """

  alias DSpace.API.Operation
  alias DSpace.API.Resource.Update

  @typedoc """
  Represents a "DSpace Object" UUID.

  Any repository entity (community, collection, item, user, user group, file, etc.) will have
  a UUID.
  """
  @type dso_uuid :: binary()

  @type options :: keyword()

  @typedoc """
  Represents a single metadata update to a resource.

  See `DSpace.API.Resource.Update` for details. A plain string-keyed map is also accepted.

  ## Examples

      %DSpace.API.Resource{
        op: :replace,
        path: "/metadata/dc.title/0/value",
        value: "New Title"
      }

      %{
        "op" => "replace",
        "path" => "/metadata/dc.title/0/value",
        "value" => "New Title"
      }
  """
  @type resource_update :: Update.t() | %{required(binary()) => binary() | nil}

  @doc """
  Builds an operation to fetch a single resource by UUID.
  """
  @callback fetch(dso_uuid(), options()) :: Operation.t()

  @doc """
  Builds an operation to fetch a list of resources.
  """
  @callback list(options()) :: Operation.t()

  @doc """
  Builds an operation to fetch resources via DSpace search ("discovery").
  """
  @callback find(options()) :: Operation.t()

  @doc """
  Builds an operation to create a new resource on DSpace.
  """
  @callback create(map(), options()) :: Operation.t()

  @doc """
  Builds an operation to update an existing resource on DSpace.

  The payload is a list of `t:resource_update/0`.
  """
  @callback update(dso_uuid(), [resource_update()], options()) :: Operation.t()

  @doc """
  Builds an operation to replace a resource on DSpace.
  """
  @callback replace(dso_uuid(), map(), options()) :: Operation.t()

  @doc """
  Builds an operation to delete a resource on DSpace.
  """
  @callback delete(binary(), options()) :: Operation.t()

  @optional_callbacks find: 1,
                      create: 2,
                      update: 3,
                      replace: 3,
                      delete: 2
end
