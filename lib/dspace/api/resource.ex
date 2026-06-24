defmodule DSpace.API.Resource do
  @moduledoc """
  Specifies the behaviour of an API resource.
  """

  alias DSpace.API.Operation

  @typedoc """
  Represents a "DSpace Object" UUID.

  Any repository entity (community, collection, item, user, user group, file, etc.) will have
  a UUID.
  """
  @type dso_uuid :: binary()

  @type options :: keyword()

  @typedoc """
  Represents a single metadata update to a resource.

  Corresponds to a JSON Patch operation as per [RFC6902](https://tools.ietf.org/html/rfc6902)
  ("copy" and "test" operations are not implemented by DSpace). Be aware  that DSpace defines
  custom semantics on top of JSON Patch.

  ## Fields

    * `op` - The operation to perform:
      * `add` - Sets the value at the target path. Replaces the value if it already exists.
      * `remove` - Removes the value at the target path. `value` is not required.
      * `replace` - Replaces an existing value at the target path. Fails if no value exists.
      * `move` - Moves the value from `from` to `path`. `value` is not required.
    * `path` - JSON Pointer to the target location (e.g. `"/metadata/dc.title/0/value"`)
    * `value` - The value to place at the target path. Required for `:add` and `:replace`.
    * `from` - Source JSON Pointer, only used with `:move`.

  ## Examples

      %{"op" => "replace", "path" => "/metadata/dc.title/0/value", "value" => "New Title"}
  """
  @type resource_update :: %{
          required(binary()) => binary(),
          required(binary()) => binary(),
          optional(binary()) => binary() | nil,
          optional(binary()) => binary() | nil
        }

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

  The payload is a list of `t:DSpace.API.Resource.resource_update.t/0`.
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
