defmodule DSpace.Api.Object do
  @moduledoc """
  Common attributes shared by all DSpace Objects (communities, collections, items, bundles, bitstreams, e-persons, groups, policies, etc.)
  """

  defstruct [
    :uuid,
    :name,
    :handle,
    :type,
    :last_modified,
    links: %{}
  ]

  @typedoc """
  _links structure. ("HAL" "convention")

  Example link relations:
  * `self`: Direct URL to this object
  * `bundles`: List of bundles (for items)
  * `owningCollection`: Parent collection (for items)
  * `mappedCollections`: Additional collections this object appears in (for items)
  * `relationships`: Entity relationships (for items)
  * `version`: Version information
  * `thumbnail`: A thumbnail image
  """
  @type links :: %{binary() => %{href: binary()}}

  @typedoc """
  Base DSpace object structure shared by all repository objects.

  Fields:
  * `uuid`: Unique identifier
  * `name`: Human-readable name/title
  * `handle`: URI
  * `type`: Object type ("community", "collection", "item")
  * `last_modified`: Modification timestamp
  * `links`: Link relations
  """
  @type t :: %__MODULE__{
          uuid: binary(),
          name: binary() | nil,
          handle: binary() | nil,
          type: binary(),
          last_modified: DateTime.t() | nil,
          links: links()
        }

  # Public API

  @doc false
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
