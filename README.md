# dspace-ex

DSpace client library for Elixir.

## Installation

Add `:dspace` to your list of dependencies in `mix.exs`. You also need to add [Req](https://github.com/wojtekmach/req), which is used for the default HTTP client. If you want to use another client instead, you can implement the `DSpace.Api.HttpClient` contract.

```elixir
def deps do
  [
    {:dspace, git: "https://github.com/moefuerst/dspace-ex", tag: "0.0.1"},
    {:req, "~> 0.5.0"},
  ]
end
```

Run `mix deps.get` to install.

## Usage

tba

## Limitations

- This library has been developed against a DSpace-CRIS 7.x REST API. As of yet, it has not been tested against vanilla DSpace.
- No efforts were made towards a “HAL-compatible client”. The “HATEOAS design” of the DSpace REST API is a pointless exercise. [JSON is ot a hypermedia,](https://htmx.org/essays/hateoas/#hateoas-and-json) and HATEOAS doesn't solve any problems that we actually have.

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
