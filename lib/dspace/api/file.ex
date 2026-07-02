defmodule DSpace.API.File do
  @moduledoc """
  Functions for working with DSpace Files.

  In DSpace-speak a file is called a "Bitstream". Every "Bitstream" lives inside a "Bundle", a
  named grouping of different files attached to an Item (the most common are `ORIGINAL` for the
  deposited files, `THUMBNAIL` for generated previews, and `LICENSE`).

  In dspace_ex, a file is called a "file". You're welcome.
  """

  @behaviour DSpace.API.Resource

  import DSpace.Utils, only: [is_nonempty_binary: 1, maybe_add_base_url: 2, pop_pagination: 1]

  alias DSpace.API
  alias DSpace.API.Error
  alias DSpace.API.HTTP.Response
  alias DSpace.API.Item
  alias DSpace.API.Operation
  alias DSpace.API.Resource
  alias DSpace.API.StreamBuilder
  alias DSpace.API.Transform

  @ep_bitstreams "/api/core/bitstreams"
  @ep_bundles "/api/core/bundles"
  @ep_formats "/api/core/bitstreamformats"

  @default_bundle_name "ORIGINAL"

  @typedoc """
  A file to upload.

  Can be either

    * a path to a file on disk as a string (read at request time, filename derived from the path)
    * a `{filename, content}` tuple where `content` is a binary or a stream
    * a `{filename, content, content_type}` tuple to additionally set the part's MIME type
  """
  @type upload ::
          binary()
          | {binary(), iodata() | Enumerable.t()}
          | {binary(), iodata() | Enumerable.t(), binary()}

  # Public API

  @doc """
  Uploads a file to an item.

  A file must always be created inside a "bundle", so adding a file to an item is really two API
  requests: (1) create the target bundle with `create_bundle/2`, then (2) `create_in_bundle/3` the
  file into it. Executing this operation chains both steps: it creates a bundle on the parent item
  and then creates the file inside it, returning the created file.

  ## Parameters

    * `file` - the file to upload, see `t:upload/0`
    * `options` - keyword list of options

  ## Options

    * `:parent` - UUID of the parent item (required)
    * `:bundle` - optional bundle attributes map, see `create_bundle/2`
    * `:properties` - optional file properties map, see `create_in_bundle/3`

  ## Examples

      File.upload("files/test.pdf", parent: item_uuid)

      File.upload({"report.pdf", pdf_binary, "application/pdf"},
        parent: item_uuid,
        bundle: %{"name" => "ORIGINAL"},
        properties: %{"metadata" => %{"dc.description" => [%{"value" => "Final report"}]}}
      )
  """
  @spec upload(upload(), keyword()) :: Operation.t()
  def upload(file, options \\ []) when is_list(options) do
    parent = Keyword.fetch!(options, :parent)
    bundle = Keyword.get(options, :bundle, %{})
    properties = Keyword.get(options, :properties, %{})

    Operation.Chain.new([
      fn _nil, context -> {create_bundle(bundle, parent: parent), context} end,
      fn %{"uuid" => bundle_uuid}, context ->
        {create_in_bundle(bundle_uuid, file, properties: properties), context}
      end
    ])
  end

  @doc """
  Downloads a file binary.

  This operation will pass a `:decode_body` option with `false` to the HTTP adapter, so the bytes
  are returned verbatim regardless of the file's content type.

  Restricted files require a short-lived authentication token passed as an option (see
  `DSpace.API.Auth.fetch_short_lived_token/0`).

  ## Streaming to disk

  `Req` supports streaming the response body straight to disk which is useful especially for large
  files. If you use a Req-based HTTP adapter (which is this library's default), passing `:into` as
  an override option to `DSpace.API.request/3` will stream the body to disk:

      uuid
      |> File.download()
      |> DSpace.API.request(client, into: File.stream!("myfile.pdf"))

  ## Options

    * `:auth_token` - short-lived token granting access to a restricted file
  """
  @spec download(binary(), keyword()) :: Operation.JSON.t()
  def download(uuid, options \\ []) when is_nonempty_binary(uuid) and is_list(options) do
    params =
      case Keyword.get(options, :auth_token) do
        nil -> []
        token -> ["authentication-token": token]
      end

    %Operation.JSON{
      path: @ep_bitstreams <> "/" <> uuid <> "/content",
      params: params,
      transformer: fn %Response{body: body} -> body end,
      before_step: &disable_body_decoding/3
    }
  end

  @doc """
  Fetches a single file via its parent item's handle.

  Either `:sequence` or `:file_name` option must be given.

  ## Options

    * `:sequence` - the file's sequence id as an integer
    * `:file_name` - the file's name as a string
  """
  @spec fetch_by_item_handle(binary(), keyword()) :: Operation.JSON.t()
  def fetch_by_item_handle(handle, options \\ []) when is_nonempty_binary(handle) and is_list(options) do
    {sequence, options} = Keyword.pop(options, :sequence)
    {file_name, _options} = Keyword.pop(options, :file_name)

    params =
      Keyword.merge(
        [handle: handle],
        Enum.reject([sequence: sequence, filename: file_name], fn {_, v} -> is_nil(v) end)
      )

    %Operation.JSON{
      path: @ep_bitstreams <> "/search/byItemHandle",
      params: params,
      expected_status: [200, 204],
      transformer: &not_found_on_no_content(&1, "No file found matching the given parameters")
    }
  end

  @doc """
  Uploads a new file binary into a bundle.

  ## Parameters

    * `bundle_uuid` - UUID of the bundle the file is created in
    * `file` - the file to upload, see `t:upload/0`
    * `options` - keyword list of options

  ## Options

    * `properties` - optional properties map. Supports `"name"` (stored filename) and
      `"metadata"`. If `"name"` is absent, the upload's filename is used.

  Note: If the payload is passed in form of a path to a file on disk, the file will only be read
  from disk when the request is actually sent with `DSpace.API.request/3`, not when calling this
  function.

  ## Examples

      # From a path on disk
      File.create_in_bundle(bundle_uuid, "files/test.pdf")

      # From in-memory content with metadata
      File.create_in_bundle(bundle_uuid, {"report.pdf", pdf_binary, "application/pdf"}, %{
        "metadata" => %{"dc.description" => [%{"value" => "Final report"}]}
      })
  """
  @spec create_in_bundle(binary(), upload(), keyword()) :: Operation.JSON.t()
  def create_in_bundle(bundle_uuid, file, options \\ []) when is_nonempty_binary(bundle_uuid) and is_list(options) do
    properties = Keyword.get(options, :properties, %{})

    %Operation.JSON{
      path: @ep_bundles <> "/" <> bundle_uuid <> "/bitstreams",
      http_method: :post,
      content_type: :multipart,
      data: %{file: file, properties: properties},
      before_step: &build_upload_payload/3
    }
  end

  @doc """
  Finds the files of an item within a bundle.

  This operation can be streamed.

  ## Parameters

    * `item_uuid` - UUID of the item
    * `bundle_name` - name of the bundle (e.g. `"ORIGINAL"`)
    * `options` - keyword list of options

  ## Options

    * `:filters` - list of `{metadata_field, value}` tuples to filter by
    * `:exclude_hidden` - when `true`, excludes files flagged with the `bitstream.hide` metadata
      (default: `false`)
    * `:page` - Page number (0-based)
    * `:size` - Items per page
  """
  @spec find_by_item(binary(), binary(), keyword()) :: Operation.JSON.t()
  def find_by_item(item_uuid, bundle_name, options \\ [])
      when is_nonempty_binary(item_uuid) and is_nonempty_binary(bundle_name) do
    {exclude_hidden, options} = Keyword.pop(options, :exclude_hidden, false)
    {filters, options} = Keyword.pop(options, :filters, [])
    {pagination, _options} = pop_pagination(options)

    endpoint =
      if exclude_hidden do
        "/search/showableByItem"
      else
        "/search/byItemId"
      end

    params =
      [uuid: item_uuid, name: bundle_name]
      |> Keyword.merge(build_metadata_filters(filters))
      |> Keyword.merge(pagination)

    op = %Operation.JSON{
      path: @ep_bitstreams <> endpoint,
      params: params,
      transformer: &Transform.transform_collection(&1, extract: ["_embedded", "bitstreams"])
    }

    %{op | stream_impl: &StreamBuilder.new(&1, op, &2)}
  end

  @doc """
  Lists the files within a bundle.

  This operation can be streamed.

    ## Options

    * `:page` - Page number (0-based)
    * `:size` - Items per page
  """
  @spec list_in_bundle(binary(), keyword()) :: Operation.JSON.t()
  def list_in_bundle(bundle_uuid, options \\ []) when is_nonempty_binary(bundle_uuid) do
    {pagination, other_options} = pop_pagination(options)

    op = %Operation.JSON{
      path: @ep_bundles <> "/" <> bundle_uuid <> "/bitstreams",
      params: pagination ++ other_options,
      transformer: &Transform.transform_collection(&1, extract: ["_embedded", "bitstreams"])
    }

    %{op | stream_impl: &StreamBuilder.new(&1, op, &2)}
  end

  @doc """
  Fetches the thumbnail of a file.

  Note: Thumbnails are usually only available for files in the `ORIGINAL` bundle.
  """
  @spec thumbnail(binary()) :: Operation.JSON.t()
  def thumbnail(uuid) when is_nonempty_binary(uuid) do
    %Operation.JSON{
      path: @ep_bitstreams <> "/" <> uuid <> "/thumbnail",
      expected_status: [200, 204],
      transformer: &not_found_on_no_content(&1, "No thumbnail found for this file")
    }
  end

  @doc """
  Moves a file to another bundle.
  """
  @spec move(binary(), binary()) :: Operation.JSON.t()
  def move(uuid, bundle_uuid) when is_nonempty_binary(uuid) and is_nonempty_binary(bundle_uuid) do
    %Operation.JSON{
      path: @ep_bitstreams <> "/" <> uuid <> "/bundle",
      http_method: :put,
      content_type: :uri_list,
      data: bundle_uuid,
      before_step: &build_bundle_uri/3
    }
  end

  @doc """
  Sets the file as the primary file of a bundle.

  Use this when the bundle has no primary file yet; use `make_primary/2` to change an existing
  one.
  """
  @spec set_primary(binary(), binary()) :: Operation.JSON.t()
  def set_primary(uuid, bundle_uuid) when is_nonempty_binary(uuid) and is_nonempty_binary(bundle_uuid) do
    %Operation.JSON{
      path: @ep_bundles <> "/" <> bundle_uuid <> "/primaryBitstream",
      http_method: :post,
      content_type: :uri_list,
      data: uuid,
      before_step: &build_file_uri/3
    }
  end

  @doc """
  Makes the file the primary file of a bundle.

  Executing this operation changes the primary file of a bundle that already has one. Use
  `set_primary/2` when the bundle has no primary file yet.
  """
  @spec make_primary(binary(), binary()) :: Operation.JSON.t()
  def make_primary(uuid, bundle_uuid) when is_nonempty_binary(uuid) and is_nonempty_binary(bundle_uuid) do
    %Operation.JSON{
      path: @ep_bundles <> "/" <> bundle_uuid <> "/primaryBitstream",
      http_method: :put,
      content_type: :uri_list,
      data: uuid,
      before_step: &build_file_uri/3
    }
  end

  @doc """
  Fetches the format of a file.
  """
  @spec format(binary()) :: Operation.JSON.t()
  def format(uuid) when is_nonempty_binary(uuid) do
    %Operation.JSON{path: @ep_bitstreams <> "/" <> uuid <> "/format"}
  end

  @doc """
  Assigns a registered format to a file.

  ## Parameters

    * uuid - the UUID of the file
    * format_id - the integer id of a format in the "format registry"
      (see `DSpace.API.File.FormatRegistry`).
  """
  @spec set_format(binary(), integer() | binary()) :: Operation.JSON.t()
  def set_format(uuid, format_id) when is_nonempty_binary(uuid) do
    %Operation.JSON{
      path: @ep_bitstreams <> "/" <> uuid <> "/format",
      http_method: :put,
      content_type: :uri_list,
      data: to_string(format_id),
      before_step: &build_format_uri/3
    }
  end

  @doc """
  Fetches a file bundle by UUID.
  """
  @spec fetch_bundle(binary()) :: Operation.JSON.t()
  def fetch_bundle(bundle_uuid) when is_nonempty_binary(bundle_uuid) do
    %Operation.JSON{path: @ep_bundles <> "/" <> bundle_uuid}
  end

  @doc """
  Creates a new file bundle.

  A file bundle *must* have an item parent.

  ## Parameters

    * `bundle` - bundle attributes as a map. Supports `"name"` (defaults to `"ORIGINAL"`) and
      `"metadata"`.
    * `options` - keyword list of options

  ## Options

    * `:parent` - UUID of the parent item (required)
  """
  @spec create_bundle(map(), keyword()) :: Operation.JSON.t()
  def create_bundle(bundle \\ %{}, options \\ []) when is_map(bundle) and is_list(options) do
    parent = Keyword.fetch!(options, :parent)

    Item.create_file_bundle(parent, bundle)
  end

  @doc """
  Deletes a file bundle.

  Executing this operation also deletes all files in the bundle.
  """
  @spec delete_bundle(binary()) :: Operation.JSON.t()
  def delete_bundle(bundle_uuid) when is_nonempty_binary(bundle_uuid) do
    %Operation.JSON{
      path: @ep_bundles <> "/" <> bundle_uuid,
      http_method: :delete,
      transformer: fn _ -> :ok end
    }
  end

  @doc """
  Fetches the primary file of a file bundle.
  """
  @spec fetch_primary_from_bundle(binary()) :: Operation.JSON.t()
  def fetch_primary_from_bundle(bundle_uuid) when is_nonempty_binary(bundle_uuid) do
    %Operation.JSON{
      path: @ep_bundles <> "/" <> bundle_uuid <> "/primaryBitstream",
      expected_status: [200, 204],
      transformer: &not_found_on_no_content(&1, "Primary file not found for this bundle")
    }
  end

  @doc """
  Removes the primary-file designation from a file bundle.

  This does *not* delete the file or remove it from the bundle; it only clears the "primary"
  designation.
  """
  @spec clear_primary(binary()) :: Operation.JSON.t()
  def clear_primary(bundle_uuid) when is_nonempty_binary(bundle_uuid) do
    %Operation.JSON{
      path: @ep_bundles <> "/" <> bundle_uuid <> "/primaryBitstream",
      http_method: :delete,
      transformer: fn _ -> :ok end
    }
  end

  @doc """
  Reorders the files within a bundle.

  Takes the raw list of move operations, e.g. to move the file at index 1 to the front:

      File.reorder(bundle_uuid, [
        %{
          "op" => "move",
          "from" => "/_links/bitstreams/1/href",
          "path" => "/_links/bitstreams/0/href"
        }
      ])
  """
  @spec reorder(binary(), [map()]) :: Operation.JSON.t()
  def reorder(bundle_uuid, move_operations) when is_nonempty_binary(bundle_uuid) and is_list(move_operations) do
    %Operation.JSON{
      path: @ep_bundles <> "/" <> bundle_uuid,
      http_method: :patch,
      data: move_operations
    }
  end

  @doc false
  def default_bundle_name, do: @default_bundle_name

  # Callbacks

  @doc """
  Fetches a single file by UUID.
  """
  @impl Resource
  @spec fetch(binary(), keyword()) :: Operation.JSON.t()
  def fetch(uuid, _options) when is_nonempty_binary(uuid) do
    %Operation.JSON{path: @ep_bitstreams <> "/" <> uuid}
  end

  @doc """
  Lists files within a bundle.

  The main "bitstreams" endpoint is not browsable, so listing is always bundle-scoped. Equivalent
  to `list_in_bundle/2`.

  This operation can be streamed.

  ## Options

    * `:bundle` - Required. UUID of the bundle to list files from
    * `:page` - Page number (0-based)
    * `:size` - Items per page
  """
  @impl Resource
  @spec list(keyword()) :: Operation.JSON.t()
  def list(options \\ []) when is_list(options) do
    case Keyword.pop(options, :bundle) do
      {bundle_uuid, other_options} when is_nonempty_binary(bundle_uuid) ->
        list_in_bundle(bundle_uuid, other_options)

      _ ->
        raise ArgumentError, "listing files requires a :bundle option (a bundle UUID)"
    end
  end

  @doc """
  Updates a file's metadata.
  """
  @impl Resource
  @spec update(binary(), [Operation.JSON.t()], keyword()) :: Operation.JSON.t()
  def update(uuid, updates, _options) when is_nonempty_binary(uuid) and is_list(updates) do
    %Operation.JSON{
      path: @ep_bitstreams <> "/" <> uuid,
      http_method: :patch,
      data: updates
    }
  end

  @doc """
  Deletes one or more files.

  All files in a bulk delete must be attached to an item.
  """
  @impl Resource
  @spec delete(binary() | [binary()], keyword()) :: Operation.JSON.t()
  def delete(uuid_or_uuids, options \\ [])

  def delete(uuids, _options) when is_list(uuids) do
    operations =
      Enum.map(
        uuids,
        fn uuid -> %{"op" => "remove", "path" => "/bitstreams/" <> uuid} end
      )

    %Operation.JSON{
      path: @ep_bitstreams,
      http_method: :patch,
      data: operations,
      # Bulk delete returns 204, unlike a regular PATCH.
      expected_status: [204],
      transformer: fn _ -> :ok end
    }
  end

  def delete(uuid, _options) when is_nonempty_binary(uuid) do
    %Operation.JSON{
      path: @ep_bitstreams <> "/" <> uuid,
      http_method: :delete,
      transformer: fn _ -> :ok end
    }
  end

  # Private helpers

  # Sic, DSpace returns 204 if these requested resources are not found
  defp not_found_on_no_content(%Response{status: 204} = response, message) do
    Error.exception(type: :not_found, status: 404, message: message, response: response)
  end

  defp not_found_on_no_content(response, _message), do: Transform.from_response(response)

  defp disable_body_decoding(operation, client, options) do
    {operation, client, Keyword.put(options, :decode_body, false)}
  end

  defp build_upload_payload(%{data: %{file: file, properties: properties}} = operation, client, options) do
    {filename, content, content_type} = normalize_file(file)
    properties = Map.put_new(properties, "name", filename)

    file_field =
      if content_type do
        {content, filename: filename, content_type: content_type}
      else
        {content, filename: filename}
      end

    fields = %{
      file: file_field,
      properties: {JSON.encode!(properties), content_type: "application/json"}
    }

    {%{operation | data: fields}, client, options}
  end

  defp normalize_file(path) when is_binary(path) do
    {Path.basename(path), Elixir.File.read!(path), nil}
  end

  defp normalize_file({filename, content}) when is_binary(filename) do
    {filename, content, nil}
  end

  defp normalize_file({filename, content, content_type}) when is_binary(filename) and is_binary(content_type) do
    {filename, content, content_type}
  end

  defp build_metadata_filters(filters) do
    Enum.flat_map(
      filters,
      fn {field, value} -> [filterMetadata: field, filterMetadataValue: value] end
    )
  end

  defp build_format_uri(%{data: id} = operation, %API{endpoint: endpoint} = client, options) do
    uri = maybe_add_base_url(@ep_formats <> "/" <> id, endpoint)

    {%{operation | data: [uri]}, client, options}
  end

  defp build_bundle_uri(%{data: uuid} = operation, %API{endpoint: endpoint} = client, options) do
    uri = maybe_add_base_url(@ep_bundles <> "/" <> uuid, endpoint)

    {%{operation | data: [uri]}, client, options}
  end

  defp build_file_uri(%{data: uuid} = operation, %API{endpoint: endpoint} = client, options) do
    uri = maybe_add_base_url(@ep_bitstreams <> "/" <> uuid, endpoint)

    {%{operation | data: [uri]}, client, options}
  end
end
