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
