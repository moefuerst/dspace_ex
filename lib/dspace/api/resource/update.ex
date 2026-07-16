defmodule DSpace.API.Resource.Update do
  @moduledoc """
  Represents a single update to a resource.

  Roughly corresponds to a JSON Patch operation as per
  [RFC6902](https://tools.ietf.org/html/rfc6902). Be aware that DSpace defines custom semantics on
  top of JSON Patch and "copy" and "test" operations are not implemented.

  ## Examples

      %DSpace.API.Resource{
        op: :replace,
        path: "/metadata/dc.title/0/value",
        value: "New Title"
      }
  """
  @moduledoc since: "0.2.0"

  @ops [:add, :remove, :replace, :move]
  @ops_strings Enum.map(@ops, &to_string/1)

  @enforce_keys [:op, :path]
  defstruct [:op, :path, :value, :from]

  @typedoc """
  A single update to a resource.

    * `op` - The operation to perform:
      * `:add` - Sets the value at the target path. Replaces the value if it already exists.
      * `:remove` - Removes the value at the target path. `value` is not required.
      * `:replace` - Replaces an existing value at the target path. Fails if no value exists.
      * `:move` - Moves the value from `from` to `path`. `value` is not required.
    * `path` - JSON Pointer to the target location (e.g. `"/metadata/dc.title/0/value"`)
    * `value` - The value to place at the target path. Required for `:add` and `:replace`.
    * `from` - Source JSON Pointer, only used with `:move`.
  """
  @type t :: %__MODULE__{
          op: op(),
          path: binary(),
          value: term() | nil,
          from: binary() | nil
        }

  @type op :: :add | :remove | :replace | :move

  # Public API

  @doc """
  Creates a new update structure.
  """
  @spec new(map() | keyword()) :: t()
  def new(%{op: op} = attributes) when op in @ops do
    struct(__MODULE__, attributes)
  end

  def new(attributes) when is_list(attributes) do
    attributes
    |> Map.new()
    |> new()
  end

  @doc """
  Creates a new update structure from a map.
  """
  @spec from_map(map()) :: t()
  def from_map(map) do
    new(%{
      op: parse_op(map["op"]),
      path: map["path"],
      value: map["value"],
      from: map["from"]
    })
  end

  @doc """
  Converts an update structure to a map.
  """
  @spec to_map(t()) :: map()
  def to_map(update) do
    %{
      "op" => to_string(update.op),
      "path" => update.path
    }
    |> maybe_put("value", update.value)
    |> maybe_put("from", update.from)
  end

  @doc """
  Normalizes an update to a map.
  """
  @spec normalize(t() | map()) :: map()
  def normalize(%__MODULE__{} = update), do: to_map(update)
  def normalize(map) when is_map(map), do: map

  # Private helpers

  defp parse_op(op) when op in @ops_strings, do: String.to_existing_atom(op)

  defp maybe_put(map, _key, nil), do: map
  defp maybe_put(map, key, value), do: Map.put(map, key, value)
end
