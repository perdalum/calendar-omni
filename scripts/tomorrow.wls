(* Run with: wlf scripts/tomorrow.wls *)
Get[FileNameJoin[{DirectoryName[$InputFileName], "calendar_omni_helpers.wl"}]];
Exit[CalendarOmniHelpers`RunReport["tomorrow", Rest[$ScriptCommandLine]]];
