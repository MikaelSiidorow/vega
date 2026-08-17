# Vega notices

## Vega license

Copyright © 2026 Mikael Siidorow

Vega is free software: you can redistribute it and/or modify it under the terms
of the GNU Affero General Public License as published by the Free Software
Foundation, either version 3 of the License, or (at your option) any later
version.

Vega is distributed in the hope that it will be useful, but without any
warranty; without even the implied warranty of merchantability or fitness for a
particular purpose. See the [GNU Affero General Public License](LICENSE) for
details.

SPDX-License-Identifier: AGPL-3.0-or-later

### App-store exception

As an additional permission under section 7 of the GNU Affero General Public
License, you may distribute Vega through an app store even if that store has
restrictive terms and conditions that are incompatible with the AGPL, provided
that Vega's corresponding source is also available under the AGPL, with or
without this permission, through a channel without those restrictive terms and
conditions.

## Relationship to wger

Vega is an unofficial native client compatible with [wger](https://wger.de).
It is not affiliated with or endorsed by the wger project, and it uses its own
name, interface, and application identity.

The following projects provided the API contract and product inspiration:

- [wger server](https://github.com/wger-project/wger), licensed under the GNU
  Affero General Public License version 3 or later.
- [Official wger Flutter client](https://github.com/wger-project/flutter),
  licensed under the GNU Affero General Public License version 3 or later with
  an app-store exception.

`Packages/WgerAPI/Sources/WgerAPI/server-openapi.json` is a verbatim OpenAPI
snapshot produced by a wger 2.7 server. `openapi.json` is a mechanically
normalized derivative used to generate Swift API types and client operations.
The normalization keeps JSON request bodies and omits unsupported upload
mutations and their request-only schemas. The original wger project and these
schema-derived files are available under the GNU Affero General Public License
version 3 or later.

Vega's focused workout sequence in `Vega/Workout/WorkoutSession.swift` and
`Vega/Workout/WorkoutSessionView.swift` adapts the start, current-set, rest, and
summary interaction model from the official wger Flutter client's
`lib/features/routines/widgets/gym_mode` directory at revision
`6eb6197923517a64487697d138caf60ea17216ef`. The native SwiftUI implementation
and state model differ from the Flutter source. The adapted work is copyright
© 2020–2026 wger Team and remains available under AGPL-3.0-or-later with the
wger app-store exception; Vega's complete corresponding source is provided in
this repository under compatible terms.

Vega does not bundle wger's exercise, ingredient, or image catalogs. Content
fetched from a configured server may carry its own attribution and Creative
Commons license; those licenses are not replaced by Vega's software license.

## Third-party software

Swift package dependencies retain their own copyright notices and licenses.
Their exact source revisions are recorded in
`Vega.xcodeproj/project.xcworkspace/xcshareddata/swiftpm/Package.resolved`.

Unless explicitly stated otherwise, contributions submitted to Vega are
licensed under the same AGPL-3.0-or-later terms and app-store exception.
