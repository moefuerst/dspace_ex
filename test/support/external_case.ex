defmodule DSpace.ExternalCase do
  @moduledoc """
  This module defines the setup for tests that require a real DSpace instance.
  """

  use ExUnit.CaseTemplate

  using do
    quote do
      import DSpace.ExternalCase

      @moduletag :external
    end
  end

  setup do
    endpoint = DSpace.ExternalCase.get_env!("DSPACE_ENDPOINT")
    {:ok, endpoint: endpoint}
  end

  def get_env!(name) do
    case System.get_env(name) do
      nil -> raise "Missing required environment variable: #{name}"
      value -> value
    end
  end

  def get_env(name, default \\ nil) do
    System.get_env(name, default)
  end

  @doc """
  Creates a DSpace API client for testing.

  Handles authentication if credentials are provided.
  """
  @spec dspace_test_api(boolean()) :: DSpace.Api.t()
  def dspace_test_api(authenticate \\ false) do
    endpoint = get_env!("DSPACE_ENDPOINT")
    api_token = get_env("DSPACE_ADMIN_APITOKEN")

    client =
      if api_token do
        DSpace.Api.new(endpoint, api_token)
      else
        DSpace.Api.new(endpoint)
      end

    if authenticate and is_nil(api_token) do
      email = get_env!("DSPACE_ADMIN_EMAIL")
      password = get_env!("DSPACE_ADMIN_PASSWORD")

      case DSpace.Api.login(client, email, password) do
        {:ok, authenticated_client} -> authenticated_client
        {:error, error} -> raise "Authentication failed: #{inspect(error)}"
      end
    else
      client
    end
  end
end
