# CalendarOmni 1.1.0

A personal macOS command-line tool for extracting Apple Calendar events, creating
one event, and updating existing non-recurring events from edited JSON.

Requires macOS 14 or later and Xcode with a Swift 6 compiler. Uses Apple's EventKit
and Swift Argument Parser 1.7.2, plus [Yams 6.2.2](https://github.com/jpsim/Yams)
for YAML configuration. Both dependencies are compiled into the executable.

## Build and run

Open `CalendarOmni.xcodeproj` in Xcode, select the **CalendarOmni** scheme, and build.
The shared scheme runs `--help` by default; edit its Run arguments to use a command.
The first build resolves the pinned Swift packages and needs network access.
No paid Apple developer account is required; the executable is signed locally.

The Makefile wraps the same Xcode project:

```sh
make                 # Release build
make debug           # Debug build
make test            # Swift unit tests and CLI checks; no Calendar access
make install         # Build and install to ~/bin/CalendarOmni
make completions     # Install zsh completion separately
make clean           # Clean Debug/Release products; keep downloaded packages
make help            # List targets and overrides
```

Add `$HOME/bin` to your shell's PATH if needed. `make install` installs only the
executable; it does not change your shell configuration or calendar config.
Use `make uninstall` to remove the installed executable. The examples below
assume `CalendarOmni` is on PATH.

The install prefix defaults to your home directory. Override it or the bin
directory explicitly; quote paths containing spaces:

```sh
make install PREFIX="$HOME/.local"       # ~/.local/bin/CalendarOmni
make install BINDIR="/custom/path/bin"    # exact destination directory
```

`DESTDIR` optionally stages installation ahead of the absolute destination path.
`COMPLETIONDIR` defaults to `~/.zsh/completion`. `BUILD_DIR` defaults to `build`,
and `CONFIGURATION` to `Release`. `make check` builds and runs CLI checks only.
Older Ruby/Wolfram helper tests remain separate, as described in `VALIDATION.md`.

Direct command-line builds remain available:

```sh
xcodebuild -project CalendarOmni.xcodeproj -scheme CalendarOmni \
  -configuration Release -derivedDataPath build \
  -clonedSourcePackagesDirPath build/SourcePackages build

./build/Build/Products/Release/CalendarOmni --version
```

The version is `1.1.0`. Xcode is the single build definition; `swift build` is not
supported. The local executable uses ad-hoc signing and embedded Calendar privacy
metadata; it is not notarized for distribution.

## Zsh completion

After building Release, install generated completion definitions:

```sh
./scripts/install-zsh-completion
```

This writes `~/.zsh/completion/_CalendarOmni`. Your current zsh configuration
already includes that directory in `fpath` and runs `compinit`. Open a new shell,
or refresh the current one:

```zsh
autoload -Uz compinit
compinit
```

Try `CalendarOmni <TAB>`, `CalendarOmni extract --<TAB>`, or
`CalendarOmni today --config <TAB>`. Completion covers commands, options,
`json`/`csv` format values, and file paths for `--config` and `--input`. Calendar
names are entered manually; tab completion does not request Calendar access.
CalendarOmni must be on PATH for the short command, or use its executable path.

Rerun the installer after rebuilding when commands or options change. Optional
arguments select a different executable and completion directory:

```sh
./scripts/install-zsh-completion /path/to/CalendarOmni /path/to/completions
```

On another Mac, add the following to `.zshrc` before its existing `compinit` call
(or include all three lines if completion is not configured):

```zsh
fpath=("$HOME/.zsh/completion" $fpath)
autoload -Uz compinit
compinit
```

## Calendar access

Run the first calendar operation interactively and allow **full Calendar access**.
Extraction and selecting a calendar require read access, so write-only permission
is insufficient. Check System Settings → Privacy & Security → Calendars if access
is denied. macOS can attribute permission to the launching application (Terminal,
Xcode, or an automation host); authorization can differ between launch contexts.
Help, version, invalid input, and an empty update batch need no Calendar access.

Use one stable installation path for automation. Rebuilding/moving the executable
may change how privacy authorization is attributed. This is a normal, unsandboxed
macOS command-line executable; macOS privacy controls still apply.

## Daily and weekly reports

`today` and `tomorrow` use the user-wide YAML file `~/.calendar-omni`.
`last-week` does not read any config file: it requires `--calendar NAME` and
has hard-coded output fields.

```yaml
calendars:
  - Ugeplan
  - "Komme-gå"

fields:
  - title
  - start
  - end
  - location
  - attendees
  - notes

datetime_format: simple
```

Use exact calendar names and only calendars you want in the report. `calendars`
and `fields` remain required nonempty lists for compatibility with existing
configs and legacy scripts. Unknown keys/fields, duplicates, and YAML aliases
are rejected. Native report layouts are fixed; `fields` does not select their
output fields. `datetime_format` controls only native daily reports (`full` if
omitted). A starter file is provided at `examples/calendar-omni.yaml`.

```sh
CalendarOmni today > today.txt
CalendarOmni tomorrow > tomorrow.txt
CalendarOmni last-week --calendar "Kalender" > last-week.json
CalendarOmni last-week --calendar "Kalender" --only-meetings > meetings.json
```

- `today` and `tomorrow` print one `FROM -- TO : TITLE` line per event, without a
  header. Multiline titles are flattened. Empty days print nothing. With
  `datetime_format: simple`, times use local `HH:MM` and all-day values show
  `all-day`; `full` preserves the original timestamp/date strings.
- `today` appends an attendee suffix when names are available, for example:
  `10:00 -- 10:45 : Ethics questions med Anders, Claus og Diba`.
  Given names are approximated by the first word of each attendee display name;
  hyphenated names are preserved. Missing/blank names are skipped, and identical
  given names are retained for distinct attendees. No usable names means no suffix.
  This applies to both simple and full date styles; `tomorrow` keeps its existing layout.
- For native `today`, omit the attendee `Per Møldrup-Dalum` before extracting given
  names (case-insensitive, ignoring extra whitespace). Other people named Per are
  kept. Append a short location after the attendee list, separated by ` — `:
  `10:00 -- 10:45 : Ethics questions med Diba — 3210-05.071`.
  Use an AU building-floor.room code when present on the first location line;
  otherwise use that line with normalized whitespace, capped at 40 characters with
  an ellipsis. Missing locations add nothing. This affects only today's display;
  extract/weekly JSON retain their full location and attendee data.

- `last-week` uses the **previous complete Monday–Sunday week**, not a rolling
  seven days. On Monday 2026-09-21 it reports September 14–20. Supply one exact,
  case-sensitive calendar name with `--calendar`; missing, empty, unknown, or
  ambiguous names fail. There is no `--config` option or config-file fallback.
- Add `last-week --only-meetings` to keep events with at least one attendee.
  This checks EventKit attendees before projecting names, so an event with only
  unnamed attendees still qualifies and may show an empty names array. Recurring
  meetings are included automatically, like other weekly events.
- Weekly output is a **top-level JSON array**, with exactly `attendees`,
  `location`, `end`, `start`, and `title` per event. Attendees are an array of
  names, with unnamed/blank-name entries omitted. No attendees produces `[]`;
  a missing location is `null`. No events produces `[]`.
- Weekly start/end values retain full timestamps with offsets, regardless of
  `datetime_format`. All-day events retain date-only values with an exclusive
  end date. The weekly layout is hard-coded, includes no notes or
  identifiers, and cannot be used as update input. It is separate from the
  extract/update JSON envelope and schemas.
- Daily reports combine configured calendars; weekly reports use only the named
  calendar. Events are sorted by start instant, then end instant. Ties retain
  original event order (and configured calendar order for daily reports). All-day events
  sort at local midnight. Overlapping events retain their original boundaries.
- Recurring events and detached exceptions are included. The base `extract`
  default is unchanged. Distinct events from different calendars are preserved.
- Every extraction must succeed before output is emitted. Failures produce
  stderr and a nonzero status without a partial report.

Example weekly output:

```json
[
  {
    "attendees": ["Anders Falkenhard Røn", "Claus Aschou Johannesen", "Diba Terese Markus"],
    "location": "3210-05.071 Mødelokal (20) AU Forskning (20)",
    "end": "2026-09-18T11:00:00+02:00",
    "start": "2026-09-18T09:00:00+02:00",
    "title": "Møde i data management koordinationsgruppen"
  }
]
```

Daily reports accept `--config PATH`. All reports accept `--help`:

```sh
CalendarOmni today --config examples/calendar-omni.yaml
CalendarOmni last-week --help
```

Relative config paths resolve from your shell's working directory. All reports
use this Mac's local time zone. CalendarOmni authorizes once, reads the selected
calendar(s) directly through EventKit, and formats the report in Swift. There is no
subprocess, JSON round trip, or scripting runtime requirement.

The earlier Ruby and Wolfram scripts remain available with their original weekly
CSV output and config-based calendar selection; native `last-week` uses JSON
and an explicit `--calendar` argument. The built-in commands are the
recommended interface. Their `--binary` / `binary=...`
overrides are unnecessary for the built-in commands. Report tests are part of the
Xcode test suite below.

## Extract

```sh
CalendarOmni extract --calendar "Ugeplan" \
  --from 2026-09-01 --to 2026-09-30 > events.json

CalendarOmni extract --calendar "Ugeplan" \
  --from 2026-09-01 --to 2026-09-30 --filter "report" \
  --fields title,start,end,location --format csv > events.csv

CalendarOmni extract --calendar "Ugeplan" \
  --from 2026-09-01 --to 2026-09-30 --include-recurring

# Only events with attendees, even when attendees are omitted from the output:
CalendarOmni extract --calendar "Ugeplan" \
  --from 2026-09-01 --to 2026-09-30 --only-meetings --fields title,start,end
```

`--only-meetings` keeps events with at least one attendee exposed by EventKit.
It combines with `--filter` or `--regex` and does not require `attendees` in
`--fields`. Recurring meetings still require `--include-recurring`. Omitting
this flag preserves normal extraction; daily/weekly reports are unchanged.

- Calendar names match exactly and case-sensitively. Use `--calendar-id ID` instead
  when names are duplicated. Missing/ambiguous selections list names, sources, and
  IDs on stderr; no default calendar is silently selected.
- `--from` and `--to` are inclusive Gregorian dates. Events overlapping the interval
  are included with their full start/end values. A zero-duration event is included
  if its start lies inside the interval.
- Recurring events, including edited/detached occurrences, are excluded by default.
  `--include-recurring` adds matching instances within the range, not recurrence rules.
- `--filter TEXT` matches titles without case or diacritic sensitivity. Alternatively,
  `--regex PATTERN` uses a case-insensitive regular expression. They are exclusive.
- `--fields` accepts `all` (default) or an exact nonempty comma-separated selection
  from `title,start,end,location,attendees,notes,duration`. CSV follows that order.
- `--time-zone Europe/Copenhagen` overrides the Mac's zone for dates and rendering.
- Long intervals are fetched in windows of at most one year to avoid EventKit's
  four-year predicate limit. Repeated window results are deduplicated by identity
  and occurrence dates, not title.
- Results reflect the local EventKit store. They do not prove remote accounts have
  completed synchronization.

### Calculated duration

Request `duration` explicitly with extraction fields:

```sh
CalendarOmni extract --calendar "Kalender" --from 2026-09-01 --to 2026-09-30 \
  --fields title,start,end,duration --format csv
```

`duration` is `(end - start)` in elapsed minutes, with no unit suffix: JSON uses a
number and CSV a plain numeric cell (`45`, `90`, `1.5`). Fractional minutes are
preserved. It can be selected alone or alongside any content fields. Defaults
and `--fields all` retain the original six fields and omit duration.
For all-day events, boundaries are midnight in the selected output time zone;
DST transition days can be 1380 or 1500 minutes. This is an extraction-only,
read-only value: remove `duration` from the JSON field list and event objects
before using extracted JSON for updates. Create/update and report output are
unchanged. The extraction JSON schema includes this optional numeric field.

## Create one event

```sh
CalendarOmni create --calendar "Ugeplan" --title "Write report" \
  --date 2026-09-21 --start 09:00 --duration 1h30m \
  --time-zone Europe/Copenhagen --location "Office" --notes "Prepare first draft"

CalendarOmni create --calendar "Arbejdstid" --title "Daily sync" \
  --date 2026-09-21 --start 09:15 --end 09:30 --format csv

cat notes.txt | CalendarOmni create --calendar "Ugeplan" --title "Prepare talk" \
  --date 2026-09-22 --start 10:00 --duration 2h --notes-stdin
```

Title, start, and end are mandatory event values. `--date` and `--start` establish
the start; supply exactly one of `--end` or `--duration` to establish the end.
A clock end is on the same civil date. Use duration for overnight events.
Durations mean elapsed minutes, including across daylight-saving changes.
Nonexistent and ambiguous local creation times are rejected, not silently adjusted.

Location and notes are optional. `--notes-stdin` preserves UTF-8 text exactly,
including newlines; it never reads interactive input. It is exclusive with `--notes`.
Creation returns all six fields and fresh reference metadata. It supports timed,
non-recurring events only. Attendees are readable but **cannot be assigned through
EventKit**. There is no attendee creation option, JSON import, or upsert mode.

## Edit exported JSON and update

```sh
CalendarOmni extract --calendar "Ugeplan" \
  --from 2026-09-01 --to 2026-09-30 --filter "report" > events.json

# Edit content fields; leave each event's _ref unchanged.
CalendarOmni update --input events.json
# Or: cat events.json | CalendarOmni update --input -
```

JSON records always include `_ref` containing `eventId`, `calendarId`, `isRecurring`,
and `occurrenceDate`. The six content fields are separately selectable. Reference
IDs are local EventKit lookup references, not permanent global IDs. If lookup fails
following a calendar move or synchronization, extract again; update never creates
replacement events.

| Edited JSON | Update behavior |
| --- | --- |
| Writable field supplied | Replace its current value |
| Content field omitted | Preserve its current value |
| `location` or `notes` is `null` | Clear that field |
| `title`, `start`, or `end` is `null` | Reject |
| Attendees unchanged (order does not matter) | Preserve |
| Attendees changed | Reject |
| Event object removed | Do not update it; never delete it |

Retain the envelope. `command` records the export's origin; it does not choose an
action. The explicit CLI subcommand chooses the action. `fields` declares allowed
content fields; if you add a previously unselected field to an event, also add it to
`fields`. Omitting an event field does not require changing `fields`.

Each record needs `_ref` and at least one content field. Empty batches succeed
without accessing Calendar. Duplicate targets, unknown keys, stale IDs, read-only
calendars, and recurring or detached events are rejected. Recurrence is checked
against the live event, not trusted from JSON. Updates retain the event's existing
time zone and all-day/timed type, and preserve unexported properties such as alarms.
Timed values use RFC 3339 timestamps with explicit offsets; all-day values use dates
and an exclusive end. Type conversion is outside 1.1.0.

The entire batch is validated before staging changes, followed by a single commit.
This is not a cross-provider transaction guarantee. A failed commit or failed output
after a save may leave an uncertain outcome; re-extract before retrying. There is no
automatic retry or conflict merging: supplied values overwrite their current values,
so use a fresh export. Successful updates return all six fields for all input records,
including unchanged records, in input order.

## Formats and errors

JSON is the default. See [output schema](CalendarOmni.schema.json) and
[update-input schema](CalendarOmni.update.schema.json), both JSON Schema Draft
2020-12. Version `schemaVersion: 1` describes the data contract; it is distinct from
the application's `1.1.0` version. JSON includes explicit null values when selected
optional values are unset, and an empty array for no attendees.

CSV is UTF-8 with semicolon delimiters, CRLF record endings, and proper quoting.
The default header is:

```text
title;start;end;location;attendees;notes
```

Attendees are a compact JSON array of `{ "name": string-or-null, "url": string }`
inside one CSV cell. Multiline notes and punctuation are preserved. CSV has no `_ref`
metadata and is not an update format. Null and empty strings both become empty cells.
Import cells as text in spreadsheet software; calendar text is not modified to
escape spreadsheet formulas.

Successful commands write only data to stdout (help/version excepted). Diagnostics
use stderr. Empty extraction produces an empty JSON events array or CSV header.
Exit status: `0` success, `2` invalid arguments/input, `1` operation/output failure.
Never assume empty stdout means success. Creation is not idempotent: do not retry
blindly after an uncertain result.

## Tests and release verification

```sh
xcodebuild -project CalendarOmni.xcodeproj -scheme CalendarOmni \
  -configuration Debug -destination 'platform=macOS' -derivedDataPath build \
  -clonedSourcePackagesDirPath build/SourcePackages test

python3 scripts/check_cli.py build/Build/Products/Release/CalendarOmni
```

The tests cover date boundaries and DST, duration parsing, field selection, JSON/CSV
encoding, all 63 field subsets, update semantics, and recurrence classification of
in-memory events. They do not save events or need Calendar authorization. The CLI
check uses help, version, invalid input, and empty updates only.

See [VALIDATION.md](VALIDATION.md) for the actual checks run for this release and
remaining live checks. [SKILLS.md](SKILLS.md) is the operating guide for LLMs;
[DESIGN.md](DESIGN.md) and [PLAN.md](PLAN.md) retain design and verification detail.
