# CalendarOmni 0.0.1 verification

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
