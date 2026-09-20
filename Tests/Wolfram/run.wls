Get[FileNameJoin[{DirectoryName[DirectoryName[DirectoryName[$InputFileName]]], "scripts", "calendar_omni_helpers.wl"}]];
Module[{report},
    report = TestReport[FileNameJoin[{DirectoryName[$InputFileName], "helpers.wlt"}]];
    Print["Tests succeeded: ", report["TestsSucceededCount"], "; failed: ", report["TestsFailedCount"]];
    If[report["TestsFailedCount"] > 0,
        Print[InputForm[report["TestsFailed"]]];
        Exit[1], Exit[0]
    ]
];
