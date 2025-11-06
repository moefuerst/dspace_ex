defmodule DSpace.API.PID do
  @moduledoc """
  Functions for working with persistent identifiers.
  """

  import DSpace.API.Utils

  alias DSpace.API.Operation

  @ep_resolve "/api/pid/find"

  # Public API

  @doc """
  Resolves a persistent identifier to a "DSpace Object" resource.

  Attempts to find a "DSpace Object" matching the provided identifier (DOI, Handle, etc.).
  If found, redirects the request to the endpoint for that resource. Executing this operation will
  return the resource or an API error.
  """
  @spec resolve(binary()) :: Operation.Query.t()
  def resolve(identifier) when is_nonempty_binary(identifier) do
    %Operation.Query{
      path: @ep_resolve,
      params: [id: identifier]
    }
  end
end
