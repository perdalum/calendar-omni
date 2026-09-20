(* Native Wolfram Language helpers. No Ruby, Perl, or shell parsing of event data. *)
BeginPackage["CalendarOmniHelpers`"];
RunReport::usage = "RunReport[mode, args] prints a report and returns an exit status. Used by the .wls entry points.";
Report::usage = "Report[mode, config, binary, today, zone] returns report text or Failure.";
LoadConfig::usage = "LoadConfig[path] reads and validates the shared YAML config.";
ReportDateRange::usage = "ReportDateRange[mode, today] returns inclusive civil date strings.";
Timestamp::usage = "Timestamp[text, zone] returns an exact UTC absolute time for sorting.";
DisplayDateTime::usage = "DisplayDateTime[text, mode, format, zone] formats a report boundary.";
Render::usage = "Render[mode, config, events, zone] sorts and formats event associations.";
Begin["`Private`"];

$projectRoot = DirectoryName[DirectoryName[$InputFileName]];
$fields = {"title", "start", "end", "location", "attendees", "notes"};
$tag = "CalendarOmniHelpersFailure";
fail[message_, code_: 2] := Throw[Failure["CalendarOmni", <|"MessageTemplate" -> message, "ExitCode" -> code|>], $tag];
require[condition_, message_, code_: 2] := If[!TrueQ[condition], fail[message, code]];
nonemptyStringsQ[value_] := ListQ[value] && Length[value] > 0 && AllTrue[value, StringQ[#] && StringTrim[#] =!= "" &];
expandPath[path_] := ExpandFileName[Which[
    path === "~", $HomeDirectory,
    StringStartsQ[path, "~/"], FileNameJoin[{$HomeDirectory, StringDrop[path, 2]}],
    StringStartsQ[path, "/"], path,
    True, FileNameJoin[{$projectRoot, path}]
]];

LoadConfig[path_String] := Catch[Module[{source, config, keys},
    require[FileExistsQ[path], "Config not found: " <> path];
    source = Quiet[Check[Import[path, "Text", CharacterEncoding -> "UTF-8"], $Failed]];
    require[StringQ[source], "Cannot read UTF-8 config: " <> path];
    require[MemberQ[$ImportFormats, "YAML"], "This Wolfram kernel does not have native YAML import."];
    (* Limit top-level layout to the documented block mapping. Native YAML import
       resolves duplicate keys, so check them before importing. Values still use YAML. *)
    keys = StringCases[source, RegularExpression["(?m)^([A-Za-z_][A-Za-z0-9_]*)[ \\t]*:"] -> "$1"];
    require[Length[keys] === Length[DeleteDuplicates[keys]], "Duplicate YAML config keys are not allowed."];
    require[ContainsAll[keys, {"calendars", "fields"}] && Complement[keys, {"calendars", "fields", "datetime_format"}] === {},
        "Use the documented YAML block mapping: calendars, fields, and optional datetime_format."];
    require[!StringContainsQ[source, RegularExpression["(?m)(?:^|:[ \\t]*|^[ \\t]*-[ \\t]+)[&*!]"]],
        "YAML anchors, aliases, and explicit tags are not supported."];
    (* Import the UTF-8 file directly; YAML ImportString in Wolfram 15 mishandles
       decoded non-ASCII characters. *)
    config = Quiet[Check[Import[path, "YAML"], $Failed]];
    require[AssociationQ[config] && Sort[Keys[config]] === Sort[keys], "Invalid YAML config or unsupported top-level layout."];
    Do[
        require[nonemptyStringsQ[config[key]], key <> " must be a nonempty list of strings."];
        require[Length[DeleteDuplicates[config[key]]] === Length[config[key]], "Duplicate entries in " <> key <> " are not allowed."],
        {key, {"calendars", "fields"}}
    ];
    require[Complement[config["fields"], $fields] === {}, "Unknown field in config. Choose title, start, end, location, attendees, notes."];
    If[!KeyExistsQ[config, "datetime_format"], AssociateTo[config, "datetime_format" -> "full"]];
    require[MemberQ[{"simple", "full"}, config["datetime_format"]], "datetime_format must be simple or full."];
    config
], $tag];

ReportDateRange[mode_String, today_DateObject] := Module[{first, last},
    If[!MemberQ[{"today", "tomorrow", "last-week"}, mode],
        Return[Failure["CalendarOmni", <|"MessageTemplate" -> "Unknown report: " <> mode, "ExitCode" -> 2|>]]];
    {first, last} = Switch[mode,
        "today", {today, today},
        "tomorrow", With[{next = DatePlus[today, {1, "Day"}]}, {next, next}],
        "last-week", first = DatePlus[today, {-(DateValue[today, "ISOWeekDay"] - 1) - 7, "Day"}];
            {first, DatePlus[first, {6, "Day"}]}
    ];
    DateString[#, {"ISODate"}] & /@ {first, last}
];

(* Parse numeric components without ToExpression: calendar text must never evaluate. *)
number[text_String] := FromDigits[text];
dateOnlyQ[text_] := StringQ[text] && StringMatchQ[text, RegularExpression["[0-9]{4}-[0-9]{2}-[0-9]{2}"]];
Timestamp[text_String, zone_] := Catch[Module[{parts, date, offset, fraction, clock, base},
    require[dateOnlyQ[text] || StringMatchQ[text,
        RegularExpression["[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}:[0-9]{2}(\\.[0-9]+)?(Z|[+-][0-9]{2}:[0-9]{2})"]],
        "Invalid event date: " <> text, 1];
    parts = number /@ StringSplit[StringTake[text, 10], "-"];
    date = Quiet[Check[DateObject[parts, "Day", "Gregorian", zone], $Failed]];
    require[DateObjectQ[date] && DateString[date, {"ISODate"}] === StringTake[text, 10], "Invalid civil date: " <> text, 1];
    If[dateOnlyQ[text], Return[AbsoluteTime[date]]];
    clock = number /@ StringSplit[StringTake[text, {12, 19}], ":"];
    require[clock[[1]] < 24 && clock[[2]] < 60 && clock[[3]] < 60, "Invalid event time: " <> text, 1];
    offset = If[StringEndsQ[text, "Z"], 0,
        With[{h = number[StringTake[text, {-5, -4}]], m = number[StringTake[text, -2]]},
            require[h < 24 && m < 60, "Invalid UTC offset: " <> text, 1];
            If[StringTake[text, {-6}] === "+", 1, -1] (h + m/60)
        ]
    ];
    fraction = StringCases[text, RegularExpression["\\.([0-9]+)"] -> "$1"];
    fraction = If[fraction === {}, 0, number[First[fraction]]/10^StringLength[First[fraction]]];
    base = AbsoluteTime[DateObject[Join[parts, clock], "Instant", "Gregorian", 0]];
    base - 3600 offset + fraction
], $tag];

DisplayDateTime[text_String, mode_String, format_String, zone_] := Module[{instant},
    If[format === "full", Return[text]];
    If[dateOnlyQ[text], Return[If[MemberQ[{"today", "tomorrow"}, mode], "all-day", text]]];
    instant = Timestamp[text, zone];
    If[FailureQ[instant], Return[instant]];
    DateString[FromAbsoluteTime[instant, TimeZone -> 0],
        If[mode === "last-week", {"ISODate", " ", "Hour", ":", "Minute"}, {"Hour", ":", "Minute"}], TimeZone -> zone]
];

csvCell[value_String] := If[StringContainsQ[value, {";", "\"", "\r", "\n"}], "\"" <> StringReplace[value, "\"" -> "\"\""] <> "\"", value];
compactJSON[value_] := ExportString[value, "RawJSON", "Compact" -> True];

Render[mode_String, config_Association, events_List, zone_] := Catch[Module[{keyed, ordered, format, columns, rows, output},
    format = Lookup[config, "datetime_format", "full"];
    keyed = MapIndexed[Function[{event, index}, With[{start = Timestamp[event["start"], zone], end = Timestamp[event["end"], zone]},
        If[FailureQ[start], Throw[start, $tag]]; If[FailureQ[end], Throw[end, $tag]];
        {{start, end, First[index]}, event}
    ]], events];
    ordered = Last /@ SortBy[keyed, First];
    If[MemberQ[{"today", "tomorrow"}, mode],
        Return[StringJoin[Function[event,
            DisplayDateTime[event["start"], mode, format, zone] <> " -- " <>
            DisplayDateTime[event["end"], mode, format, zone] <> " : " <>
            StringReplace[event["title"], RegularExpression["[\\r\\n\\x{0085}\\x{2028}\\x{2029}]+"] -> " "] <> "\n"
        ] /@ ordered]]
    ];
    columns = config["fields"];
    rows = Prepend[Function[event, Function[field,
        Switch[field,
            "start" | "end", DisplayDateTime[event[field], mode, format, zone],
            "attendees", compactJSON[event[field]],
            _, If[event[field] === Null, "", event[field]]
        ]
    ] /@ columns] /@ ordered, columns];
    output = StringJoin[(StringRiffle[csvCell /@ #, ";"] <> "\r\n") & /@ rows];
    output
], $tag];

findBinary[explicit_] := Module[{candidates},
    If[StringQ[explicit], candidates = {expandPath[explicit]},
        candidates = Join[FileNameJoin[{#, "CalendarOmni"}] & /@ StringSplit[Replace[Environment["PATH"], $Failed -> ""], ":"],
            {FileNameJoin[{$projectRoot, "build", "Build", "Products", "Release", "CalendarOmni"}]}]
    ];
    SelectFirst[candidates, FileType[#] === File &, Missing["NotFound"]]
];

validFieldQ[field_, value_] := Switch[field,
    "attendees", ListQ[value] && AllTrue[value, AssociationQ[#] && Sort[Keys[#]] === {"name", "url"} &&
        (#["name"] === Null || StringQ[#["name"]]) && StringQ[#["url"]] &],
    "location" | "notes", value === Null || StringQ[value],
    _, StringQ[value]
];

Report[mode_String, config_Association, binary_String, today_DateObject, zone_] := Catch[Module[
    {range, fields, combined = {}, result, payload, events, args, output},
    range = ReportDateRange[mode, today]; If[FailureQ[range], Return[range]];
    fields = If[mode === "last-week", DeleteDuplicates[Join[config["fields"], {"start", "end"}]], {"title", "start", "end"}];
    Do[
        args = {binary, "extract", "--calendar", calendar, "--from", First[range], "--to", Last[range],
            "--include-recurring", "--fields", StringRiffle[fields, ","], "--format", "json"};
        result = Quiet[Check[RunProcess[args], $Failed]];
        require[AssociationQ[result], "Could not run CalendarOmni: " <> binary, 1];
        require[result["ExitCode"] === 0, "CalendarOmni failed for " <> calendar <> ": " <> StringTrim[result["StandardError"]],
            If[result["ExitCode"] === 2, 2, 1]];
        payload = Quiet[Check[ImportString[result["StandardOutput"], "RawJSON"], $Failed]];
        require[AssociationQ[payload] && Lookup[payload, "schemaVersion"] === 1 && Lookup[payload, "command"] === "extract" &&
            Lookup[payload, "fields"] === fields && ListQ[Lookup[payload, "events"]], "Invalid CalendarOmni JSON response for " <> calendar, 1];
        events = payload["events"];
        require[AllTrue[events, Function[event, AssociationQ[event] && ContainsAll[Keys[event], fields] &&
            AllTrue[fields, validFieldQ[#, event[#]] &]]], "Incomplete or invalid event returned for " <> calendar, 1];
        combined = Join[combined, events],
        {calendar, config["calendars"]}
    ];
    output = Render[mode, config, combined, zone]; output
], $tag];

RunReport[mode_String, args_List] := Module[{result},
    If[args === {"help"},
        WriteString[First[$Output], "Usage: wlf scripts/" <> mode <> ".wls [config=PATH] [binary=PATH]\n" <>
            "Shared config: ~/.calendar-omni. Daily reports: FROM -- TO : TITLE. Weekly: semicolon CSV.\n"];
        Return[0]
    ];
    result = Catch[Module[{configPath, binaryPath = Automatic, config, binary, zone, today, key, value, text},
        require[MemberQ[{"today", "tomorrow", "last-week"}, mode], "Unknown report: " <> mode];
        configPath = FileNameJoin[{$HomeDirectory, ".calendar-omni"}];
        Do[
            require[StringContainsQ[arg, "="], "Expected config=PATH, binary=PATH, or help."];
            key = First[StringSplit[arg, "=", 2]]; value = StringDrop[arg, StringLength[key] + 1];
            require[MemberQ[{"config", "binary"}, key] && value =!= "", "Unknown or empty argument: " <> arg];
            If[key === "config", configPath = expandPath[value], binaryPath = value],
            {arg, args}
        ];
        config = LoadConfig[configPath]; If[FailureQ[config], Throw[config, $tag]];
        binary = findBinary[binaryPath]; require[StringQ[binary], "CalendarOmni not found. Build Release or supply binary=/absolute/path."];
        zone = $TimeZoneEntity;
        today = DateObject[Take[DateList[Now, TimeZone -> zone], 3], "Day", "Gregorian", zone];
        text = Report[mode, config, binary, today, zone]; If[FailureQ[text], Throw[text, $tag]];
        text
    ], $tag];
    If[FailureQ[result],
        (* WolframScript's WSTP transport buffers script output. Its Exit override
           returns a process status without terminating the continued kernel. *)
        WriteString[First[$Output], mode <> ": " <> result["MessageTemplate"] <> "\n"];
        Lookup[result[[2]], "ExitCode", 1],
        WriteString[First[$Output], result]; 0
    ]
];
End[];
EndPackage[];
