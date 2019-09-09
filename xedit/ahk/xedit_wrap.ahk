#Persistent
SetTitleMatchMode 2
SetTimer, CheckScript, 100

script_started := []

Return

CheckScript:
IfWinExist, Module Selection ahk_class TfrmModuleSelect
{
	WinActivate
	Send, {Enter}
}

IfWinExist, Applying script ahk_class TfrmMain
{
	WinGet, pid, pid
	if (!script_started[pid]) {
		script_started[pid] := true
	}
}

IfWinExist, FO4Script ahk_class TfrmMain
{
	WinGet, pid, pid
	if (script_started[pid]) {
		WinActivate
		WinClose

		script_started.delete(pid)
		if (script_started.count() == 0) {
			ExitApp
		}
	}
}

Return
