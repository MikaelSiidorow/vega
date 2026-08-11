# Vega roadmap

Vega is an early-stage native iOS client focused on fast nutrition tracking
against a self-hosted wger server.

## Available now

- Sign in to a configurable wger instance.
- Complete TOTP and recovery-code challenges, or hand authentication to the
  server's web flow for passkeys, social login, and SSO.
- Persist and refresh sessions securely through Keychain.
- Load a daily nutrition diary with meal groups, unassigned-log time groups,
  serving units, calories, and macros.
- Navigate between dates and refresh from the server.
- Correct diary entries by deleting them, changing amount or serving unit, or
  moving them to another time or planned meal.
- Add diary entries through ingredient search and an editable portion preview
  that keeps amount, unit, gram equivalent, calories, and macros visible.
- Scan EAN, UPC, and GTIN product barcodes with the native camera, or enter a
  code manually, and send it through the server's ingredient search.
- Put frequently logged portions near the current time above recent portions
  while preserving their saved amount and serving unit.
- Exercise deterministic diary states in UI tests without a live account.

## Current work

- Add server-backed API contract tests so generated Swift models are exercised
  against real wger serializers and deterministic edge-case data.

## Next

- Track daily body weight and show useful trends over time.
- Browse exercises and workout plans, then record sets, repetitions, and weight.
- Improve accessibility, localization, decimal input, and time-zone behavior.

## Later, based on use

- Repeated and favorite foods.
- App Intents and widgets.
- Last-known-data caching and offline writes; reevaluate PowerSync when the
  required offline behavior is concrete.

Keep this file forward-looking. Detailed experiments, personal usage notes,
and temporary implementation plans belong in issues or local notes.
