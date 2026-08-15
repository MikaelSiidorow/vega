# PowerSync architecture

Vega is local-first for the personal data it currently supports. SwiftUI models
read strictly typed domain values from repositories backed by PowerSync's native
SQLite database. Local creates, edits, and deletes are committed immediately;
PowerSync records them in `ps_crud` and uploads them when connectivity returns.

## Data ownership

| Feature | Read/write path | Notes |
| --- | --- | --- |
| Weight history | PowerSync | Offline create, edit, and delete use client UUIDs. |
| Nutrition plans and goals | PowerSync | The active plan and goal fields are resolved locally. |
| Diary, meals, and recent foods | PowerSync | Recent foods are ranked client-side from local diary history. Referenced ingredient and serving-unit rows are synchronized for typed hydration. |
| Routines, workout sessions, and set logs | PowerSync | A session and its first set log are inserted in one SQLite transaction. |
| Resolved workout-day schedule | REST, then local cache | Wger does not currently publish the resolved day/slot structure through PowerSync. All other workout data remains local-first. |
| Authentication and PowerSync credentials | REST | The Keychain retains the host, refresh token, and access token so an already-synchronized account can open offline. |
| Ingredient and barcode search | REST | Search is intentionally server-backed; selected results become readable through synchronized diary references. |

If SQLite cannot be opened, repositories use their typed REST implementation.
If a new database opens but has not completed its first download, an empty local
result temporarily yields REST data while the SQLite observation remains active.
After synchronized rows arrive, the same stream switches to local values.

## Isolation and upload behavior

Each host and JWT subject receives a separate database named from a truncated
SHA-256 digest of `canonical host URL | subject`. Switching accounts closes the
active database before opening the other account's file. Explicit sign-out
disconnects, clears, and deletes the current account's local database.

The connector follows Wger's upload contract:

- `GET /api/v2/powersync-token` supplies the endpoint and short-lived token.
- `PUT`, `PATCH`, and `DELETE /api/v2/upload-powersync-data` receive `{table,
  data}`. Foreign-key `_id` suffixes are removed and Django `DateField` values
  are reduced to `YYYY-MM-DD`.
- `401`, `408`, `429`, transport errors, and `5xx` throw without completing the
  transaction, so PowerSync retries it.
- Other permanent failures, including Wger's `200 {"error": ...}` response,
  are recorded for the account menu and completed so one invalid operation does
  not permanently block the queue.

The account menu shows connectivity, active transfer, queued write, and
permanent-rejection states. Its reconnect action disconnects and reopens the
current PowerSync connection. The SwiftUI weight, diary, and workout models
consume SQLite observation streams, so both local writes and downloaded changes
render without a REST reload.

## Compatibility and references

The project pins [PowerSync Swift 1.16.0](https://github.com/powersync-ja/powersync-swift/tree/1.16.0)
and uses the native `PowerSyncDatabase` API described by the
[official Swift SDK guide](https://docs.powersync.com/client-sdk-references/swift),
[API reference](https://powersync-ja.github.io/powersync-swift/documentation/powersync/),
and [official demo](https://github.com/powersync-ja/powersync-swift/tree/1.16.0/Demos/PowerSyncExample).
GRDB integration remains alpha in this SDK, so Vega maps query cursors directly
into its domain types instead of adding a second database abstraction.

The behavior was checked against the official Wger implementations at the
revisions used during development:

- Flutter connector and sync diagnostics at
  [`wger-project/flutter@6eb6197`](https://github.com/wger-project/flutter/tree/6eb6197923517a64487697d138caf60ea17216ef/lib/powersync),
  especially its at-least-once upload classification and queue status UI.
- Wger handlers and tests at
  [`wger-project/wger@c390246`](https://github.com/wger-project/wger/tree/c3902462668622c46c56d50e339c2edbcca6f23f/wger),
  including the nutrition, weight, routine, workout-session, and workout-log
  ownership and idempotency rules.

Vega differs from Flutter by using native PowerSync SQL observation directly
rather than Drift/Riverpod and by retaining the unsupported resolved workout
schedule in client-only PowerSync tables. Vega's checked-in OpenAPI snapshot is
still independently pinned and normalized for REST operations. A newer Wger
OpenAPI document does not alter the PowerSync SQLite decoder: additional server
columns are ignored, while missing or malformed required values fail decoding
rather than silently weakening the domain type.
