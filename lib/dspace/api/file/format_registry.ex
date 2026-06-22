defmodule DSpace.API.File.FormatRegistry do
  @moduledoc """
  Provides functions to access and write the File format registry.
  """

  import DSpace.Utils, only: [pop_pagination: 1]

  alias DSpace.API.Operation
  alias DSpace.API.StreamBuilder
  alias DSpace.API.Transform

  @ep_core "/api/core/bitstreamformats"

  # Public API

  @doc """
  Fetches a single file format by ID.
  """
  @spec fetch(non_neg_integer(), keyword()) :: Operation.t()
  def fetch(id, _options \\ []) when is_integer(id) do
    %Operation.JSON{path: @ep_core <> "/" <> to_string(id)}
  end

  @doc """
  Lists the file formats defined in the registry.

  This operation can be streamed.

  ## Options

    * `:page` - Page number (0-based, defaults to 0)
    * `:size` - Number of items per page (usually defaults to 20)
  """
  @spec list(keyword()) :: Operation.JSON.t()
  def list(options \\ []) do
    {pagination, other_options} = pop_pagination(options)

    op = %Operation.JSON{
      path: @ep_core,
      params: pagination ++ other_options,
      transformer:
        &Transform.transform_collection(&1,
          extract: ["_embedded", "bitstreamformats"]
        )
    }

    %{op | stream_impl: &StreamBuilder.new(&1, op, &2)}
  end

  @doc """
  Creates a new file format in the registry.

  This operation requires administrator privileges.
  """
  @spec create(map(), keyword()) :: Operation.t()
  def create(format, _options \\ []) when is_map(format) do
    %Operation.JSON{
      path: @ep_core,
      http_method: :post,
      data: format
    }
  end

  @doc """
  Replaces an existing file format in the registry.
  """
  @spec replace(non_neg_integer(), map(), keyword()) :: Operation.t()
  def replace(id, format, _options \\ []) when is_integer(id) and is_map(format) do
    %Operation.JSON{
      path: @ep_core <> "/" <> to_string(id),
      http_method: :put,
      data: format
    }
  end

  @doc """
  Deletes a file format.
  """
  @spec delete(non_neg_integer(), keyword()) :: Operation.t()
  def delete(id, _options \\ []) when is_integer(id) do
    %Operation.JSON{
      path: @ep_core <> "/" <> to_string(id),
      http_method: :delete,
      transformer: fn _ -> :ok end
    }
  end
end
