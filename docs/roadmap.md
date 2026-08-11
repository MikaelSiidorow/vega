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
- Put frequently logged portions near the current time above recent portions
  while preserving their saved amount and serving unit.
- Exercise deterministic diary states in UI tests without a live account.

## Current work

- Validate direct and browser-based authentication on a physical iPhone.
- Verify the MFA challenge UI with a deterministic UI test and screenshot.

## Next

- Improve accessibility, localization, decimal input, and time-zone behavior.
- Validate the complete nutrition flow on a physical iPhone.

## Later, based on use

- Repeated and favorite foods.
- Weight tracking and trends.
- Barcode scanning, App Intents, and widgets.
- Last-known-data caching and offline writes; reevaluate PowerSync when the
  required offline behavior is concrete.
- Workout support if Vega grows beyond nutrition tracking.

Keep this file forward-looking. Detailed experiments, personal usage notes,
and temporary implementation plans belong in issues or local notes.
