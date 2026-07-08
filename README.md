# dspace_ex

An Elixir library for working with [DSpace](https://dspace.org) repositories.

## Who Is This For?

dspace_ex is designed for Elixir developers building integrations, batch processing pipelines or
migration tooling for DSpace repositories.

Whether you're moving content between institutional repositories or other data management systems,
automating metadata enrichment, or designing custom submission interfaces, dspace_ex provides an 
idiomatic Elixir interface to DSpace's JSON API. 

It translates DSpace's idiosyncratic API surface into plain, consistent terms: files are files
(not "bitstreams"), users are users (not "EPersons"), search is search, and a missing resource is
always `:not_found`— You don't need to learn DSpace's *NIH* terminology or work around the API's
quirks to build against it.

- Ingest & enrichment: submit records, update metadata, and manage files programmatically
- Export & migration: retrieve DSpace content for import into a CRIS, another repository solution
  or a custom pipeline
- Batch operations: process large sets of records efficiently using Elixir's concurrency 
  primitives

The long-term goal is complete coverage of the DSpace API, enabling everything from simple 
automation scripts to full-featured applications.


## Maintenance status

Work in progress, breaking changes are likely between releases. Help with expanding the 
functionality is always welcome!


## Installation

Add `:dspace_ex` to your dependencies in `mix.exs`. You also need to add `Req`, which is the 
default HTTP adapter used by the library.

```elixir
def deps do
  [
    {:dspace_ex, "~> 0.1.0"},
    {:req, "~> 0.5 or ~> 1.0"}
  ]
end
```

`Req` is an optional dependency. If your application uses a different HTTP client, implement the
`DSpace.API.HTTP` behaviour and configure client structs with your adapter (see docs).


## Basic usage

API interactions are composed in a functional manner. Each interaction is described as a data 
structure that can be inspected, transformed, or reused before execution. API calls are not 
executed until passed to `DSpace.API.request/3`, `DSpace.API.request!/3` or 
`DSpace.API.stream!/3`.

```elixir
client = DSpace.API.new("https://example.com/server")

{:ok, collection} =
  "a1b2c3d4-e5f6-4a7b-8c9d-0e1f2a3b4c5d"
  |> DSpace.API.Collection.fetch()
  |> DSpace.API.request(client)
```

Results are returned as string-keyed maps parsed from the response body, rather than cast into
domain structs, leaving that responsibility to the consuming application. DSpace is overly
configurable (metadata schemas, resource types, and available fields vary significantly between
instances) making a fixed struct representation difficult across the diversity of real-world
deployments.

Endpoints that return multiple resources are paginated. Each page returns a result tuple 
containing the resources, metadata, and an URL to fetch the next page:

```elixir
{:ok, {collections, meta, next_url}} =
  DSpace.API.Collection.list()
  |> DSpace.API.request(client)

{:ok, {more_collections, meta, next_url}} =
  DSpace.API.Collection.list()
  |> DSpace.API.next_page(next_url)
  |> DSpace.API.request(client)
```

`DSpace.API.stream!/3` wraps pagination automatically and returns a lazy Stream of resources:

```elixir
stream =
  DSpace.API.Collection.list()
  |> DSpace.API.stream!(client)
  |> Enum.each(&process/1)
```

If you want to parse the result page map yourself, you can override the default transformer. 
`DSpace.API.Transform.from_response/1` will return the whole response body as a map:

```elixir
{:ok, collections_page} =
  DSpace.API.Collection.list()
  |> Map.put(:transformer, &DSpace.API.Transform.from_response/1)
  |> DSpace.API.request(client)

# or

{:ok, collections_page} =
  DSpace.API.Collection.list()
  |> DSpace.API.request(client, transform: &DSpace.API.Transform.from_response/1)
```

dspace_ex tries to apply sensible transforms. For example, 
`Auth.refresh_access_token/0` will  return `{:ok, token_string}`, not a raw response. You can 
disable transformers altogether, returning a response struct with HTTP status code, all headers, 
and the response body as a map:

```elixir
{:ok, %{status: status, headers: headers, body: body}} =
  DSpace.API.Collection.list()
  |> DSpace.API.request(client, transform: false)
```


## Configuration

dspace_ex doesn't prescribe the configuration strategy of your application. To interact with the 
API, simply declare a `DSpace.API` structure with the necessary configuration when you need it:

```elixir
client = %DSpace.API{
  endpoint: "https://example.com/server",
  access_token: "my-access-token",
  csrf_token: "my-csrf-token"
}

{:ok, item} =
  "a1b2c3d4-e5f6-4a7b-8c9d-0e1f2a3b4c5d"
  |> DSpace.API.Item.fetch()
  |> DSpace.API.request(client)
```

Since `DSpace.API` is a plain struct, you can source its values however suits your application: 
hardcoded for a quick script, pulled from the application environment, or injected at runtime.

See `DSpace.API.new/1` for all client configuration options.

Note: `csrf_token` (and `access_token` if it's not an API Key) are session-scoped and must be 
obtained via authentication flow before making authenticated requests.

### Req configuration / Observability

Default options for `Req` can be set in the `http_impl` tuple when injecting the implementation
into a `DSpace.API` structure by passing a list of options. The `DSpace.API.HTTP.Req` adapter
supports passing a `:plugins` list as part of the adapter options. This lets your application
attach custom Req steps for telemetry, logging, etc. that participate in the full request/response
pipeline:

```elixir
client = %DSpace.API{
  endpoint: "https://example.com/server",
  http_impl:
    {DSpace.API.HTTP.Req,
     [
       retry: false,
       pool_timeout: 500,
       plugins: [&MyApp.ReqTelemetry.attach/1]
     ]}
}
```

You can also pass override options to `Req` when performing an operation:

```elixir
{:ok, item} =
  "a1b2c3d4-e5f6-4a7b-8c9d-0e1f2a3b4c5d"
  |> DSpace.API.Item.fetch()
  |> DSpace.API.request(client, retry: false)
```

### API Compatibility

The DSpace "REST" API is not versioned. This library is currently developed against the 2025 
version of the DSpace-CRIS fork based on DSpace 9.2. Some endpoints and behaviours differ across 
DSpace versions and distributions. dspace_ex includes version-specific overrides where the API 
differences are known.

Include the DSpace version of the instance you are connecting to in the client struct:

```elixir
client = %DSpace.API{
  endpoint: "https://example.com/server",
  version: "7.6.2"
}
```

If you run into compatibility issues with vanilla DSpace or DSpace-CRIS installations, please open 
an [Issue](https://github.com/moefuerst/dspace_ex/issues) with the DSpace version, the endpoint 
involved, and the response body returned by the server.


## Error Handling

Performing an operation with `DSpace.API.request/3` returns either `{:ok, result}` or 
`{:error, error}` where the error is one of two types:

API error (`DSpace.API.Error`). The server responded, but with a failure status or unexpected 
payload:

```elixir
item =
  uuid
  |> DSpace.API.Item.fetch() 
  |> DSpace.API.request(client)

case item do
  {:ok, item} ->
    process(item)

  {:error, %DSpace.API.Error{type: :not_found}} ->
    Logger.warning("Item not found.")

  {:error, %DSpace.API.Error{status: 500}} ->
    Logger.warning("Server error.")

  {:error, %DSpace.API.Error{} = error} ->
    Logger.warning(inspect(error))
end
```

Transport error (`DSpace.API.HTTP.Error`). The request never completed due to a connection
failure, timeout, DNS issue, etc.:

```elixir
{:error, %DSpace.API.HTTP.Error{} = error} ->
  Logger.error(Exception.message(error))
```

`DSpace.API.request!/3` and `DSpace.API.stream!/3` raise either of these errors instead of 
returning a tuple.


## Session Management

The DSpace API spec requires CSRF tokens to be monitored on every response. In practice, the
DSpace backend only rotates the token on login, logout, explicit refresh, and invalid-token 
responses. Your application is responsible for persisting the updated token between requests.

Use the `:on_response_hook` field to receive token updates. The hook is called synchronously
whenever a response includes a CSRF token in its headers:

```elixir
client = %DSpace.API{
  endpoint: "https://example.com/server",
  on_response_hook: &MyApp.Session.update_csrf/1
}
```

The hook receives `%{csrf_token: "token"}`. Because the call blocks the request pipeline, consider 
dispatching to a `GenServer` or `Task`. Configuring a hook is optional.


## Development

The project can be developed with a local Elixir/Erlang installation or through Docker.

### Using Local Elixir/Erlang

The required local tool versions are listed in `mise.toml` for use with 
[mise-en-place](https://mise.jdx.dev/) or similar tools.

```bash
mise install
mix deps.get
mix compile
```

### Using Docker

If you don't have Elixir and Erlang installed on your machine, you can fetch and install the 
dependencies with

```bash
make deps
```

and start a local development container with

```bash
make dev
```

This will drop you into an interactive bash shell inside an ephemeral application container. 
Your local working directory is mounted inside the container for development using the editing
tools on your development machine. Dependencies and build artifacts are cached in named Docker 
volumes and persist across sessions.

To show all available targets, run

```bash
make help
```


## Documentation

The project documentation is [available via HexDocs](https://dspace-ex.hexdocs.pm).

To generate it locally, run:

```bash
mix docs
```

You can then open `doc/index.html` in your browser.


## Tests

```bash
mix test
```

The test suite includes external tests that can run against a real DSpace repository for
compatibility and integration testing. These tests are excluded by default.

Only run external tests against a disposable test or development instance. They create, update,
and delete data in the target repository.

```bash
export DSPACE_ENDPOINT=https://your.dspace.instance/server
export DSPACE_VERSION="9.2.0"

# Run read-only external tests
mix test --only external --exclude requires_auth

# Run all external tests. These require admin credentials and modify data
export DSPACE_ADMIN_EMAIL=admin@example.com
export DSPACE_ADMIN_PASSWORD=secret
mix test --only external
```

A disposable DSpace stack based on a recent version of the DSpace-CRIS fork is available for 
external testing through Docker:

```bash
make test.external
```


## Code quality checks

The codebase is set up to perform quality checks using `credo`, `dialyzer` and the `styler` format
plugin. It's usually faster to not bother with individual checks and use one of the following 
aliases to run all of them.

To format your code, run all static analysis tools, and run the test suite, use:

```bash
mix precommit
```

For the checks that are performed by CI (static analysis, dependency audit, etc.), use:

```bash
mix check
```


## Contributing

Feedback and pull requests to contribute new features or fixes are most welcome. Please run 
`mix precommit` before committing your changes and `mix check` before pushing a branch. Please 
open an [Issue](https://github.com/moefuerst/dspace_ex/issues) first if your change is larger in 
scope.


## Roadmap

- Support more of the API contract
- Substantially improve e2e test coverage
- Provide better tools for constructing payloads
- Telemetry integration

## Acknowledgments

dspace_ex is built on top of [Req](https://github.com/wojtekmach/req). The approach around the 
operation protocol was inspired by [ex-aws](https://github.com/ex-aws).


## License

Copyright (C) 2026 The dspace_ex Project Contributors  
Copyright (C) 2025-2026 Moritz F. Fürst

This project is licensed under the GNU Affero General Public License, Version 3.0 only.

Pursuant to Section 14 of the GNU Affero General Public License, Version 3.0, Moritz F. Fürst is
hereby designated as the proxy who is authorized to issue a public statement accepting any future
version of the GNU Affero General Public License for use with this Program. Therefore,
notwithstanding the specification that this Program is licensed under the GNU Affero General
Public License, Version 3.0 only, a public acceptance by the Designated Proxy of any subsequent
version of the GNU Affero General Public License shall permanently authorize the use of that
accepted version for this Program.
