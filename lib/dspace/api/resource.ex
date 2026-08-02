defmodule DSpace.API.Resource do
  @moduledoc """
  Specifies the behaviour of an API resource module.
  """

  alias DSpace.API.Model.ResourceUpdate
  alias DSpace.API.Operation

  @typedoc """
  Represents a "DSpace Object" UUID.

  Most repository entities (community, collection, item, user, user group, file, etc.) called
  "objects" in DSpace-speak will have such a UUID.
  """
  @type dso_uuid :: binary()

  @typedoc """
  Represents a single metadata update to a resource.

  Can be either

    * a `t:DSpace.API.Model.ResourceUpdate.t/0`
    * a plain string-keyed map

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
  @type update :: ResourceUpdate.t() | %{required(binary()) => binary() | nil}

  @typedoc """
  Represents the preferred language for metadata when retrieving a resource.

  Note that if the preferred language is not available for a given metadata value, all language
  variants of that value will be returned by the server.

  Can be either

    * `:all` - Returns all language variants (default)
    * a language tag as an atom or string (e.g. `:en`).
    * a list of language tags as atoms or strings (e.g. `[:en, :de_AT]`). This will send an
      `Accept-Language` header with quality values derived from list order
    * an `Accept-Language` header value as a string (e.g.`en-US,en;q=0.9,zh-CN;q=0.8,zh;q=0.7`).
    * an `Accept-Language` header (e.g. `%{:accept_language => ["fr-CH,fr;q=0.9,en;q=0.8,de;q=0.7"]}}`)
    * `nil` - Returns the server default
  """
  @type preferred_language ::
          :all | atom() | binary() | [atom() | binary()] | %{required(atom()) => [binary()]} | nil

  @type options :: keyword()

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

  The payload is a list of `t:update/0`.
  """
  @callback update(dso_uuid(), [update()], options()) :: Operation.t()

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
