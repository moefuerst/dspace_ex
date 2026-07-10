defmodule DSpace.API.Operation.Error do
  @moduledoc """
  Represents an error when the operation can't be executed

  This error is returned when dspace_ex detects the desired operation would fail because the
  targeted DSpace instance would not support it or the client configuration would be insufficient
  to execute the operation successfully.
  """

  defexception [:not_supported, :missing_property]

  @type t :: %__MODULE__{
          not_supported: binary() | nil,
          missing_property: term() | nil
        }

  # Callbacks

  @spec message(t()) :: binary()
  @impl true
  def message(%{not_supported: dist_or_version, missing_property: missing})
      when is_binary(dist_or_version) and not is_nil(missing) do
    "a #{dist_or_version} instance doesn't support this operation " <>
      "and executing this operation requires #{inspect(missing)})"
  end

  def message(%{not_supported: dist_or_version}) when is_binary(dist_or_version) do
    "a #{dist_or_version} instance doesn't support this operation"
  end

  def message(%{missing_property: missing}) when not is_nil(missing) do
    "executing this operation requires #{inspect(missing)}"
  end
end
