defmodule DSpace.Api.Response.Page do
  @moduledoc """
  Represents pagination information in an API response

  Provides utilities for handling pagination in API responses.
  See [section on pagination in the Rest7Contract](https://github.com/4Science/Rest7Contract?tab=readme-ov-file#pagination)
  """

  defstruct [
    :number,
    :size,
    :total_elements,
    :total_pages,
    :next_page,
    :prev_page,
    :first_page,
    :last_page
  ]

  @typedoc """
  Pagination information from an API response.

  ## Fields
  * `number` - Current page number (zero-based)
  * `size` - Actual page size returned
  * `total_elements` - Total items available
  * `total_pages` - Total pages available
  * `next_page` - URL for next page if exists
  * `prev_page` - URL for previous page if exists
  * `first_page` - URL for first page
  * `last_page` - URL for last page
  """
  @type t :: %__MODULE__{
          number: non_neg_integer(),
          size: pos_integer(),
          total_elements: non_neg_integer(),
          total_pages: non_neg_integer(),
          next_page: binary() | nil,
          prev_page: binary() | nil,
          first_page: binary() | nil,
          last_page: binary() | nil
        }

  @doc """
  Creates page parameters for requests.

  ## Options
  * `:page` - Page number (zero-based, default: 0)
  * `:size` - Items per page (must be positive, default: 20)
  * `:sort` - Sort criteria ("field,asc|desc")
  """
  @spec params(keyword()) :: keyword()
  def params(opts \\ []) do
    page = Keyword.get(opts, :page, 0)
    size = Keyword.get(opts, :size, 20)
    sort = Keyword.get(opts, :sort)

    opts = [page: page, size: size]
    if sort, do: Keyword.put(opts, :sort, sort), else: opts
  end

  @doc """
  Adds pagination parameters to request options.
  """
  @spec add_params_to_options(keyword(), keyword()) :: keyword()
  def add_params_to_options(options, page_options) do
    page_params = params(page_options)
    existing_params = Keyword.get(options, :params, [])
    Keyword.put(options, :params, Keyword.merge(existing_params, page_params))
  end

  @doc """
  Prepares options for a "next page" request based on a response.

  Returns `nil` if there's no next page.
  """
  @spec next(map(), keyword()) :: keyword() | nil
  def next(response, options) do
    case get_in(response.body, ["_links", "next", "href"]) do
      next_url when is_binary(next_url) ->
        uri = URI.parse(next_url)
        page_params = URI.decode_query(uri.query || "") |> Map.to_list()
        existing_params = Keyword.get(options, :params, [])

        options
        # Remove base endpoint to avoid concatenation
        |> Keyword.delete(:base_url)
        # Full url from the response
        |> Keyword.put(:url, next_url)
        |> Keyword.put(:params, Keyword.merge(existing_params, page_params))

      _ ->
        nil
    end
  end

  @doc """
  Creates a Page struct from an API response.
  """
  @spec from_response(map()) :: t()
  def from_response(%{"page" => page_info, "_links" => links}) do
    %__MODULE__{
      number: page_info["number"],
      size: page_info["size"],
      total_elements: page_info["totalElements"],
      total_pages: page_info["totalPages"],
      next_page: get_in(links, ["next", "href"]),
      prev_page: get_in(links, ["prev", "href"]),
      first_page: get_in(links, ["first", "href"]),
      last_page: get_in(links, ["last", "href"])
    }
  end

  def from_response(_), do: nil
end
