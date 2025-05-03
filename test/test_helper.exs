defmodule TestHelper do
  @doc """
  Helper to respond with JSON content type and a pre-formatted JSON string body (for use with Bypass)
  """
  def respond_with_json(conn, status_code, json_body_string) do
    conn
    |> Plug.Conn.put_resp_content_type("application/json")
    |> Plug.Conn.resp(status_code, json_body_string)
  end

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
