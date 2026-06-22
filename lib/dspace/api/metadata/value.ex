defmodule DSpace.API.Metadata.Value do
  @moduledoc """
  Represents a single DSpace metadata value.

  A metadata value in DSpace can have additional properties like language, an authority key, and
  security level alongside its main content.

  This struct is not used internally by `dspace-ex`, API responses are returned as plain maps
  and deserialisation is left to the caller. You can use this struct and its functions for
  building, converting and querying metadata values in your application if you want a typed
  representation when constructing or inspecting metadata values.

  ## Example

    %{
      "dc.publisher" => [
        %DSpace.API.Metadata.Value{
          value: "Telefonaktiebolaget LM Ericsson",
          language: "se",
          authority: "550e8400-e29b-41d4-a716-446655440000",
          confidence: :accepted,
          place: 0,
          security_level: :public
        }
      ]
    }
  """

  import DSpace.Utils, only: [is_nonempty_binary: 1]

  # Value placeholder sentinel for positional correlation
  @no_value_placeholder "#PLACEHOLDER_PARENT_METADATA_VALUE#"

  @enforce_keys [:value]
  defstruct [:value, :language, :authority, :confidence, :place, :security_level]

  @typedoc """
  DSpace authority matching confidence values.

    * `:accepted` - Confirmed accurate by a user or policy
    * `:uncertain` - Valid but unconfirmed, used for programmatic relation links
    * `:ambiguous` - Multiple equally valid matches
    * `:not_found` - No matching authority values
    * `:failed` - Internal authority failure
    * `:rejected` - Authority recommends rejection
    * `:no_value` - No confidence value available
    * `:unset` - Not yet evaluated (default)
  """
  @type confidence_score ::
          :accepted | :uncertain | :ambiguous | :not_found | :failed | :rejected | :no_value | :unset

  @typedoc """
  DSpace-CRIS security levels for metadata values.

  Note that these levels are a configurable property. An instance might define additional/
  different security levels. The structure described here is the default.

    * `:public` - Available to all users (including anonymous)
    * `:trusted` - Available to authenticated users in the "Trusted" group
    * `:admin_owner` - Available only to administrators and entity owner
  """
  @type security_level :: :public | :trusted | :admin_owner

  @typedoc """
  A single DSpace metadata value.

    * `value` - The actual content (required)
    * `language` - Language code (optional)
    * `authority` - Authority key for controlled values; DSpace Object UUID or controlled
      vocabulary key (optional)
    * `confidence` - Authority matching confidence
    * `place` - Position in multi-value fields (0-based)
    * `security_level` - Access restriction level
  """
  @type t :: %__MODULE__{
          value: binary(),
          language: binary() | nil,
          authority: binary() | nil,
          confidence: confidence_score() | nil,
          place: non_neg_integer() | nil,
          security_level: security_level() | nil
        }

  # Public API

  @doc """
  Builds a plain metadata value with default confidence `:unset`.

  ## Examples

      iex> DSpace.API.Metadata.Value.new("John")
      %DSpace.API.Metadata.Value{
        value: "John",
        confidence: :unset,
        language: nil,
        authority: nil,
        place: nil,
        security_level: nil
      }

      iex> DSpace.API.Metadata.Value.new("Test", language: "en", confidence: :accepted)
      %DSpace.API.Metadata.Value{
        value: "Test",
        confidence: :accepted,
        language: "en",
        authority: nil,
        place: nil,
        security_level: nil
      }

      iex> DSpace.API.Metadata.Value.new("Test", security_level: :public)
      %DSpace.API.Metadata.Value{
        value: "Test",
        confidence: :unset,
        language: nil,
        authority: nil,
        place: nil,
        security_level: :public
      }
  """
  @spec new(binary(), keyword()) :: t()
  def new(value, opts \\ []) when is_binary(value) do
    opts = Keyword.validate!(opts, [:language, :authority, :confidence, :security_level])

    # confidence: `||` is intentional. `confidence: nil` is treated as "omitted", falling through
    # to the default. `nil` confidence is a deserialization-only artifact produced by `from_map/1`
    # when the wire JSON carries `"confidence": null`. Constructors always stamp a non-nil value.
    %__MODULE__{
      value: value,
      language: opts[:language],
      authority: opts[:authority],
      confidence: opts[:confidence] || :unset,
      security_level: opts[:security_level]
    }
  end

  @doc """
  Builds a relation (authority-linked) metadata value with `confidence: :uncertain` by default.

  ## Examples

      iex> DSpace.API.Metadata.Value.relation("Department of Physics", "550e8400-e29b-41d4-a716-446655440000")
      %DSpace.API.Metadata.Value{
        value: "Department of Physics",
        authority: "550e8400-e29b-41d4-a716-446655440000",
        confidence: :uncertain,
        language: nil,
        place: nil,
        security_level: nil
      }

      iex> DSpace.API.Metadata.Value.relation("Department", "uuid", confidence: :accepted)
      %DSpace.API.Metadata.Value{
        value: "Department",
        authority: "uuid",
        confidence: :accepted,
        language: nil,
        place: nil,
        security_level: nil
      }
  """
  @spec relation(binary(), binary(), keyword()) :: t()
  def relation(display_value, authority, opts \\ [])
      when is_nonempty_binary(display_value) and is_nonempty_binary(authority) do
    opts = Keyword.validate!(opts, [:language, :confidence, :security_level])

    %__MODULE__{
      value: display_value,
      authority: authority,
      language: opts[:language],
      confidence: opts[:confidence] || :uncertain,
      security_level: opts[:security_level]
    }
  end

  @doc """
  Builds a placeholder Value for positionally-correlated groups.

  Used when a position in a group has no value but alignment must be preserved.

  ## Examples

      iex> DSpace.API.Metadata.Value.placeholder()
      %DSpace.API.Metadata.Value{
        value: "#PLACEHOLDER_PARENT_METADATA_VALUE#",
        confidence: :unset,
        language: nil,
        authority: nil,
        place: nil,
        security_level: nil
      }
  """
  @spec placeholder() :: t()
  def placeholder, do: %__MODULE__{value: @no_value_placeholder, confidence: :unset}

  @doc """
  Converts a `Value` to a string-keyed map with DSpace API JSON field names.

  All fields are always emitted. The only exception is `"securityLevel"`: it is omitted
  when `nil`, because DSpace-CRIS treats its absence differently from an explicit `null` (absence
  means "no access restriction set"; `null` is not a valid wire value for that field).

  ## Examples

      iex> value = %DSpace.API.Metadata.Value{
      ...>   value: "test",
      ...>   language: "en",
      ...>   authority: "uuid",
      ...>   confidence: :accepted,
      ...>   place: 0,
      ...>   security_level: :public
      ...> }
      iex> DSpace.API.Metadata.Value.to_map(value)
      %{
        "value" => "test",
        "language" => "en",
        "authority" => "uuid",
        "confidence" => 600,
        "place" => 0,
        "securityLevel" => 0
      }

      iex> value = %DSpace.API.Metadata.Value{value: "test"}
      iex> DSpace.API.Metadata.Value.to_map(value)
      %{"authority" => nil, "confidence" => nil, "language" => nil, "place" => nil, "value" => "test"}
  """
  @spec to_map(t()) :: map()
  def to_map(%__MODULE__{} = value) do
    map = %{
      "value" => value.value,
      "language" => value.language,
      "authority" => value.authority,
      "confidence" => encode_confidence(value.confidence),
      "place" => value.place
    }

    maybe_put_security_level(map, value.security_level)
  end

  @doc """
  Creates a `Value` from a string-keyed DSpace API JSON map.

  Missing keys default to `nil`. Ignores unknown keys.

  ## Examples

      iex> map = %{
      ...>   "value" => "test",
      ...>   "language" => "en",
      ...>   "confidence" => 600,
      ...>   "securityLevel" => 1
      ...> }
      iex> DSpace.API.Metadata.Value.from_map(map)
      %DSpace.API.Metadata.Value{
        value: "test",
        language: "en",
        authority: nil,
        confidence: :accepted,
        place: nil,
        security_level: :trusted
      }
  """
  @spec from_map(map()) :: t()
  def from_map(%{"value" => value} = map) when is_binary(value) do
    %__MODULE__{
      value: value,
      language: map["language"],
      authority: map["authority"],
      confidence: decode_confidence(map["confidence"]),
      place: map["place"],
      security_level: decode_security_level(map["securityLevel"])
    }
  end

  @doc """
  Returns `true` if the value is a placeholder.

  Placeholders are used in positionally-correlated metadata groups where a position has no value.

  ## Examples

      iex> placeholder = DSpace.API.Metadata.Value.placeholder()
      iex> DSpace.API.Metadata.Value.placeholder?(placeholder)
      true
  """
  @spec placeholder?(t()) :: boolean()
  def placeholder?(%__MODULE__{value: @no_value_placeholder}), do: true
  def placeholder?(%__MODULE__{}), do: false

  @spec no_value_placeholder() :: binary()
  def no_value_placeholder, do: @no_value_placeholder

  # Private helpers

  defp maybe_put_security_level(map, nil), do: map

  defp maybe_put_security_level(map, level) do
    Map.put(map, "securityLevel", encode_security_level(level))
  end

  defp encode_confidence(nil), do: nil
  defp encode_confidence(:accepted), do: 600
  defp encode_confidence(:uncertain), do: 500
  defp encode_confidence(:ambiguous), do: 400
  defp encode_confidence(:not_found), do: 300
  defp encode_confidence(:failed), do: 200
  defp encode_confidence(:rejected), do: 100
  defp encode_confidence(:no_value), do: 0
  defp encode_confidence(:unset), do: -1

  defp decode_confidence(nil), do: nil
  defp decode_confidence(600), do: :accepted
  defp decode_confidence(500), do: :uncertain
  defp decode_confidence(400), do: :ambiguous
  defp decode_confidence(300), do: :not_found
  defp decode_confidence(200), do: :failed
  defp decode_confidence(100), do: :rejected
  defp decode_confidence(0), do: :no_value
  defp decode_confidence(-1), do: :unset

  defp encode_security_level(:public), do: 0
  defp encode_security_level(:trusted), do: 1
  defp encode_security_level(:admin_owner), do: 2

  defp decode_security_level(nil), do: nil
  defp decode_security_level(0), do: :public
  defp decode_security_level(1), do: :trusted
  defp decode_security_level(2), do: :admin_owner
end
