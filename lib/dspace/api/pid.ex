defmodule DSpace.API.PID do
  @moduledoc """
  Operations for working with persistent identifiers.
  """

  import DSpace.Utils, only: [is_nonempty_binary: 1]

  alias DSpace.API.Operation

  @ep_resolve "/api/pid/find"

  # Public API

  @doc """
  Resolves a persistent identifier to a "DSpace Object" resource.

  Attempts to find a "DSpace Object" matching the provided identifier (DOI, Handle, etc.). If
  found, redirects the request to the endpoint for that resource.

  Executing this operation will return the resource or an API error.
  """
  @spec resolve(binary()) :: Operation.JSON.t()
  def resolve(identifier) when is_nonempty_binary(identifier) do
    %Operation.JSON{
      path: @ep_resolve,
      params: [id: identifier]
    }
  end
end
