defprotocol DSpace.API.Operation do
  @moduledoc """
  Defines a protocol for executing operations on a DSpace API.
  """

  @doc """
  Performs a synchronous request on a DSpace API, returning a result or an error.
  """
  def perform(operation, client, options)

  @doc """
  Performs a streaming request on a DSpace API.
  """
  def stream!(operation, client, options)
end
