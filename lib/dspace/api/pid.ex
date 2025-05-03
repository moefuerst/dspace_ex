defmodule DSpace.Api.Pid do
  @moduledoc """
  Provides functionality for persistent identifiers.
  """

  import DSpace.Utils.Guards

  alias DSpace.Api
  alias DSpace.Api.Error
  alias DSpace.Api.Object
  alias DSpace.Api.Response

  @ep_url "/api/pid"

  defmodule Identifier do
    @moduledoc """
    Represents an Identifier resource.
    """
    defstruct [
      :value,
      :identifier_type,
      :identifier_status
      # superfluous :id field ignored (== :value)
      # superfluous :type field ignored (always "identifier")
      # "HATEOAS" :_links field ignored
    ]

    @typedoc """
    A DSpace identifier resource.

    ## Fields:
    * `value`: The actual identifier value (e.g., DOI URL, Handle URL).
    * `identifier_type`: The type of the identifier (e.g., "doi", "handle").
    * `identifier_status`: The registration status for DOIs (e.g., "TO_BE_REGISTERED", "REGISTERED", null).
    """
    @type t :: %__MODULE__{
            value: binary(),
            identifier_type: binary(),
            identifier_status: binary() | nil
          }

    @doc false
    @spec from_response(map()) :: t()
    def from_response(body) when is_map(body) do
      %__MODULE__{
        value: body["value"],
        identifier_type: body["identifierType"],
        identifier_status: body["identifierStatus"]
      }
    end

    def from_response(_), do: %__MODULE__{}
  end

  # Public API

  @doc """
  Resolves a persistent identifier to a DSpace Object.

  Attempts to find a DSpace Object matching the provided identifier (DOI, Handle, etc.)
  """
  @spec resolve(api :: Api.t(), identifier :: binary()) ::
          {:ok, Object.t()} | {:error, Error.t() | Exception.t()}
  def resolve(%Api{} = api, identifier) when is_not_empty(identifier) do
    options = [
      url: "#{@ep_url}/find",
      params: [id: identifier]
    ]

    case Api.request(api, options) do
      {:ok, response} -> {:ok, Object.from_response(response.body)}
      {:error, _} = error -> error
    end
  end

  @doc """
  Finds all persistent identifiers associated with a specific item.
  """
  @spec find_by_item(api :: Api.t(), item_uuid :: binary()) ::
          {:ok, [Identifier.t()]} | {:error, Error.t() | Exception.t()}
  def find_by_item(%Api{} = api, item_uuid) when is_not_empty(item_uuid) do
    options = [
      url: "#{@ep_url}/identifiers/search/findByItem",
      params: [uuid: item_uuid]
    ]

    case Api.request(api, options) do
      {:ok, response} ->
        identifiers =
          Response.extract_resources(response.body, ["_embedded", "identifiers"])
          |> Enum.map(&Identifier.from_response/1)

        {:ok, identifiers}

      {:error, _} = error ->
        error
    end
  end

  @doc """
  Mints and queues a DOI for registration for a given item.

  The item must already exist.
  """
  @spec register_doi(api :: Api.t(), item_uuid :: binary()) ::
          {:ok, Identifier.t()} | {:error, Error.t() | Exception.t()}
  def register_doi(api, item_uuid) when is_not_empty(item_uuid) do
    # DSpace expects the full Item URI in the body
    item_uri = "#{api.endpoint}/api/core/items/#{item_uuid}"

    options = [
      method: :post,
      url: "#{@ep_url}/identifiers",
      params: [type: "doi"],
      body: item_uri,
      auth: {:bearer, api.access_token},
      headers: [
        {"content-type", "text/uri-list"},
        {"x-xsrf-token", api.csrf_token}
      ],
      json: false
    ]

    case Api.request(api, options) do
      {:ok, %{body: body} = _response} -> {:ok, Identifier.from_response(body)}
      {:error, _} = error -> error
    end
  end
end
