defmodule DSpace.API.Search do
  @moduledoc """
  Operations for working with DSpace search ("discovery").

  Provides functionality for searching across "DSpace objects" including items, collections, and
  communities. Supports faceted search, filtering, and sorting.
  """

  import DSpace.Utils, only: [is_nonempty_binary: 1, pop_pagination: 1]

  alias DSpace.API.HTTP.Response
  alias DSpace.API.Operation
  alias DSpace.API.StreamBuilder
  alias DSpace.API.Transform

  @ep_search "/api/discover/search"
  @ep_objects_search @ep_search <> "/objects"
  @ep_search_facets @ep_search <> "/facets"

  @typedoc """
  Options for search operations.
  """
  @type search_options :: [
          query: binary(),
          scope: binary(),
          configuration: atom() | binary(),
          filters: [filter()],
          sort: sort()
        ]

  @typedoc """
  A search filter specification.
  """
  @type filter :: %{filter: binary(), operator: binary(), value: binary()}

  @typedoc """
  A sort specification.
  """
  @type sort :: binary() | atom() | {binary() | atom(), :asc | :desc}

  # Public API

  @doc """
  Performs a search query using the "Discovery" search endpoint.

  This function takes either

    * a search query as a string or
    * a search context as a keyword list of options

  This operation can be streamed.

  ## Options

    * `:query` - The search query string (optional for scope-only searches)
    * `:scope` - UUID of a specific DSpace container (community, collection, etc.) to limit search
      scope
    * `:configuration` - Name of Discovery configuration to use as a string or atom
      * `:workspace` - Search user's draft items (requires authentication)
      * `:workflow` - Search editorial workflow items (requires authentication)
      * Custom configuration names as defined in the DSpace instance's `discovery.xml`
    * `:filters` - List of filter maps to refine search results. Each filter must have:
      * `:filter` - The filter (e.g., "itemtype", "title", "author", "subject", "dateIssued")
      * `:operator` - The filter operator (e.g., "equals", "notequals", "contains", "notcontains",
        "authority", "notauthority")
      * `:value` - The filter value to match against
    * `:sort` - Sort specification for results. Can be:
      * A string or atom for field name (defaults to ascending order)
      * A tuple `{field, direction}` where direction is `:asc` or `:desc`. Common sort fields:
        * `"score"` - Relevance score (use `:desc` for most relevant first)
        * `"dc.date.issued"` - Publication date
        * `"dc.date.accessioned"` - Date added to repository
        * `"dc.title"` - Title (use `:asc` for A-Z alphabetical)
    * `:page` - Page number (0-based, defaults to 0)
    * `:size` - Number of items per page (usually defaults to 20)
  """
  @spec query(query_string :: binary() | search_options()) :: Operation.JSON.t()
  def query(options) when is_list(options) do
    params = build_query_params(options)

    op = %Operation.JSON{
      path: @ep_objects_search,
      params: params,
      transformer: &transform_search_result/1
    }

    %{op | stream_impl: &StreamBuilder.new(&1, op, &2)}
  end

  def query(query) when is_nonempty_binary(query) do
    query(query: query)
  end

  @doc """
  Fetches information on the search configuration.

  Returns the available filters, operators, and sort options.
  """
  @spec fetch_config() :: Operation.JSON.t()
  def fetch_config do
    %Operation.JSON{path: @ep_search}
  end

  @doc """
  Fetches the available search filters and their specifications.
  """
  @spec fetch_filters() :: Operation.JSON.t()
  def fetch_filters do
    %Operation.JSON{
      path: @ep_search,
      transformer: &Transform.get(&1, "filters")
    }
  end

  @doc """
  Fetches the available sort options.
  """
  @spec fetch_sort_options() :: Operation.JSON.t()
  def fetch_sort_options do
    %Operation.JSON{
      path: @ep_search,
      transformer: &Transform.get(&1, "sortOptions")
    }
  end

  @doc """
  Fetches available facets for the given search context.

  Returns facets that can be used to refine search results. Uses the same search context (query,
  scope, configuration, filters) but returns facet information instead of search results.

  This operation can be streamed.

  ## Parameters

    * `options` - Search context and pagination options, see `query/1` options
  """
  @spec fetch_facets(keyword()) :: Operation.JSON.t()
  def fetch_facets(options \\ []) do
    params = build_query_params(options)

    op = %Operation.JSON{
      path: @ep_search_facets,
      params: params,
      transformer: &Transform.transform_collection(&1, extract: ["_embedded", "facets"])
    }

    %{op | stream_impl: &StreamBuilder.new(&1, op, &2)}
  end

  @doc """
  Fetches values for a specific search facet.

  Retrieves the possible values and their counts for a single facet field. Useful for building
  facet selection interfaces.

  This operation can be streamed.

  ## Parameters

    * `facet_name` - The name of the facet (e.g., "author", "subject", "dateIssued")
    * `options` - Search context and pagination options, see `query/1` options
  """
  @spec fetch_facet_values(binary(), keyword()) :: Operation.JSON.t()
  def fetch_facet_values(facet_name, options \\ []) when is_nonempty_binary(facet_name) do
    params = build_query_params(options)

    op = %Operation.JSON{
      path: @ep_search_facets <> "/" <> facet_name,
      params: params,
      transformer: &Transform.transform_collection(&1, extract: ["_embedded", "values"])
    }

    %{op | stream_impl: &StreamBuilder.new(&1, op, &2)}
  end

  # Private helpers

  defp build_query_params(options) do
    {query_params, options} = Keyword.split(options, [:configuration, :filters])
    {pagination_params, options} = pop_pagination(options)

    Enum.concat([
      options,
      build_configuration_param(query_params[:configuration]),
      build_filter_params(query_params[:filters]),
      pagination_params
    ])
  end

  defp build_configuration_param(nil), do: []
  defp build_configuration_param(config) when is_binary(config), do: [configuration: config]
  defp build_configuration_param(config) when is_atom(config), do: [configuration: Atom.to_string(config)]

  defp build_filter_params(nil), do: []

  defp build_filter_params(filters) when is_list(filters) do
    Enum.map(filters, fn %{filter: filter, operator: operator, value: value} ->
      {"f." <> filter, value <> "," <> operator}
    end)
  end

  defp transform_search_result(%Response{body: body}) when is_map(body) do
    search_result = get_in(body, ["_embedded", "searchResult"]) || %{}
    results = get_in(search_result, ["_embedded", "objects"]) || []

    data = Enum.map(results, &get_in(&1, ["_embedded", "indexableObject"]))

    meta =
      body
      |> Map.drop(["_embedded", "_links"])
      |> Map.merge(%{
        "facets" => get_in(body, ["_embedded", "facets"]) || [],
        "page" => Map.get(search_result, "page") || %{},
        "_links" => Map.get(search_result, "_links") || %{}
      })

    next = get_in(search_result, ["_links", "next", "href"])

    {data, meta, next}
  end
end
