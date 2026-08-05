# Vega

Vega is an iOS app built with SwiftUI.

See the short [roadmap](docs/roadmap.md) for current and planned work.

## Development

Open `Vega.xcodeproj` in Xcode or open the repository in Zed. Xcode is required to build the project.

The `WgerAPI` local Swift package generates public Swift models and a typed
client from the checked-in wger 2.6.0 OpenAPI snapshot. Xcode's workspace-level
`Package.resolved` is the single lockfile for the app and its local packages.
Build the API package with:

```sh
make build-wger-api
```

Refresh the snapshot from the target server, then rebuild it, with:

```sh
make refresh-wger-schema
make build-wger-api
```

`refresh-wger-schema` rejects schemas that do not report wger 2.6.0. It keeps
the verbatim server response in `server-openapi.json` and derives
`openapi.json` for Apple's generator. The derivation keeps JSON request bodies
and omits unsupported image/video upload mutations and their seven request-only
schemas. Their read and delete operations remain available. Generated Swift
files are build artifacts and are not committed.

Format the handwritten Swift sources with:

```sh
make format
```

Run the formatter in lint mode, compile the app and generated API, and execute
the unit and UI tests with:

```sh
make check
```

The test destination defaults to the latest iPhone 17 Pro simulator. Override
`IOS_SIMULATOR_DESTINATION` when using a different installed simulator.

GitHub Actions runs the same `make check` command on macOS 26 with Xcode 26.6.
Swift package checkouts and compatible Xcode build products are cached using the
workspace lockfile and build configuration as the cache key.

Refresh the complete Xcode build metadata used by SourceKit-LSP:

```sh
make build-for-testing
```
