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
- Compare consumed energy, protein, carbohydrates, and fat with configured
  nutrition goals or the foods scheduled in the active plan.
- Navigate between dates and refresh from the server.
- Correct diary entries by deleting them, changing amount or serving unit, or
  moving them to another time or planned meal.
- Add diary entries through ingredient search and an editable portion preview
  that keeps amount, unit, gram equivalent, calories, and macros visible.
- Scan EAN, UPC, and GTIN product barcodes with the native camera, or enter a
  code manually, and send it through the server's ingredient search.
- Put frequently logged portions near the current time above recent portions
  while preserving their saved amount and serving unit.
- Track body-weight measurements in kilograms, correct or remove entries, and
  review native trend charts over 30 days, 90 days, one year, or all time.
- Move between native Diary, Workouts, and Progress destinations while keeping
  each screen's state.
- Browse workout routines and their server-resolved training days, then record,
  correct, or delete today's sets with repetitions and weight.
- Exercise deterministic diary states in UI tests without a live account.

## Next

- Add workout sessions, rest timers, and richer exercise details.
- Expand generated API contract fixtures as more server surfaces are adopted.
- Improve accessibility, localization, decimal input, and time-zone behavior.

## Later, based on use

- Repeated and favorite foods.
- App Intents and widgets.
- Last-known-data caching and offline writes; reevaluate PowerSync when the
  required offline behavior is concrete.

Keep this file forward-looking. Detailed experiments, personal usage notes,
and temporary implementation plans belong in issues or local notes.
