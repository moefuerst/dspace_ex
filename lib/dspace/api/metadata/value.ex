defmodule DSpace.Api.Metadata.Value do
  @moduledoc """
  Represents a single DSpace REST API metadata value.

  Provides runtime validation of metadata values according to DSpace's constraints.

  A metadata value in DSpace can have additional properties like language, an authority key, and security level alongside its main content.

  ## Example

  %DSpace.Api.Metadata.Value{
    value: "Telefonaktiebolaget LM Ericsson",
    language: "se",
    authority: "550e8400-e29b-41d4-a716-446655440000",
    confidence: 600,
    place: 0
  }

  """

  @typedoc """
  DSpace API metadata value

  ## Fields
  * `value` - The actual content (required)
  * `language` - language code
  * `authority` - Authority key for controlled values; UUID or controlled vocabulary key
  * `confidence` - Authority matching confidence (-1 to 600)
  * `place` - Position in multi-value fields (0-based)
  * `securityLevel` - Access restriction level (0 = Public, 1 = "Trusted" group, 2 = Admin/Owner)
  """
  @type t :: %__MODULE__{
          value: binary(),
          language: language_code() | nil,
          authority: authority_key() | nil,
          confidence: confidence_score() | nil,
          place: place_number() | nil,
          securityLevel: security_level() | nil
        }

  @type language_code :: binary()

  @typedoc """
  Authority key identifies controlled vocabulary terms or entities:
  * UUID - For internal DSpace entities (items, collections etc)
  * String - For external authority controls (ORCID, funders etc)
  """
  @type authority_key :: binary()

  @typedoc """
  Authority matching confidence values:
  * 600 - Accepted: Confirmed accurate by a user or policy
  * 500 - Uncertain: Valid but unconfirmed by a user
  * 400 - Ambiguous: Multiple equally valid matches
  * 300 - Not Found: No matching authority values
  * 200 - Failed: Internal authority failure
  * 100 - Rejected: Authority recommends rejection
  *   0 - No Value: No confidence value available
  *  -1 - Unset: Not yet evaluated (default)
  """
  @type confidence_score :: -1 | 0 | 100 | 200 | 300 | 400 | 500 | 600

  @typedoc """
  Position in multi-value fields:
  * 0..n - Zero-based index for ordered values
  """
  @type place_number :: non_neg_integer()

  @typedoc """
  DSpace-CRIS security levels for metadata values:
  * 0 - Public: Available to all users (including anonymous)
  * 1 - Trusted: Available to authenticated users in the "Trusted" group
  * 2 - Admin/Owner: Available only to administrators and entity owner
  """
  @type security_level :: 0 | 1 | 2

  @enforce_keys [:value]
  defstruct [
    :value,
    :language,
    :authority,
    :confidence,
    :place,
    # sic! camelcase
    :securityLevel
  ]

  @schema NimbleOptions.new!(
            value: [
              type: :map,
              required: true,
              keys: [
                value: [
                  type: :string,
                  required: true
                ],
                language: [
                  type: :string
                ],
                authority: [
                  type: :string
                ],
                confidence: [
                  type: {:in, [-1, 0, 100, 200, 300, 400, 500, 600]},
                  default: -1
                ],
                place: [
                  type: :non_neg_integer
                ],
                # sic! camelcase
                securityLevel: [
                  type: {:in, [0, 1, 2]}
                ]
              ]
            ]
          )

  # Public API

  @doc """
  Creates a new Value struct from a map of attributes.
  """
  @spec new(map()) :: t()
  def new(attrs) when is_map(attrs) do
    struct!(__MODULE__, attrs)
  end

  @doc """
  Returns the metadata value schema.
  """
  @spec schema() :: NimbleOptions.t() | NimbleOptions.ValidationError.t()
  def schema, do: @schema

  @doc """
  Validates a metadata value map against the schema.
  """
  @spec validate(map()) :: {:ok, map()} | {:error, NimbleOptions.ValidationError.t()}
  def validate(metadata) when is_map(metadata) do
    NimbleOptions.validate(metadata, @schema)
  end

  @spec validate!(map()) :: map() | NimbleOptions.ValidationError.t()
  def validate!(metadata) when is_map(metadata) do
    NimbleOptions.validate!(metadata, @schema)
  end
end
