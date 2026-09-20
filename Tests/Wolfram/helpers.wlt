Begin["CalendarOmniHelpersTests`"];
zone = "Europe/Copenhagen";
config = <|"calendars" -> {"A", "B"}, "fields" -> {"title", "start", "end", "notes", "attendees"}, "datetime_format" -> "simple"|>;
event[title_, start_, end_] := <|"title" -> title, "start" -> start, "end" -> end, "notes" -> "first; \"quote\"\nsecond", "attendees" -> {}|>;
date[y_, m_, d_] := DateObject[{y, m, d}, "Day", "Gregorian", zone];
configText[text_] := Module[{path, result},
    path = CreateTemporary[]; Export[path, text, "Text", CharacterEncoding -> "UTF-8"];
    result = CalendarOmniHelpers`LoadConfig[path]; DeleteFile[path]; result
];

VerificationTest[CalendarOmniHelpers`ReportDateRange["today", date[2026,9,20]], {"2026-09-20", "2026-09-20"}, TestID -> "today"]
VerificationTest[CalendarOmniHelpers`ReportDateRange["tomorrow", date[2026,12,31]], {"2027-01-01", "2027-01-01"}, TestID -> "tomorrow-year-boundary"]
VerificationTest[CalendarOmniHelpers`ReportDateRange["last-week", date[2026,9,20]], {"2026-09-07", "2026-09-13"}, TestID -> "last-week-sunday"]
VerificationTest[CalendarOmniHelpers`ReportDateRange["last-week", date[2026,9,21]], {"2026-09-14", "2026-09-20"}, TestID -> "last-week-monday"]
VerificationTest[CalendarOmniHelpers`ReportDateRange["last-week", date[2026,1,1]], {"2025-12-22", "2025-12-28"}, TestID -> "last-week-year-boundary"]
VerificationTest[CalendarOmniHelpers`ReportDateRange["last-week", date[2026,3,30]], {"2026-03-23", "2026-03-29"}, TestID -> "spring-dst-week"]
VerificationTest[CalendarOmniHelpers`ReportDateRange["last-week", date[2026,10,26]], {"2026-10-19", "2026-10-25"}, TestID -> "fall-dst-week"]
VerificationTest[FailureQ[CalendarOmniHelpers`ReportDateRange["bad", date[2026,9,20]]], True, TestID -> "invalid-mode"]

VerificationTest[CalendarOmniHelpers`Timestamp["2026-09-20T09:30:00+02:00", zone] === CalendarOmniHelpers`Timestamp["2026-09-20T07:30:00Z", zone], True, TestID -> "offset-sorting"]
VerificationTest[CalendarOmniHelpers`Timestamp["2026-09-20T09:30:00-03:00", zone] === CalendarOmniHelpers`Timestamp["2026-09-20T12:30:00Z", zone], True, TestID -> "negative-offset"]
VerificationTest[CalendarOmniHelpers`Timestamp["2026-09-20T00:00:00+02:00", zone] === CalendarOmniHelpers`Timestamp["2026-09-20", zone], True, TestID -> "all-day-midnight"]
VerificationTest[CalendarOmniHelpers`Timestamp["2026-09-20T09:00:00.123456789Z", zone] - CalendarOmniHelpers`Timestamp["2026-09-20T09:00:00.123456788Z", zone], 1/10^9, TestID -> "nanosecond-ordering"]
VerificationTest[FailureQ[CalendarOmniHelpers`Timestamp["2026-02-30T09:00:00Z", zone]], True, TestID -> "invalid-civil-date"]
VerificationTest[FailureQ[CalendarOmniHelpers`Timestamp["2026-09-20T24:00:00Z", zone]], True, TestID -> "invalid-clock"]
VerificationTest[FailureQ[CalendarOmniHelpers`Timestamp["2026-09-20T09:00:00", zone]], True, TestID -> "missing-offset"]
VerificationTest[CalendarOmniHelpers`DisplayDateTime["2026-09-20T07:30:45Z", "today", "simple", zone], "09:30", TestID -> "simple-local-time"]
VerificationTest[CalendarOmniHelpers`DisplayDateTime["2026-01-20T07:30:45Z", "last-week", "simple", zone], "2026-01-20 08:30", TestID -> "winter-dst-rendering"]
VerificationTest[CalendarOmniHelpers`DisplayDateTime["2026-09-20T07:30:45.123456789Z", "today", "full", zone], "2026-09-20T07:30:45.123456789Z", TestID -> "full-preserved"]
VerificationTest[CalendarOmniHelpers`DisplayDateTime["2026-09-20", "today", "simple", zone], "all-day", TestID -> "all-day-daily"]
VerificationTest[CalendarOmniHelpers`DisplayDateTime["2026-09-20", "last-week", "simple", zone], "2026-09-20", TestID -> "all-day-weekly"]
VerificationTest[CalendarOmniHelpers`Render["today", config, {event["Møde\nAnden linje", "2026-09-20T09:00:00+02:00", "2026-09-20T10:30:00+02:00"]}, zone], "09:00 -- 10:30 : Møde Anden linje\n", TestID -> "daily-layout-unicode-multiline"]
VerificationTest[CalendarOmniHelpers`Render["tomorrow", config, {}, zone], "", TestID -> "empty-day"]
VerificationTest[CalendarOmniHelpers`Render["last-week", config, {}, zone], "title;start;end;notes;attendees\r\n", TestID -> "empty-week"]
VerificationTest[CalendarOmniHelpers`Render["last-week", <|"fields" -> {"title", "notes", "attendees"}|>, {event["a;\"b\"", "2026-09-20T09:00:00Z", "2026-09-20T10:00:00Z"]}, zone], "title;notes;attendees\r\n\"a;\"\"b\"\"\";\"first; \"\"quote\"\"\nsecond\";[]\r\n", TestID -> "weekly-csv-quoting"]
VerificationTest[CalendarOmniHelpers`Render["today", config, {event["later", "2026-09-20T09:00:00Z", "2026-09-20T10:00:00Z"], event["earlier", "2026-09-20T09:30:00+02:00", "2026-09-20T10:30:00+02:00"]}, zone], "09:30 -- 10:30 : earlier\n11:00 -- 12:00 : later\n", TestID -> "global-sort-before-format"]

VerificationTest[configText["calendars: [A, B]\nfields: [title, start]\n"]["datetime_format"], "full", TestID -> "yaml-default-full"]
VerificationTest[configText["# comment\ncalendars:\n  - A\n  - 'Komme-gå'\nfields: [title, start]\ndatetime_format: simple\n"]["calendars"], {"A", "Komme-gå"}, TestID -> "yaml-native"]
VerificationTest[FailureQ[configText["calendars: [A]\ncalendars: [B]\nfields: [title]\n"]], True, TestID -> "yaml-duplicate-keys"]
VerificationTest[FailureQ[configText["calendars: [A, A]\nfields: [title]\n"]], True, TestID -> "yaml-duplicate-calendars"]
VerificationTest[FailureQ[configText["calendars: []\nfields: [title]\n"]], True, TestID -> "yaml-empty-calendars"]
VerificationTest[FailureQ[configText["calendars: [A]\nfields: [bad]\n"]], True, TestID -> "yaml-unknown-fields"]
VerificationTest[FailureQ[configText["calendars: [A]\nfields: [title]\ndatetime_format: short\n"]], True, TestID -> "yaml-invalid-format"]
VerificationTest[FailureQ[configText["calendars: &a [A]\nfields: *a\n"]], True, TestID -> "yaml-aliases"]
End[];
