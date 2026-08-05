# Vega roadmap

Vega is an early-stage native iOS client focused on fast nutrition tracking
against a self-hosted wger server.

## Available now

- Sign in to a configurable wger instance.
- Persist and refresh sessions securely through Keychain.
- Load a daily nutrition diary with meal groups, unassigned-log time groups,
  serving units, calories, and macros.
- Navigate between dates and refresh from the server.
- Exercise deterministic diary states in UI tests without a live account.

## Current work

- Delete diary entries with confirmation.
- Edit amount and serving unit.
- Move entries to another time or meal.
- Verify correction flows with deterministic UI tests and screenshots.

## Next

- Add diary entries through ingredient search and portion selection.
- Complete MFA challenge flows.
- Improve accessibility, localization, decimal input, and time-zone behavior.
- Validate the complete nutrition flow on a physical iPhone.

## Later, based on use

- Recent, repeated, and favorite foods.
- Weight tracking and trends.
- Barcode scanning, App Intents, and widgets.
- Last-known-data caching and offline writes; reevaluate PowerSync when the
  required offline behavior is concrete.
- Workout support if Vega grows beyond nutrition tracking.

Keep this file forward-looking. Detailed experiments, personal usage notes,
and temporary implementation plans belong in issues or local notes.
