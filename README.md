# Vega

Vega is an iOS app built with SwiftUI.

See the short [roadmap](docs/roadmap.md) for current and planned work.

## Setup from a fresh clone

Vega currently requires Xcode 26.6 and the iOS 26.5 simulator runtime. The
default test destination is an iPhone 17 Pro simulator. Xcode supplies Swift,
`swift-format`, and the other tools needed for normal development.

Clone the repository and confirm that the intended Xcode is active:

```sh
git clone git@github.com:MikaelSiidorow/vega.git
cd vega
xcodebuild -version
```

Open `Vega.xcodeproj`, select the shared `Vega` scheme and an iPhone 17 Pro
simulator, then build once. Xcode will ask whether to trust the
`OpenAPIGenerator` build plug-in from Apple's pinned
`swift-openapi-generator` package. Review the package identity and choose
“Trust & Enable.” This approval belongs to the local Xcode installation and is
therefore expected to recur in a new ephemeral environment.

Run the complete check after approving the plug-in:

```sh
make check
```

For a trusted, non-interactive environment, the equivalent headless command is:

```sh
make check XCODEBUILD_FLAGS=-skipPackagePluginValidation
```

The committed workspace `Package.resolved` supplies the complete dependency
lock. The OpenAPI snapshots are also committed, so initial setup neither calls
the target wger server nor regenerates the schema. No signing configuration or
Apple Developer account is needed for simulator builds. Before discarding an
ephemeral environment, commit and push any work that should survive.

If Xcode 26.6 is installed but is not the active toolchain, select its actual
installation path with `xcode-select --switch` or set `DEVELOPER_DIR` for the
command. Override `IOS_SIMULATOR_DESTINATION` if the default simulator is not
installed.

## Development

Open `Vega.xcodeproj` in Xcode or open the repository in Zed. Xcode is required
to build the project.

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

Schema refresh additionally requires `curl` and `jq`; neither is needed for a
normal build from a fresh clone.

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
