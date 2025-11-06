defmodule DSpace.API.Monitor do
  @moduledoc """
  Functions for calling the monitoring endpoints of the DSpace API.
  """

  import DSpace.API.Utils

  alias DSpace.API.Operation

  @ep_monitor "/actuator"
  @ep_health @ep_monitor <> "/health"
  @ep_info @ep_monitor <> "/info"

  # Public API

  @doc """
  Fetches the health status of the DSpace API.

  ## Parameters
    * `component`: The name of the system component to check the health status of. If not
      provided, the combined health status of the API will be returned.

  Retrieving the health status of individual system components requires administrator privileges.
  """
  @spec health(nil | binary()) :: Operation.t()
  def health(component \\ nil)

  def health(nil) do
    %Operation.Query{path: @ep_health}
  end

  def health(component) when is_nonempty_binary(component) do
    %Operation.Query{path: @ep_health <> "/" <> component}
  end

  @doc """
  Fetches application information from the DSpace API.

  Usually this will return the API version, mail configuration, urls to Solr, the Angular
  application and the database, and similar information.

  Executing this operation requires administrator privileges.
  """
  @spec info() :: Operation.t()
  def info do
    %Operation.Query{path: @ep_info}
  end
end
