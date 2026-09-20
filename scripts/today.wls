(* Run with: wlf scripts/today.wls *)
Get[FileNameJoin[{DirectoryName[$InputFileName], "calendar_omni_helpers.wl"}]];
Exit[CalendarOmniHelpers`RunReport["today", Rest[$ScriptCommandLine]]];
