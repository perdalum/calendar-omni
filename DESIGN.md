# CalendarOmni 1.0.0: design and architecture

Status: implemented as 1.0.0 on 2026-09-20. See `VALIDATION.md` for completed
checks and live/platform verification still outstanding.

## Purpose and scope

One personal macOS command-line tool with six commands:

- `CalendarOmni extract`: retrieve many events from one calendar over a date range.
- `CalendarOmni create`: create one timed event in one calendar.
- `CalendarOmni update`: update existing non-recurring events from edited JSON.
- `CalendarOmni today`, `tomorrow`, and `last-week`: reports across configured calendars.

Use the existing Swift scripts as behavioral references: exact calendar selection,
inclusive extraction dates, title filters, duration input, and notes. Preserve the
original files. Replace their fragile argument handling and informal output.

Version 1 extracts timed, all-day, and multi-day events. Recurring occurrences
are excluded by default and included only with `--include-recurring`. Creation supports the existing script's timed, non-recurring events,
including location and notes. Attendees can be extracted but cannot be assigned
through EventKit. Updates support existing non-recurring events, including all-day
events. No deletion, recurrence creation or editing, attendee invitations, reminders,
database, server, plug-in system, or bulk creation.

“Bulk extraction” initially means all matching events from one selected calendar.
It does not imply selecting every calendar or exporting recurrence definitions.
The result reflects the local EventKit store; successful extraction is not a
guarantee that remote calendar accounts have finished synchronizing.

## Platform and build decision

Use Swift 6 language mode and macOS 14 or later. Use Foundation and EventKit,
plus Apple's Swift Argument Parser for subcommands, validation, and help, and
Yams 6.2.2 for the existing YAML report configuration.
Argument Parser is pinned to 1.7.2, with the resolved revision checked into the
Xcode workspace configuration.

Create a native `CalendarOmni.xcodeproj`, with one command-line executable target,
one test target, and a shared `CalendarOmni` scheme. Build the same project from
Xcode or the terminal:

```sh
xcodebuild -project CalendarOmni.xcodeproj -scheme CalendarOmni \
  -configuration Release -derivedDataPath build build
./build/Build/Products/Release/CalendarOmni --help
```

This meets both requested build interfaces with one build definition. A separate
`Package.swift` and support for `swift build` are deliberately outside this proposal;
they are unnecessary unless “command-line build” specifically means SwiftPM.
Xcode can resolve the Argument Parser package dependency itself.

Use an embedded executable Info.plist with a stable bundle identifier and
`NSCalendarsFullAccessUsageDescription`. Confirm the final binary contains it.
Use local signing supported by the installed Xcode; do not require a paid developer
account. App Sandbox is not enabled for this personal command-line executable.
Document a stable installation path and the actual permissions behavior observed
from Terminal and Xcode. Calendar privacy authorization remains mandatory.

## Command interface

Prefer named options over five positional values. They make generated commands
easier to inspect, and eliminate the overloaded “end time or duration” argument.

```sh
CalendarOmni extract --calendar "Komme-gå" \
  --from 2026-09-14 --to 2026-09-20 --format json

CalendarOmni extract --calendar "Ugeplan" \
  --from 2026-09-01 --to 2026-09-30 \
  --filter "report" --format csv > events.csv

CalendarOmni create --calendar "Ugeplan" --title "Write report" \
  --date 2026-09-21 --start 09:00 --duration 1h30m \
  --time-zone Europe/Copenhagen --notes "Prepare the first draft"

CalendarOmni create --calendar "Arbejdstid" --title "Daily sync" \
  --date 2026-09-21 --start 09:15 --end 09:30 --format csv

cat notes.txt | CalendarOmni create --calendar "Ugeplan" \
  --title "Prepare talk" --date 2026-09-22 --start 10:00 \
  --duration 2h --notes-stdin
```

Options for extraction and creation (`update` options are specified below):

| Option | Contract |
| --- | --- |
| `--calendar NAME` | Exact, case-sensitive title. Required unless an ID is supplied. |
| `--calendar-id ID` | Alternative exact EventKit calendar identifier. Mutually exclusive with name. |
| `--format json\|csv` | Default `json`. All three commands support both output formats. |
| `--time-zone ZONE` | IANA zone, default the Mac's current zone, resolved once at startup. |
| `--help`, `--version` | No calendar access needed. Root invocation without a command shows help. |

Extraction options:

- Optional boolean flag `--include-recurring` (no space after `--`), default off.
  Without it, exclude both ordinary recurring occurrences and detached/edited
  occurrences. With it, include them alongside non-recurring events in the range.
- Required `--from YYYY-MM-DD` and `--to YYYY-MM-DD`, both inclusive civil dates.
- Optional `--filter TEXT` (case- and diacritic-insensitive title substring) or
  `--regex PATTERN` (case-insensitive title regex), mutually exclusive.
- Reject empty filters, invalid regular expressions, and reversed date ranges.
- Optional `--fields all|FIELD,FIELD,...`, default `all`. Select from `title`, `start`,
  `end`, `location`, `attendees`, `notes`. A list replaces the default selection;
  emit exactly those content fields, in the supplied order for CSV. JSON always
  also includes `_ref` identity metadata; it is not part of `--fields`.
- Reject an empty list, `none`, duplicate/unknown field names, or mixing `all` with
  field names. Trim whitespace around names. Extraction has no mandatory event
  fields: for example, `--fields title` is valid. Creation requirements are separate.

Creation options:

- Required event data: `title`, `start`, and `end`. The existing date/time options
  construct start and end; `--duration` remains a shortcut for supplying a definite
  end. Calendar selection is a required destination, not an event-content field.

- Required `--title`, `--date YYYY-MM-DD`, `--start HH:mm` (also accept `H:mm`).
- Exactly one of `--end HH:mm` or `--duration 1h30m` / `2h` / `45m`.
- `--end` means the same civil date and must be later than the start. For overnight
  events, use duration. Do not silently infer “tomorrow”.
- Optional `--location TEXT`. Omission leaves the location unset.
- Optional `--notes TEXT` or `--notes-stdin`, mutually exclusive. Only read stdin
  when explicitly requested; reject interactive stdin and invalid UTF-8. Preserve
  supplied note text, including newlines. Missing notes become JSON `null`.
- Attendees are extraction-only: EventKit exposes a read-only attendee list and
  cannot add invitees. Reject attempts to supply attendees; do not silently ignore
  them or embed them in notes. This is an API constraint, not a CLI preference.
- Creation returns all six fields and does not accept `--fields` in version 1.
- Reject blank titles, extra arguments, unknown options, nonpositive durations,
  integer overflow, and unrepresentable dates before requesting calendar access.

If a calendar title matches multiple calendars, fail and report matching names,
sources, and IDs on stderr. If none matches, report available calendars there.
Never choose the first duplicate or silently fall back to the default calendar.
Check `allowsContentModifications` before creation or update.

## Updating from edited JSON

```sh
CalendarOmni extract --calendar "Ugeplan" \
  --from 2026-09-01 --to 2026-09-30 \
  --filter "report" --format json > events.json

# Edit content fields in events.json, leaving _ref metadata unchanged.
CalendarOmni update --input events.json

# Recurring occurrences are available for extraction when explicitly requested.
CalendarOmni extract --calendar "Ugeplan" \
  --from 2026-09-01 --to 2026-09-30 --include-recurring
```

`update` accepts `--input PATH` (required; `-` explicitly reads piped UTF-8 JSON from
stdin), `--format json|csv` (default JSON), and help/version. It takes the original
calendar from each record's `_ref`; there is no target-calendar override or calendar
move operation. It accepts the extraction envelope directly, or a previous create
or update response. The envelope's `command` describes its origin and never chooses
an operation: only the explicitly invoked CLI command does that.

The input schema is `CalendarOmni.update.schema.json`. Keep `schemaVersion`,
`timeZone`, and the original `fields` list. That list describes the original
projection; keys may be removed from individual event objects to leave those values
untouched. Any supplied content field must be in `fields`; to add a previously
unselected field, also add its name to that list. Remove an event object to omit
it from the update; this never deletes a calendar event. An empty event list is a
successful no-op. Reject a record containing only `_ref` and duplicate event IDs.

Update semantics:

| Input | Action |
| --- | --- |
| Content field omitted | Keep the current saved value. |
| Writable field supplied | Replace its value. |
| `location` or `notes` is `null` | Clear the field. |
| `title`, `start`, or `end` is `null` | Reject. |
| Attendees supplied and equal to the current list | Preserve them; no attendee write. |
| Attendees changed | Reject; EventKit does not support assigning attendees. |

Compare attendees as an order-independent collection of name/URL pairs. Preserve
unexported properties such as alarms by editing the fetched event rather than
constructing a replacement. Unchanged writable values do not require a save.
Validate the resulting event after merging the supplied fields: title remains
nonblank and end must be later than start. Update date values retain the current
all-day/timed type; converting between those types is outside version 1. All-day
end dates remain exclusive; timed inputs require explicit RFC 3339 offsets.
Keep the original EventKit time zone on the event; the input envelope time zone is
used for civil-date interpretation and output, not to silently replace that zone.

Resolve `_ref.eventId` using `event(withIdentifier:)`, verify `_ref.calendarId`,
and recheck the fetched event for recurrence. Missing/stale IDs, calendar mismatch,
read-only targets, unknown fields, malformed input, and recurring/detached targets
are errors. Do not guess a match by title, create a replacement, or trust edited
`isRecurring: false` metadata to bypass the live recurrence check. A null event ID
can occur in extraction output but cannot be used for updating.

Validate the entire input and resolve every target before staging any saves.
Use one EventKit store, stage changed events with `.thisEvent` and `commit: false`,
then call `commit()` once. Discard staged changes on pre-commit failure. This does
not promise a distributed transaction across calendar providers. A commit or output
failure can leave an uncertain outcome: report it, return nonzero, and require a
fresh extraction before retrying. Do not automatically retry. Abort if an EventKit
store-change notification invalidates the fetched targets during preparation.
Version 1 does not offer conflict merging against edits made after extraction;
supplied writable fields replace their current values, so use a fresh export.

Successful update output has `command: "update"` and all six content fields plus
fresh `_ref` metadata for each input record, in input order (including unchanged
records). `create` still creates one new event and has no JSON-import or upsert mode.

## Dates, extraction boundaries, and recurrence

Use a Gregorian calendar explicitly, strict date validation, and a fixed POSIX
locale for machine text. User locale must not change parsing or output.

The selected time zone governs civil inputs and rendered timed-event timestamps.
Use calendar arithmetic to turn inclusive dates into `[from midnight, day after to
midnight)`. Do not add 86,400 seconds to advance a civil day.

Extract occurrences overlapping that half-open interval; include an event that
started before the range but continues into it. Preserve full event start/end
values rather than clipping them. For zero-duration events, include starts within
the interval. Apply the precise boundary rule after EventKit retrieval.

EventKit limits individual predicates to four years. Query consecutive windows of
at most one calendar year, then remove occurrences repeated across window boundaries
using calendar ID, event ID, start, and end. Test recurring instances separately so
shared series identifiers never collapse different occurrences. If EventKit omits an
ID, retain records rather than risk merging distinct events based on title alone.

Classify fetched events using EventKit's `hasRecurrenceRules` and `isDetached`,
with `occurrenceDate` as additional series-occurrence metadata. Treat a fetched
event with recurrence rules or detached status as recurring. A non-null
`occurrenceDate` alone is not evidence of recurrence: the in-memory EventKit test
found it populated even on a standalone event after assigning its start date. Apply this check before serialization even when start/end are not
selected. Test normal occurrences and detached exceptions: checking recurrence
rules alone is insufficient. The same helper must guard updates. Verify the
classification against real non-recurring events and provider exceptions before
shipping, since imported copies that no longer carry series metadata cannot be
identified as recurring by title or appearance.

By default remove recurring events. With `--include-recurring`, preserve matching
instances and exceptions returned by EventKit; do not expand rules manually or
return an unbounded series. Sort by start instant, end instant, calendar ID, event
ID, and title. `_ref.occurrenceDate` retains the original occurrence date even when
an exception's start has moved. Including recurring events in an export does not
make them eligible for version-1 updates.

For creation, reject nonexistent or ambiguous local times around daylight-saving
transitions with an actionable error. Do not silently normalize a missing time or
pick one occurrence of a repeated hour. Durations mean elapsed minutes and can cross
midnight or a daylight-saving transition.

All-day extraction uses calendar dates with an exclusive end date, retaining the
event's civil-day meaning without conversion into a timed appointment. Verify
EventKit's all-day and floating-time behavior with events whose zones differ from
the Mac's current zone before finalizing mapping. Set the query's effective default
time zone consistently with `--time-zone` before creating the store, since the SDK
documents predicate behavior in terms of the default time zone.

## Fields and output contract

There are six selectable event-content fields, plus fixed JSON `_ref` metadata:

| Field | Creation input | Extraction |
| --- | --- | --- |
| `title` | Required, nonblank | Selectable |
| `start` | Required, constructed from date and start time | Selectable |
| `end` | Required, supplied as end time or calculated from duration | Selectable |
| `location` | Optional | Selectable |
| `attendees` | Unsupported by EventKit for creation | Selectable, read-only |
| `notes` | Optional | Selectable |

Recommendation: extract all six by default. An empty selection produces no useful
records, while defaulting to only required creation fields would conflate two
separate contracts. The short explicit selection is easy for LLMs and scripts:

```sh
CalendarOmni extract --calendar "Ugeplan" \
  --from 2026-09-01 --to 2026-09-30 --fields title,start,end

CalendarOmni extract --calendar "Ugeplan" \
  --from 2026-09-01 --to 2026-09-30 \
  --fields title,start,end,location --format csv
```

`--fields all` is equivalent to omitting the option. There are no separate include,
exclude, or preset systems. The canonical default order is
`title,start,end,location,attendees,notes`.

Successful commands write only the requested data to stdout. Errors and diagnostic
messages go to stderr. Help/version are the explicit non-data exceptions. An empty
extraction is success: JSON has an empty events array; CSV has only the selected header.

JSON uses the Draft 2020-12 schema in `CalendarOmni.schema.json`:

```json
{
  "schemaVersion": 1,
  "command": "create",
  "timeZone": "Europe/Copenhagen",
  "fields": ["title", "start", "end", "location", "attendees", "notes"],
  "events": [
    {
      "_ref": {
        "eventId": "opaque-eventkit-identifier",
        "calendarId": "opaque-calendar-identifier",
        "isRecurring": false,
        "occurrenceDate": null
      },
      "title": "Write report",
      "start": "2026-09-21T09:00:00+02:00",
      "end": "2026-09-21T10:30:00+02:00",
      "location": null,
      "attendees": [],
      "notes": "Prepare the first draft"
    }
  ]
}
```

- All commands share the envelope. `create` returns one saved event, `extract`
  returns zero or more matches, and `update` returns one result per input record.
  No synthetic success message or duplicate count.
- `fields` declares the resolved selection, even for an empty extraction. Every
  returned event contains exactly those content keys plus `_ref`. Unselected fields are omitted;
  selected-but-unset location/notes are `null`. Missing titles become `""`.
- Timed `start` and `end` are RFC 3339 timestamps with offsets; output preserves
  subsecond precision if present. All-day values are `YYYY-MM-DD` dates, with an
  exclusive end date. The representation itself distinguishes all-day events.
- The envelope's `timeZone` describes input interpretation and timed output rendering.
- `attendees` is an array of `{ "name": string-or-null, "url": string }` objects.
  `url` retains EventKit's participant URL, commonly `mailto:someone@example.org`;
  do not assume every participant address is an email. Use `[]` when EventKit
  supplies no attendees. This reports what EventKit exposes, not a separate check
  against the remote provider. No Contacts lookup or extra permission is needed.
- CSV stores attendees as a compact JSON array in one cell, using normal CSV escaping.
  This preserves multiple attendees and names containing punctuation unambiguously.
- JSON always includes `_ref` independently of field selection. Its `eventId`
  is the opaque EventKit lookup ID (nullable if unavailable); `calendarId` identifies
  its calendar; `isRecurring` classifies series membership; `occurrenceDate` is the
  original series occurrence timestamp or `null`. Leave this metadata unchanged.
  These references enable updating the same local store, not permanent identity:
  calendar moves/synchronization can invalidate IDs. Re-extract when lookup fails.
- CSV remains a content-only export; `_ref` is not flattened into extra columns.
  JSON is the supported editable update format. Duration and event-zone fields
  remain outside the public content set. This is not a full calendar backup.
- Schema validation enforces selections and field shapes. Code additionally checks
  real IANA zones, consistent start/end representations, date ordering, and semantics.

CSV uses UTF-8, semicolons, and CRLF record endings. The default header is:

```text
title;start;end;location;attendees;notes
```

CSV headers and rows follow the selected order. Quote fields containing a semicolon,
quote, CR, or LF; double embedded quotes. Preserve punctuation and multiline notes.
`null` is an empty cell; an empty attendee array is `[]`. CSV cannot distinguish null
from an empty string; JSON preserves that distinction. JSON envelope metadata is
not repeated as CSV columns.
No `sep=;` preamble, localized numbers, added prose, or automatic spreadsheet formulas.
Values are not modified for spreadsheet formula protection: treat imported cells as text.

Exit codes: `0` success/help/version; `2` invalid invocation or input; `1` access,
calendar selection, EventKit, or output failure. Do not output a success envelope
when an operation fails. Build the complete extraction payload before writing stdout.

Creation saves once with `.thisEvent` and `commit: true`, then emits the saved record.
A save can succeed even if writing stdout subsequently fails. Report that distinction
on stderr where possible. Never automatically retry creation after an uncertain result;
there is no idempotency guarantee and a retry can create another event.

## Architecture

```text
Command line
    |
    v
CalendarOmni / ExtractCommand / CreateCommand / UpdateCommand
    | parse CLI or JSON input and validate
    v
DateParsing                 (pure helpers)
    |
    v
CalendarService             (one EKEventStore, one isolation domain)
    | request access, resolve calendar, fetch or save
    v
EventRecord + EventOutput    (Codable value types)
    |
    v
OutputWriter                (JSONEncoder or semicolon CSV)
    |
    v
stdout
```

Keep EventKit objects confined to a single `@MainActor` service. Use async permission
requests and synchronous fetch/save operations sequentially there; this short-lived
CLI does not need parallel queries. Convert EventKit objects into value records
before serialization. Avoid detached tasks, unsafe Sendable declarations, repository
protocols, dependency-injection frameworks, and separate domain packages. A small
lock-protected notification counter is the only manually Sendable synchronization
type; EventKit objects never cross isolation boundaries.

Only the CLI boundary decides exit codes. Helpers throw descriptive errors. Pure
date/CSV/record tests need no calendar permissions; live tests are a separate procedure.

Project layout:

```text
CalendarOmni.xcodeproj/       # native project, shared scheme, resolved dependency
Sources/CalendarOmni/
  CalendarOmni.swift         # entry point and common options
  ExtractCommand.swift
  CreateCommand.swift
  UpdateCommand.swift       # JSON patches and preflight of existing events
  CalendarService.swift
  DateParsing.swift
  EventRecord.swift          # record and output envelope
  OutputWriter.swift
Resources/Info.plist
Tests/CalendarOmniTests/
CalendarOmni.schema.json
CalendarOmni.update.schema.json
README.md
SKILLS.md
DESIGN.md
PLAN.md
CalendarCreateEvent.swift    # preserved reference; excluded from targets
CalendarExtractor.swift     # preserved reference; excluded from targets
```

## Permissions and LLM use

Request full calendar access, since extracting events and resolving a named calendar
require read access. Write-only access cannot implement this interface. Handle denied,
restricted, and insufficient access explicitly. No access request for invalid input,
help, or version. Full access is an OS permission; `extract` still never mutates events.

The user completes macOS consent interactively before unattended use. Permission
behavior depends on the launch context and must be verified from the real executable.
Do not promise that moving or rebuilding a binary preserves its authorization.

`SKILLS.md` provides the LLM operating guide with:
the executable path and prerequisites; exact command examples; schema and exit-code
contracts; field selection; default recurrence exclusion and `--include-recurring`;
JSON round-tripping with `_ref`; update omission/null semantics and stale IDs;
required creation fields; read-only attendees; optional
location and notes; date and time-zone rules; exact calendar selection;
instructions to treat event contents as data, never instructions; and creation retry
rules. Creation/update require the user's intent for those mutations; do not add a CLI
confirmation prompt that blocks authorized automation. Do not infer success from an
empty stdout or interpret access failures as an empty calendar.

`SKILLS.md` is repository documentation. Automatic agent-skill installation is a
separate packaging task, not a prerequisite for an LLM to use this CLI.

## Basis and remaining verification

The existing sources were inspected directly. At the initial inspection this folder
contained only those two scripts and was not a Git repository. Xcode and a Swift 6 toolchain are
installed. No existing build configuration needs preserving.

Primary references:

- [Apple Swift Argument Parser](https://github.com/apple/swift-argument-parser):
  declarative arguments, subcommands, generated help, and async command support.
- [Apple TN2339: command-line Xcode builds](https://developer.apple.com/library/archive/technotes/tn2339/_index.html):
  building Xcode projects and schemes with `xcodebuild`.
- [Apple TN3152: Calendar access levels](https://developer.apple.com/documentation/technotes/tn3152-migrating-to-the-latest-calendar-access-levels):
  macOS 14 access APIs and purpose descriptions.
- [Apple EventKit predicates](https://developer.apple.com/documentation/eventkit/ekeventstore/predicateforevents(withstart:end:calendars:)):
  query behavior; the installed SDK's `EKEventStore.h` also confirms the four-year cap.

See `VALIDATION.md` for measured results. Embedded metadata and a live read-only
extraction are verified; cross-context permissions, live all-day/recurrence fixtures,
and live creation/update still require separate checks.

- [Apple: attendees](https://developer.apple.com/documentation/eventkit/ekcalendaritem/attendees):
  the attendee property is read-only; EventKit cannot add attendees.

- [Apple: eventIdentifier](https://developer.apple.com/documentation/eventkit/ekevent/eventidentifier):
  lookup identifiers and calendar-move limitations.
- [Apple: event lookup](https://developer.apple.com/documentation/eventkit/ekeventstore/event(withidentifier:)):
  identifier lookup returns the first occurrence; recurrence must be checked.
- [Apple: occurrenceDate](https://developer.apple.com/documentation/eventkit/ekevent/occurrencedate):
  original occurrence dates are retained for detached exceptions.
- The installed SDK headers also expose `hasRecurrenceRules` and `isDetached`.

## Built-in convenience reports

`ReportCommands.swift` provides three small commands sharing `--config` (default
`~/.calendar-omni`). `Report.swift` validates YAML with Yams, calculates local civil
date ranges, sorts records globally, and renders the daily text or existing CSV
format. `ReportOptions` authorizes one `CalendarService` and reads all configured
calendars with recurrence included. It buffers the complete report before writing;
any calendar failure produces only a stderr diagnostic and a nonzero status.

The default `extract` recurrence policy and JSON schemas are unchanged. Daily
reports use a fixed start/end/title layout; weekly reports use configured field
order. Date formatting follows `datetime_format: simple|full`. Existing scripts
are retained for comparison; the native commands are the main interface.
