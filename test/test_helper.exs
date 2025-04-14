defmodule TestHelper do
  @doc """
  Loads a JSON fixture as a string (for use with Bypass)
  """
  def load_fixture(path) do
    Path.join(["test", "support", "fixtures", path])
    |> File.read!()
  end

  @doc """
  Parses a JSON fixture (direct assertions)
  """
  def parse_fixture(path) do
    load_fixture(path)
    |> Jason.decode!()
  end
end

ExUnit.configure(exclude: :integration)
ExUnit.start()

Application.ensure_all_started(:bypass)
Application.ensure_all_started(:req)
