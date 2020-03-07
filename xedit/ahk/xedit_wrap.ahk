#Persistent
SetTitleMatchMode 2
SetTimer, CheckScript, 100

script_started := []

Return

CheckScript:
IfWinExist, Module Selection ahk_class TfrmModuleSelect
{
	WinGet, id, list, Module Selection ahk_class TfrmModuleSelect
	Loop, %id% {
		hwid := id%a_index%
		WinActivate, ahk_id %hwid%
		ControlSend,, {Enter}, ahk_id %hwid%
	}
}

IfWinExist, Applying script ahk_class TfrmMain
{
	WinGet, id, list, Applying script ahk_class TfrmMain
	Loop, %id% {
		hwid := id%a_index%
		if (!script_started[hwid]) {
			script_started[hwid] := true
		}
	}
}

IfWinExist, FO4Script ahk_class TfrmMain
{
	WinGet, id, list, FO4Script ahk_class TfrmMain
	Loop, %id% {
		hwid := id%a_index%
		if (!script_started[hwid]) {
			Return
		}

;		WinActivate, ahk_id %hwid%
;		WinWaitActive, ahk_id %hwid%
		WinClose, ahk_id %hwid%
		WinWaitClose, ahk_id %hwid%

		script_started.delete(hwid)
		if (script_started.count() == 0) {
			ExitApp
		}
	}
}

Return
