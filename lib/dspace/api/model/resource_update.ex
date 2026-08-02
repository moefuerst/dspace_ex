defmodule DSpace.API.Model.ResourceUpdate do
  @moduledoc """
  Represents a single update to a resource.

  Roughly corresponds to a JSON Patch operation as per
  [RFC6902](https://tools.ietf.org/html/rfc6902). Be aware that DSpace defines custom semantics on
  top of JSON Patch, and "copy" and "test" operations are not implemented.

  ## Examples

      %DSpace.API.Resource{
        op: :replace,
        path: "/metadata/dc.title/0/value",
        value: "New Title"
      }
  """
  @moduledoc since: "0.2.0"

  use DSpace.API.Model

  alias DSpace.API.Model

  @ops [:add, :remove, :replace, :move]
  @ops_strings Enum.map(@ops, &to_string/1)

  @wire %{}

  @enforce_keys [:op, :path]
  defstruct [:op, :path, :value, :from]

  @typedoc """
  A single update to a resource.

    * `op` - The update operation to perform:
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
    struct!(__MODULE__, attributes)
  end

  def new(attributes) when is_list(attributes) do
    attributes
    |> Map.new()
    |> new()
  end

  @doc """
  Creates an update structure to add a value.
  """
  @spec add(binary(), term()) :: t()
  def add(path, value) do
    struct(__MODULE__, op: :add, path: path, value: value)
  end

  @doc """
  Creates an update structure to remove a value.
  """
  @spec remove(binary()) :: t()
  def remove(path) do
    struct(__MODULE__, op: :remove, path: path)
  end

  @doc """
  Creates an update structure to replace a value.
  """
  @spec replace(binary(), term()) :: t()
  def replace(path, value) do
    struct(__MODULE__, op: :replace, path: path, value: value)
  end

  @doc """
  Creates an update structure to move a value.
  """
  @spec move(binary(), binary()) :: t()
  def move(from, path) do
    struct(__MODULE__, op: :move, from: from, path: path)
  end

  # Callbacks

  @doc """
  Creates a new update structure from a wire format map.
  """
  @impl Model
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
  Converts an update structure to a wire format map.
  """
  # Also accept a plain map to maintain backwards compatibility.
  @impl Model
  @spec to_map(t() | map()) :: map()
  def to_map(%__MODULE__{} = update), do: Model.to_map(update)
  def to_map(update) when is_map(update), do: update

  # Private helpers

  defp parse_op(op) when op in @ops_strings, do: String.to_existing_atom(op)
end
