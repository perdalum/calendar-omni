(* Run with: wlf scripts/last-week.wls *)
Get[FileNameJoin[{DirectoryName[$InputFileName], "calendar_omni_helpers.wl"}]];
Exit[CalendarOmniHelpers`RunReport["last-week", Rest[$ScriptCommandLine]]];
