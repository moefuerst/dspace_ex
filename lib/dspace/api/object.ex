defmodule DSpace.Api.Object do
  @moduledoc """
  Common attributes shared by all DSpace Objects (communities, collections, items, bundles, bitstreams, e-persons, groups, policies, etc.)
  """

  @typedoc """
  _links structure.

  Example link relations:
  - `self`: Direct URL to this object
  - `bundles`: List of bundles (for items)
  - `owningCollection`: Parent collection (for items)
  - `mappedCollections`: Additional collections this object appears in (for items)
  - `relationships`: Entity relationships (for items)
  - `version`: Version information
  - `thumbnail`: A thumbnail image
  """
  @type links :: %{binary() => %{href: binary()}}

  @typedoc """
  Base DSpace object structure shared by all repository objects.

  Fields:
  - `uuid`: Unique identifier
  - `name`: Human-readable name/title
  - `handle`: Persistent identifier in the handle system
  - `type`: Object type ("community", "collection", "item")
  - `last_modified`: Last modification timestamp
  - `links`: links to related resources
  """
  @type t :: %__MODULE__{
          uuid: binary(),
          name: binary() | nil,
          handle: binary() | nil,
          type: binary(),
          last_modified: DateTime.t() | nil,
          links: links()
        }

  defstruct [
    :uuid,
    :name,
    :handle,
    :type,
    :last_modified,
    links: %{}
  ]

  ### Public API

  @doc """
  Creates an Object struct from a DSpace API response.
  """
  @spec from_response(map()) :: t()
  def from_response(body) when is_map(body) do
    %__MODULE__{
      uuid: body["uuid"],
      name: body["name"],
      handle: body["handle"],
      type: body["type"],
      last_modified: body["lastModified"],
      links: Map.get(body, "_links", %{})
    }
  end

  def from_response(_), do: %__MODULE__{}
end
