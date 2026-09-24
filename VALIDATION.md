# CalendarOmni verification history

Verified on 2026-09-20 using Xcode 27.0 beta (27A5228h), Swift 6.4, on this Apple
Silicon Mac. The deployment target is macOS 14; older macOS versions were not run.

## Completed

- Debug build and shared-scheme Xcode tests completed successfully.
- **17 XCTest tests passed**, with zero failures. Coverage includes strict civil
  dates, invalid timestamps, DST gaps and repeated times, 23/25-hour date ranges,
  overnight duration input, overflow rejection, long-range query windows, overlap
  boundaries, selection validation, JSON null/projection handling, multiline CSV,
  update merge semantics, attendees, all-day type preservation, duplicate/stale
  input shape rejection, and an in-memory EventKit recurrence check.
- All **63 nonempty field selections** encode and decode through the update input
  parser inside the test suite.
- **33 CLI checks passed** against both Debug and Release binaries: version/help,
  parser/validation failures with exit 2 and clean stdout, malformed update input,
  empty update JSON and CSV, and output/update JSON Schema validation.
- Release built successfully as a universal **arm64 + x86_64** executable at
  `build/Build/Products/Release/CalendarOmni`. The Intel slice was built but was not
  separately executed.
- Verified ad-hoc code signing and the embedded Info.plist, including the stable
  `local.CalendarOmni` identity, `0.0.1` version, and Calendar full-access usage text.
- Live, **read-only** extraction succeeded from `Ugeplan` through the built Release
  executable in the Codex-launched process. A September 2026 extraction returned
  12 events. Default and `--include-recurring` output both returned 12; this sample
  contained no recurring, all-day, or attendee-bearing events.
- The live JSON passed `CalendarOmni.schema.json`. All 12 CSV rows matched the JSON
  content fields, including null/empty-cell mapping and attendee JSON cells.
- Both original Swift reference scripts are byte-for-byte unchanged (SHA-256 below).

The EventKit in-memory test established that `occurrenceDate` alone must not be
used to detect recurrence: it was populated on a standalone event after its start
was set. The implementation uses `hasRecurrenceRules || isDetached` instead, and
retains occurrenceDate only as reference metadata for actual recurring events.

## Remaining live/platform checks

- **No calendar events were created, updated, or deleted.** Actual save/update
  behavior still needs verification in a user-designated test calendar. Pure update
  validation and merge behavior are tested, but this is not a claim of live write
  verification, rollback guarantees, or remote provider transaction guarantees.
- Recurrence inclusion/exclusion was exercised on the live sample, but that sample
  had no recurring events. A live recurring series with a detached exception,
  attendee-bearing events, and all-day events across zones remain to be checked.
- A real extraction exceeding four years was not run. Contiguous one-year window
  generation is tested; remote-provider behavior across those windows remains a
  live check.
- Xcode's build/test engine and shared scheme were verified through `xcodebuild`.
  The GUI editor/Run action was not manually operated. Initial consent and permission
  attribution under separate Terminal/Xcode launches still depend on those contexts.
- Denied-permission and disconnected-calendar scenarios were not exercised by
  changing the user's macOS privacy settings.
- The test runner may log EventKit access-denied messages when constructing unsaved
  in-memory events; no authorization is requested by these tests. Xcode also emits
  an informational AppIntents metadata warning because this CLI has no AppIntents.
  Neither caused a test failure. The final Release build had no compiler warnings.

## Reproduce

Use the build/test commands in README.md and `scripts/check_cli.py`. Optional schema
checking in that script requires the development-only Python package
`jsonschema[format]`; it is not a CalendarOmni runtime dependency.

The Xcode CLI needs access to its normal compiler/package caches and test services.
In this execution environment, the initial sandboxed build could not write those
caches; the successful builds used the approved normal Xcode execution context.

Original reference hashes:

```text
040fd0ff456e9f3313d455b2ea6594d69195e0ac0087a1a9a6f4fd2e5a26396f  CalendarCreateEvent.swift
703408e2f1239d2502791c9e4f43005d2a3b630c9ec75147bb5691057a4b755f  CalendarExtractor.swift
```

## Reporting helpers

Added and verified on 2026-09-20, without changing or rebuilding the Swift executable:

- `scripts/today`, `scripts/tomorrow`, and `scripts/last-week`, with shared standard-
  library Ruby implementation and user-wide YAML config at `~/.calendar-omni`.
- **12 helper tests and 74 assertions passed**, using a fake CalendarOmni executable.
  Tests exercise all report ranges, previous complete Monday–Sunday weeks, New Year,
  DST-spanning weeks, safe YAML validation, multi-calendar sorting by actual instants,
  all-day/fractional timestamp ordering, hidden sort fields, multiline CSV, header-only
  reports, nonzero failures without partial output, shell-safe calendar arguments,
  execution from another directory, and symlink launch behavior.
- Live read-only runs with the default user config (`Ugeplan`, all six fields):
  `today` returned 4 rows; `tomorrow` and `last-week` returned header-only CSVs.
  Verified column order, chronological sorting, and valid attendee-array cells.
- The live configuration had one calendar; multi-calendar merging and failure in a
  later calendar were verified with fixtures rather than additional private calendars.
- Every helper passes `--include-recurring`. The live sample does not establish
  coverage of a real recurring series; that remains as noted above.
- The user config was created exclusively (without overwriting an existing file)
  with permissions 0600. No Calendar events were created, modified, or deleted.

Reproduce helper tests with:

```sh
/usr/bin/ruby Tests/Helpers/test_calendar_omni_helpers.rb
```

### Datetime display option

- Added optional `datetime_format: simple|full`. Missing options retain full output;
  the user's config and example config explicitly select simple output.
- The expanded helper suite passed **17 tests and 107 assertions**. Added checks for
  option validation/defaults, exact full-value preservation, local daily HH:MM and
  weekly YYYY-MM-DD HH:MM rendering, all-day handling, and sorting before formatting.
- A live read-only `today` run with the updated user config returned 4 rows; every
  displayed start/end value was HH:MM or the all-day label. No events were modified.

### Daily line output

- `today` and `tomorrow` now emit one `FROM -- TO : TITLE` line per event, with
  no header or output for empty days. They fetch title/start/end independently of
  configured weekly CSV fields and flatten line breaks within titles.
- `datetime_format` still controls displayed start/end values; sorting still uses
  full instants. `last-week` remains semicolon CSV with configured columns.
- The adapted helper suite passed **19 tests and 107 assertions**, including exact
  daily output, multiline titles, empty days, full/simple formats, and weekly CSV.

## Wolfram Language report variants — 2026-09-20

- Verified through the user's `wolframscript -wstpserver -continueprofile
  "$HOME/wstp-profile" -file ...` workflow with Wolfram 15.0.1 on macOS ARM.
- **33 Wolfram tests passed**: civil date ranges across year/DST boundaries,
  exact timestamp ordering including offsets and nanoseconds, daily and weekly
  formatting, all-day events, CSV escaping, empty output, Unicode YAML config,
  invalid configuration, and invalid dates.
- **15 WSTP CLI checks passed** using a fake CalendarOmni executable. All three
  reports matched the Ruby variants byte for byte for both simple and full date
  formats. Checked quoted/Unicode calendar names, paths with spaces, recurring
  extraction flags, help, empty results, malformed JSON, operation failure,
  missing config, exit status, and continued-kernel use after errors.
- Direct UTF-8 file import avoids a verified Unicode failure in the native YAML
  `ImportString` path on this kernel. No additional YAML paclet was installed.
- Live read-only runs of all three native helpers succeeded using the existing
  user config: today returned 371 bytes, tomorrow 357 bytes, last-week 1,238
  bytes, each with status 0 and empty stderr. No events were created or updated.
- WSTP buffers script output and returns diagnostics on stdout. This limitation
  is documented; callers must check exit status before accepting report data.
- No Swift changes or rebuild required. Existing Ruby scripts and user config
  were preserved.

Reproduce the native checks with:

```sh
wlf Tests/Wolfram/run.wls
python3 Tests/Wolfram/check_cli.py
```

## Built-in Swift reports — 2026-09-20

- Added `CalendarOmni today`, `tomorrow`, and `last-week` with `--config`, keeping
  the existing YAML keys and formatting rules. Yams 6.2.2 is pinned in the Xcode
  project and resolved package file. The two new implementation files total
  141 lines, including blank lines.
- Xcode Debug tests: **21 tests passed**, including four report tests covering
  config validation, Unicode, duplicate/unknown keys and fields, aliases, multiple
  YAML documents, DST/year/week boundaries, timestamp sorting, all-day output,
  daily formatting, full timestamp preservation, and weekly CSV escaping.
- Release command-line build succeeded. **45 CLI checks passed**, including help
  and invalid config/argument checks for all report commands; error output stays
  on stderr. Optional JSON Schema validation was skipped because `jsonschema`
  was not installed in the Python environment; schemas were unchanged.
- Live read-only checks outside the sandbox succeeded for all three commands.
  Output matched the Ruby helpers byte for byte using the current user config:
  today 371 bytes, tomorrow 357 bytes, last-week 1,238 bytes. The sandbox initially
  blocked EventKit communication (Mach error 4099); the normal execution context
  succeeded. No events were created or modified, and user config was unchanged.
- README, SKILLS, design, and plan now describe the built-in commands. Legacy
  script variants remain available; no scripting runtime is needed for reports.

## Zsh completion — 2026-09-20

- Added `scripts/install-zsh-completion`, which generates `_CalendarOmni` from
  the selected executable, validates zsh syntax, and installs it atomically.
- Added file completion hints for report `--config` and update `--input`.
  Generated definitions include all six commands, options, and json/csv values.
- Release build succeeded; all 45 existing CLI checks passed. Optional JSON
  Schema validation was skipped because Python `jsonschema` was unavailable.
- Installed into the user's existing `~/.zsh/completion` directory. A clean zsh
  session with that fpath successfully registered and loaded `_CalendarOmni`.
  No `.zshrc` changes were needed. An initial test under `/tmp` was rejected by
  zsh's directory permission checks; the actual user completion path passed.
- Completion generation and verification did not request Calendar access.

## Version 1.0.0 release — 2026-09-20

- Updated application version, Debug/Release marketing version, embedded
  Info.plist, current guides, and CLI version assertion to 1.0.0. Schema version
  remains 1. Historical 0.0.1 validation and changelog entries are retained.
- Release build succeeded. Both `--version` and the built executable's embedded
  `CFBundleShortVersionString` were verified as 1.0.0.
- Debug XCTest suite: 21 tests passed. CLI checks: 45 passed. Generated zsh
  completion passed syntax validation. Optional Python JSON Schema validation
  was skipped because `jsonschema` was unavailable; schema files are unchanged.
- Ruby helpers: 19 tests / 107 assertions passed. Wolfram helpers: 33 tests and
  15 WSTP CLI checks passed, including byte-for-byte report comparisons.
- `git diff --check` passed before the release commit. No calendar writes were
  performed during release verification.

## Meeting-only extraction — 2026-09-21

- Added `extract --only-meetings`, filtering mapped records with nonempty
  attendees before output-field selection. Existing extraction filters remain
  in effect. No schema changes or calendar writes.
- Release build succeeded and 46 CLI checks passed, including help and rejection
  of an explicit value after the boolean flag. Optional Python schema validation
  was skipped because `jsonschema` was unavailable.
- 36 read-only comparisons passed across both configured calendars for September
  2026: default/explicit recurrence inclusion, title substring/regex filters,
  JSON with all fields or without attendees, and semicolon CSV. Results exactly
  matched normal extraction filtered to events with attendees. Checks covered
  empty results as well as 27 non-recurring and 39 recurrence-inclusive matches
  in the second calendar.
- Regenerated and installed zsh completion; `--only-meetings` is present.

## Makefile — 2026-09-21

- Added build/all, debug, test, check, install, uninstall, completions, clean, and
  help targets over the existing Xcode project. Default install is
  `$HOME/bin/CalendarOmni`; PREFIX, BINDIR, and DESTDIR overrides are supported.
- `make test` passed: Release build, 46 CLI checks, and 21 Swift tests. Optional
  JSON Schema checks were skipped because Python `jsonschema` was unavailable.
- `make install` successfully copied the executable into a temporary bin path
  containing spaces; that executable reported 1.0.0. `make uninstall` removed it.
- Dry runs verified default ~/bin installation, PREFIX/DESTDIR staging, completion
  destination quoting, and both clean commands. No installation in ~/bin or
  changes to the user's shell/calendar configuration were made for these checks.

## Version 1.1.0 release — 2026-09-21

- Updated CLI version, Xcode Debug/Release marketing versions, embedded
  Info.plist, current guides, and CLI version assertion to 1.1.0. Changelog
  records the meeting-only extraction flag and Makefile as this release's changes.
  Schema version remains 1; earlier release records are preserved.
- `make test` passed: Release build, 46 CLI checks, and 21 Swift tests.
  Optional Python JSON Schema validation was skipped because `jsonschema` was
  unavailable; schema files are unchanged.
- Verified both the Release executable's `--version` and its embedded
  `CFBundleShortVersionString` as 1.1.0. `git diff --check` passed.
- Release verification did not access or modify calendars.

## Simplified weekly JSON — 2026-09-21

- Native `last-week` now emits a top-level JSON array with exactly title, start,
  end, location, and attendees. Attendees are nonblank name strings only; missing
  names are omitted, missing locations are null, and empty reports are []. Full
  timestamps/date-only boundaries are preserved independently of config formatting.
- `make test` passed: Release build, 46 CLI checks, and 21 Swift tests. The weekly
  regression test checks exact keys, Unicode/escaping, chronological sorting,
  all-day dates, null location, omitted attendee URLs/unnamed entries, empty arrays,
  and identical output under simple/full config. The fixture config omits location
  and attendees, verifying that weekly fields are fixed regardless of selection.
- Live read-only comparison matched all 30 events for the previous Monday–Sunday
  across configured calendars against normal extraction projected to the new shape.
  No calendar or user-config writes were performed.
- Refreshed zsh completion and docs. Legacy Ruby/Wolfram scripts retain CSV.
  Extract/update schemas are unchanged; the weekly report is a separate format.

## Weekly meeting filter — 2026-09-21

- Added `last-week --only-meetings`, filtering on nonempty EventKit attendee
  records before projecting attendee names. Events with only unnamed attendees
  still qualify; daily commands are unchanged.
- `make check` passed: Release build and 48 CLI checks, including weekly help
  and rejection of an explicit boolean value. Optional Python schema validation
  remained skipped because `jsonschema` was unavailable.
- Live read-only comparison matched all 10 qualifying events from the previous
  week against normal extraction filtered on attendees. Fixed JSON keys and full
  timestamps were preserved. No Calendar writes were performed.
- Updated README/SKILLS and regenerated installed zsh completions.

## Explicit weekly calendar — 2026-09-21

- `last-week` now requires `--calendar NAME` and no longer accepts `--config` or
  loads ReportConfig. Its fixed JSON renderer takes no config object. Daily
  reports continue to use the existing YAML configuration.
- `make test` passed: Release build, 48 CLI checks, and 21 Swift tests. CLI checks
  cover missing/empty/whitespace calendar names, removal of --config, and the
  meeting flag. Optional Python schema validation remains unavailable.
- Four live read-only comparisons passed for two explicitly named calendars,
  with/without --only-meetings: 12/0 and 18/10 events respectively. Results matched
  normal extraction projected to weekly JSON. These runs set HOME and
  CFFIXED_USER_HOME to a temporary directory containing malformed .calendar-omni;
  weekly output succeeded without reading it. Actual user config was unchanged.
- Refreshed installed zsh completion and current documentation. No calendar writes.

## Today's attendee names — 2026-09-23

- Native `today` appends a Danish `[med …]` list using the first whitespace-
  separated part of each available attendee display name. Hyphenated names and
  duplicate given names are preserved; nil/blank names are omitted. No usable
  names means no suffix. Tomorrow and weekly formatting are unchanged.
- `make test` passed: Release build, 48 CLI checks, and 22 Swift tests. Added
  formatting cases for zero/one/two/three names, missing names, Unicode,
  whitespace/newlines, hyphenated and duplicate names, simple/full timestamps,
  and unchanged tomorrow output. Optional Python JSON Schema validation was
  skipped because `jsonschema` is unavailable.
- Updated README, SKILLS, design, and changelog. No calendar or user-config writes.

### Today suffix correction — 2026-09-23

The square brackets in the requested example indicated optional content, not
literal output. Today now appends ` med Anders, Claus og Diba` without brackets.
Updated existing expectations and docs; `make test` passed (22 Swift tests and
48 CLI checks), and the Release binary was rebuilt.

## Today self-exclusion and short location — 2026-09-23

- Exclude Per Møldrup-Dalum from today's displayed attendees using full-name,
  case-insensitive matching with normalized whitespace; other people named Per
  remain. Extract and weekly data are unchanged.
- Append a location after an em dash: AU room code if found on the first line,
  otherwise that line with normalized whitespace and a 40-character limit
  (including ellipsis). No location means no suffix.
- `make test` passed: Release build, 48 CLI checks, and 23 Swift tests. Added
  self-only/mixed/case/whitespace cases and location cases covering room codes,
  missing values, multiline text, Unicode, truncation, and unchanged tomorrow.
- Optional Python schema validation was skipped because jsonschema is unavailable.
  No Calendar or user-config writes were performed.

## Opt-in duration — 2026-09-24

- Added `extract --fields duration` (alone or in a field list). JSON emits a number;
  CSV emits numeric text without units. Defaults and `--fields all` retain six
  content fields. Create/update/report layouts are unchanged. Update input rejects
  duration with a message explaining removal of the calculated field.
- Output schema updated with optional numeric duration and field-selection
  presence/absence rules. The update-input schema remains unchanged.
- `make test` passed: Release build, 49 CLI checks, and 24 Swift tests. Duration
  cases cover whole/fractional/zero minutes, overnight events, offset changes,
  all-day/multiday events, spring/fall DST, JSON/CSV encoding, default exclusion,
  and explicit selection. Optional Python schema validation was skipped because
  jsonschema is unavailable.
- Read-only live checks passed for 76 events: numeric duration agrees with elapsed
  timestamp differences, duration-only JSON/CSV agree, and default/all omit it.
- Regenerated installed completion help. No calendar or user-config writes.
