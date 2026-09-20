# CalendarOmni 0.0.1 implementation plan

Status: implementation complete for 0.0.1; build, unit, CLI, schema, and read-only
live checks completed. Live write tests and additional provider/platform fixtures
remain unverified. See `VALIDATION.md` for evidence and precise limitations.
The steps below preserve the implementation scope and acceptance criteria.

## 1. Establish the executable and macOS permission path

- Create the native Xcode command-line project and shared scheme, Swift 6 mode,
  macOS 14 deployment target, and resolved Argument Parser dependency.
- Embed the calendar usage description and stable identity in the executable.
- Build Debug and Release from the terminal and open/build the same scheme in Xcode.
- Verify help and version without accessing EventKit.
- Exercise authorization and a read-only calendar lookup from Terminal and Xcode.
  Resolve any executable metadata or launch-context issues before adding operations.

Acceptance: both build paths produce `CalendarOmni`; permission failures are
actionable and cannot masquerade as successful empty results.

## 2. Implement inputs and output contract

- Implement strict civil-date/time/duration parsing and time-zone selection.
- Implement the six public fields and extraction selection via `--fields`; default
  to all six. Test exact selected keys/CSV column order and omitted versus null values.
- Add fixed JSON `_ref` metadata alongside selectable content fields.
- Implement JSON records conforming to `CalendarOmni.schema.json` and semicolon CSV.
- Establish stdout/stderr separation and the documented exit codes.
- Test meaningful boundaries: invalid dates, leap days, DST gaps/repeated times,
  overnight durations, Unicode, embedded quotes/semicolons/newlines, and empty output.
- Validate example and generated JSON using Draft 2020-12 with format checks enabled.

Acceptance: format and date tests run without calendar access; errors precede any
permission request or mutation.

## 3. Implement bulk extraction

- Resolve exact calendar names or IDs; diagnose missing and ambiguous names.
- Query bounded windows, apply overlap rules, deduplicate window repeats, filter,
  sort, and serialize complete results.
- Exclude recurring events by default; add the boolean `--include-recurring` flag.
- Verify multi-day, all-day, floating-zone, recurring, and detached exception
  occurrences. Test that field projection cannot bypass recurrence filtering.
- Verify attendee extraction, including unnamed participants, non-email URLs, and
  multiple attendees serialized in a single properly escaped CSV cell.
- Check extraction spanning more than four years for silent truncation.

Acceptance: known fixtures agree with Apple Calendar and the reference script for
ordinary events; deliberate differences in errors and output match the new contract.

## 4. Implement single-event creation

- Validate calendar writability, create the event with its explicit time zone and
  optional location and notes, commit once, and serialize the actual saved event.
- Require title, start, and end (allow duration to derive end). Do not accept attendees
  for creation: the public EventKit API only supports reading them.
- Test argument rejection without writes. Use an explicitly designated test calendar
  for the live save test; do not write test appointments into an arbitrary calendar.
- Read back the saved event to check its title, dates, location, and multiline notes.
- Verify that output failure after save is reported without automatically saving again.

Acceptance: a successful invocation creates one event and returns one matching
record in either requested output format. Test cleanup is explicit; it is not a new
CalendarOmni delete command.

## 5. Implement JSON updates

- Add `update --input PATH` (or `-` for piped input), accepting edited output JSON
  under `CalendarOmni.update.schema.json` and emitting JSON or CSV.
- Require `_ref` metadata; resolve IDs and verify the calendar and live recurrence
  status. Reject stale IDs and recurring/detached events without fallback creation.
- Implement omitted-field preservation, null clearing for location/notes, mandatory
  resulting title/start/end, and unchanged-attendee acceptance; reject attendee edits.
- Preserve nonexported properties and all-day/timed type. Skip unnecessary saves.
- Preflight every record before staging saves; reject duplicate targets, then stage
  changes and commit once. Do not claim cross-provider atomicity or auto-retry errors.
- Test projected exports, empty batches, invalid later records, read-only calendars,
  stale IDs, edited recurrence metadata, attendees, unknown fields, and null semantics.
- In a designated test calendar, extract, edit, update, and read back events; verify
  preserved alarms and omitted fields and that no duplicate events were created.

Acceptance: edited JSON updates only the identified non-recurring events. Missing
references and recurring targets fail explicitly; `create` remains a separate action.

## 6. Document and hand over

- Write README build/install instructions and command examples.
- Write `SKILLS.md` for LLM operation, including mutation intent and retry behavior.
- Document machine-interface differences from the two reference scripts.
- Run the focused tests, schema validation, Release build, and documented examples.
- Record which macOS permission/live EventKit checks were actually performed.
- Preserve both original Swift files and keep them outside all build targets.

Acceptance: one documented executable, one project, three commands, two output formats,
output and update-input schemas, and an LLM operating guide. No runtime framework or expansion machinery.

## Implemented decisions

1. Command-line builds use `xcodebuild`; a separate SwiftPM build is not required.
2. JSON is the default; CSV is explicit and uses semicolons.
3. Named arguments replace the old positional syntax; no compatibility aliases.
4. Bulk extraction selects one calendar per invocation.
5. Creation stays timed and non-recurring in version 1; extraction includes all-day
   events; recurring occurrences require `--include-recurring`.
6. Apple's Argument Parser is the only added dependency.

7. Public event fields are title, start, end, location, attendees, and notes.
   Extraction defaults to all; `--fields` selects an exact nonempty subset.
8. Creation requires title, start, and end; location and notes are optional.
   Attendees are extraction-only because EventKit cannot assign them.
9. JSON includes fixed `_ref` metadata for update targeting independently of selected
   content fields; CSV stays content-only.
10. Add `update --input` for non-recurring events only. Unknown IDs never create events.
11. Recurrence exclusion includes detached exceptions. Update always rechecks live
    recurrence status, regardless of metadata supplied in JSON.
