# Changelog

## 1.0.0 — 2026-09-20

- Add a zsh completion installer using Argument Parser's generated definitions,
  with file completion for report configs and update input files.

- Move daily and weekly reports into `CalendarOmni today`, `tomorrow`, and
  `last-week`, with direct EventKit access, shared CSV formatting, and the existing
  YAML config. Add pinned Yams 6.2.2; no scripting runtime required. Older script
  variants remain available for comparison.

- Add native Wolfram Language report variants (`today.wls`, `tomorrow.wls`,
  `last-week.wls`) for the user's `wlf` WSTP workflow, sharing the existing YAML
  config and matching Ruby report output. Keep the Ruby helpers available.

- Daily helpers print `FROM -- TO : TITLE`, one line per event without a header;
  weekly output remains configurable semicolon CSV.

- Add `datetime_format: simple|full` to helper config. Simple daily reports use
  HH:MM; simple weekly reports use YYYY-MM-DD HH:MM. Full preserves source values.

- Add `today`, `tomorrow`, and `last-week` reporting scripts using shared
  `~/.calendar-omni` YAML configuration for calendars and output fields.
- Merge results chronologically across calendars, include recurring events, and
  reject partial results if any calendar fails.

## 0.0.1 — 2026-09-20

- Initial macOS command-line tool with a native Xcode project and shared scheme.
- Extract events with exact calendar selection, title filtering, date ranges, and
  field selection; recurring events are opt-in with `--include-recurring`.
- Create a timed event with optional location and notes.
- Update non-recurring events from edited JSON while preserving omitted fields.
- JSON Schema contracts, semicolon CSV, embedded Calendar privacy description,
  focused tests, and an LLM operating guide.
