# Vega

Vega is an independent, native, local-first SwiftUI client for self-hosted
[wger](https://wger.de) fitness and nutrition servers. It focuses on making
frequent nutrition and workout tracking feel fast and at home on iOS, including
when the network is unavailable.

Vega is an early-stage, unofficial project. It is not affiliated with or
endorsed by the wger project.

See the short [roadmap](docs/roadmap.md) for current and planned work.

## Relationship to wger

Vega is a native SwiftUI client built against wger's documented HTTP and
PowerSync contracts. Most of the implementation is original Swift code;
selected interaction patterns, including the focused workout sequence and
PowerSync upload behavior, are adapted from the
[official wger Flutter client](https://github.com/wger-project/flutter). The
[wger server](https://github.com/wger-project/wger), Flutter client, and Vega
are licensed under the GNU Affero General Public License.

The checked-in OpenAPI snapshots originate from a wger 2.7 server and are
mechanically normalized for Apple's Swift OpenAPI Generator. Vega does not
bundle wger's exercise, ingredient, or image catalogs. See [NOTICE.md](NOTICE.md)
for provenance and third-party licensing details.

## Local-first data

Weight, nutrition plans and goals, diary history, recent foods, routines,
workout sessions, and set logs read and write through a per-account PowerSync
SQLite database. Changes are available immediately offline and upload when the
connection returns. Authentication, PowerSync credentials, ingredient/barcode
search, and the workout schedule that wger does not yet synchronize continue to
use REST. The account menu exposes the current sync state and queued changes.

See [PowerSync architecture](docs/powersync.md) for the data boundary, retry and
isolation rules, server compatibility, and exact upstream references.

## Setup from a fresh clone

Vega currently requires Xcode 26.6 and the iOS 26.5 simulator runtime. The
default test destination is an iPhone 17 Pro simulator. Xcode supplies Swift,
`swift-format`, and the other tools needed for normal development.

Clone the repository and confirm that the intended Xcode is active:

```sh
git clone https://github.com/MikaelSiidorow/vega.git
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

To build on a physical device, create the ignored local signing configuration
and replace the placeholder with your Apple Developer team ID:

```sh
cp Config/Local.xcconfig.example Config/Local.xcconfig
```

Keep machine-specific signing settings in `Config/Local.xcconfig` instead of
selecting a team in the project file. The app's Debug and Release configurations
optionally include that file through the committed `Config/Base.xcconfig`.

If Xcode 26.6 is installed but is not the active toolchain, select its actual
installation path with `xcode-select --switch` or set `DEVELOPER_DIR` for the
command. Override `IOS_SIMULATOR_DESTINATION` if the default simulator is not
installed.

## Development

Open `Vega.xcodeproj` in Xcode or open the repository in Zed. Xcode is required
to build the project.

The `WgerAPI` local Swift package generates public Swift models and a typed
client from the checked-in wger 2.7 OpenAPI snapshot. Xcode's workspace-level
`Package.resolved` is the single lockfile for the app and its local packages.
Build the API package with:

```sh
make build-wger-api
```

Refresh the snapshot intentionally from a compatible wger 2.7 server, then
rebuild it, with:

```sh
WGER_SCHEMA_URL=https://your-wger.example/api/v2/schema make refresh-wger-schema
make build-wger-api
```

Schema refresh additionally requires `curl` and `jq`; neither is needed for a
normal build from a fresh clone.

`refresh-wger-schema` rejects schemas outside the wger 2.7 series. It keeps
the verbatim server response in `server-openapi.json` and derives
`openapi.json` for Apple's generator. The derivation verifies the corrected
ingredient, nutrition-plan, and resolved workout-day contracts, and keeps one
narrow nullability correction for unset workout targets. It also keeps JSON
request bodies and omits unsupported image/video upload mutations and their
request-only schemas. Their read and delete operations remain available.
Generated Swift files are build artifacts and are not committed.

Format the handwritten Swift sources with:

```sh
make format
```

Run the formatter in lint mode, compile the app and generated API, and execute
the unit tests with:

```sh
make check
```

Run the slower simulator UI tests separately with:

```sh
make test-ui
```

The test destination defaults to the latest iPhone 17 Pro simulator. Override
`IOS_SIMULATOR_DESTINATION` when using a different installed simulator.

GitHub Actions runs `make check` on the standard Apple Silicon macOS 26 runner
with Xcode 26.6. Adding the `run-ui-tests` label to a pull request runs the UI
suite after the standard check and exports its screenshots. Swift package
checkouts and compatible Xcode build products are cached between both jobs.
Each run keeps its Xcode result bundle and exported UI-test screenshots as an
artifact for seven days.

Refresh the complete Xcode build metadata used by SourceKit-LSP:

```sh
make build-for-testing
```

## License

Vega is licensed under the
[GNU Affero General Public License, version 3 or later](LICENSE), with an
[additional permission for app-store distribution](NOTICE.md#app-store-exception).
The corresponding source remains available through this repository.
