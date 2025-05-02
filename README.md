# dspace-ex

DSpace client library for Elixir.

## Usage

Create an API client configured with your DSpace REST endpoint URL. Here is an example of fetching a DSpace Item by its UUID. You can try it out by starting an IEx shell with `iex -S mix`:

```elixir
iex> client = DSpace.Api.new("https://your.dspace.instance/server")
iex> {:ok, item} = DSpace.Api.Item.fetch(client, "f6b7c7e8-a2d9-45b0-8a7c-7e8d9f0b1c2d")
iex> IO.inspect(item.dspace_object.name)
"Making reliable distributed systems in the presence of software errors" # Example output
```

To perform actions requiring authentication, you need to log in or provide an API key:

```elixir
iex> username = "your_dspace_username"
iex> password = "your_dspace_password"
iex> {:ok, auth_client} = DSpace.Api.login(client, username, password)
iex> # auth_client now contains tokens needed for authenticated requests:
iex> IO.inspect(auth_client)
%DSpace.Api{
  # access_token: #<hidden>,
  # csrf_token: #<hidden>,
  api_version: "7.6.1",
  client_impl: {DSpace.Api.Http.Req, [json: true]},
  endpoint: "https://your.dspace.instance/server"
}
iex> # (Note: `access_token` and `csrf_token` are hidden from `IO.inspect`
iex> # for security reasons.)
iex> #
iex> # If you obtain tokens separately (e.g., API key from config, CSRF
iex> # from a refresh), update the client:
iex> api_key = "your_jwt_access_token"
iex> csrf_token = "your_csrf_token"
iex> client_with_tokens =
...>   client
...>   |> DSpace.Api.with_access_token(api_key)
...>   |> DSpace.Api.with_csrf_token(csrf_token)
```

For modifying data, such as creating a Collection, you use the authenticated client. A [CSRF token is necessary](#api-authentication-and-csrf) as well.

```elixir
iex> parent_community = "a1b2c3d4-e5f6-7890-abcd-ef1234567890"
iex> collection = %{
...>   "name" => "My Test Collection",
...>   "metadata" => %{
...>     "dc.title" => [%{"value" => "My Test Collection", "language" => "en"}]
...>   }
...> }
iex> {:ok, new_collection} = DSpace.Api.Collection.create(auth_client, collection, parent_community)
iex> # Inspect the newly created collection's details
iex> IO.inspect(new_collection)
```

Refer to the [Documentation](#documentation) for all features.

## Installation

Add `:dspace` to your list of dependencies in `mix.exs`. You also need to add [Req](https://github.com/wojtekmach/req), which is used as the default HTTP client. If your project uses another client, you can implement the `DSpace.Api.Http` contract and pass the implementation to the `DSpace.Api` module.

```elixir
def deps do
  [
    {:dspace, git: "https://github.com/moefuerst/dspace-ex", tag: "0.0.1"},
    {:req, "~> 0.5.0"},
  ]
end
```

Run `mix deps.get` to install.

## Limitations

### WIP
This library is a work in progress, and mostly covers retrieval and manipulation of what is called an “item” in DSpace. Help with expanding the functionality is always welcome!

### API Authentication and "CSRF"
A peculiarity of the DSpace API's design is the misapplication of CSRF protection— the API blends session-based mechanics with REST semantics and requires a CSRF token with all unsafe methods (`POST`, `PUT`, `PATCH`, etc.), regardless of client or endpoint.

At the moment, this library doesn't abstract this uncommon requirement too much, with one exception: the login flow. `dspace-ex` handles the steps internally— you can authenticate directly using `DSpace.Api.login/3` without needing to manually fetch a token beforehand.

For all other unsafe requests, you must:

1. Either log in, or, if using an API key, make an initial `GET` request to any endpoint to receive a CSRF token
2. Capture and persist the CSRF token
3. Include this token for all subsequent unsafe HTTP requests (e.g., creating, updating, or deleting resources)
4. Maintain “session” continuity, as the CSRF token may be refreshed

For your convenience, the request building pipeline will fail fast if a CSRF token is not provided for modifying operations (i.e. before actually making the request). Additionally, the helper function `DSpace.Api.with_csrf_from_response/2` (see docs) is provided to help you manage the token.

### Compatibility
This library has been developed against a DSpace-CRIS 7.x API. As of yet, it has not been tested against vanilla DSpace. Basic CRUD operations should work, but ymmv.

### Category error is not addressed
No efforts are being made towards a “HAL-compatible client”. The “HATEOAS design” of the DSpace REST API is a pointless exercise. [JSON is not a hypermedia,](https://htmx.org/essays/hateoas/#hateoas-and-json) and HATEOAS doesn't solve any problems that we actually have. JSON APIs are [consumed by code, not humans with agency](https://intercoolerjs.org/2016/05/08/hatoeas-is-for-humans.html).

## Documentation

The project documentation can be generated with `mix docs`. You can then open `doc/index.html` in your browser.

## Tests

```shell
$ mix test
```

## Contributing

Pull requests to contribute new features or enhancements are most welcome. Please run `mix format` and an analysis with `mix dialyzer` and `mix credo` before committing your changes.

## License

Licensed under the GNU Affero General Public License v3.0 or later. See the [LICENSE](./LICENSE) file for details. We encourage adoption in public educational institutions, libraries, museums, government agencies, and research organizations. If your institution faces any legal or procurement challenges with AGPLv3, we offer a **permissive, non-commercial use exemption**.
