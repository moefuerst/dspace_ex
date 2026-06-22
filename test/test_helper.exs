defmodule TestHelper do
  @moduledoc false

  defmodule HTTP do
    @moduledoc false
    @behaviour DSpace.API.HTTP

    @impl true
    def request(options) do
      send(self(), {:http_request, options})

      status =
        Keyword.get(options, :test_return_status, 200)

      headers =
        Keyword.get(options, :test_return_headers, %{"content-type" => ["application/json"]})

      body =
        Keyword.get(options, :test_return_body, %{"response" => "ok"})

      {:ok, %DSpace.API.HTTP.Response{status: status, headers: headers, body: body}}
    end
  end

  @doc """
  Responds with DSpace's JSON content type and a pre-formatted JSON string body
  (for use with Bypass)
  """
  def respond_with_json(conn, status_code, json_body_string) do
    conn
    |> Plug.Conn.put_resp_content_type("application/hal+json")
    |> Plug.Conn.resp(status_code, json_body_string)
  end

  @doc """
  Loads a JSON fixture as a string (for use with Bypass)
  """
  def load_fixture(path) do
    ["test", "support", "fixtures", path]
    |> Path.join()
    |> File.read!()
  end

  @doc """
  Parses a JSON fixture (direct assertions)
  """
  def parse_fixture(path) do
    path
    |> load_fixture()
    |> JSON.decode!()
  end
end

ExUnit.configure(exclude: :external)
ExUnit.start()

Application.ensure_all_started(:bypass)
Application.ensure_all_started(:req)
