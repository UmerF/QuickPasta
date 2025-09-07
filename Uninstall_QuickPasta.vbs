' Uninstall_QuickPasta.vbs — removes per-user menu
Option Explicit
Dim sh: Set sh = CreateObject("Wscript.Shell")
sh.Run "reg.exe delete ""HKCU\Software\Classes\Directory\shell\QuickPasta"" /f", 0, True
sh.Run "reg.exe delete ""HKCU\Software\Classes\*\shell\QuickPasta"" /f", 0, True
sh.Run "reg.exe delete ""HKCU\Software\Classes\Directory\Background\shell\QuickPasta"" /f", 0, True
MsgBox "QuickPasta menu removed.", 64, "QuickPasta"
