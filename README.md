# dspace-ex

DSpace client library for Elixir.

## Usage

tba

## Installation

Add `:dspace` to your list of dependencies in `mix.exs`. You also need to add [Req](https://github.com/wojtekmach/req), which is used as the default HTTP client. If your project uses another client, you can implement the `DSpace.Api.HttpClient` contract and pass the implementation to the `DSpace.Api` module.

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

### Category error is not addressed
No efforts are being made towards a “HAL-compatible client”. The “HATEOAS design” of the DSpace REST API is a pointless exercise. [JSON is not a hypermedia,](https://htmx.org/essays/hateoas/#hateoas-and-json) and HATEOAS doesn't solve any problems that we actually have. JSON APIs are [consumed by code, not humans with agency](https://intercoolerjs.org/2016/05/08/hatoeas-is-for-humans.html).

### API Authentication and "CSRF"
A peculiarity of the DSpace REST API's design is the misapplication of CSRF protection— the API requires a CSRF token with all unsafe methods (`POST`, `PUT`, `PATCH`, etc.), even for non-browser clients, even for the auth endpoint.

At the moment, this library doesn't abstract this uncommon requirement. You must:

1. Make an initial `GET` request (to any endpoint) to receive a CSRF token
2. Use that token to authenticate via login (if necessary)
3. Keep using the token (which may be refreshed) for all subsequent unsafe methods

For your convenience, the request building pipeline will fail fast if a CSRF token is not provided for modifying operations (i.e. before actually making the request). Additionally, the helper functions `DSpace.Api.with_token_from_response/2` and `DSpace.Api.Response.extract_csrf/1` (see docs) are provided to help you manage the token.

### Compatibility

This library has been developed against a DSpace-CRIS 7.x API. As of yet, it has not been tested against vanilla DSpace. Basic CRUD operations should work, but ymmv.

## Documentation

The project documentation can be generated with `mix docs`. You can then open `doc/index.html` in your browser.

## Tests

```shell
$ mix test
```

## Contributing

Pull requests to contribute new features or enhancements are most welcome. Please run `mix format` and an analysis with `mix credo` before committing your changes.

## License

This project is licensed under the AGPL-3.0. See the [LICENSE](./LICENSE) file for details.
