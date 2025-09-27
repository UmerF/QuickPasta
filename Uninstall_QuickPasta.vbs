' Uninstall_QuickPasta.vbs — removes per-user menu
Option Explicit
Dim sh: Set sh = CreateObject("Wscript.Shell")
sh.Run "reg.exe delete ""HKCU\Software\Classes\Directory\shell\QuickPasta"" /f", 0, True
sh.Run "reg.exe delete ""HKCU\Software\Classes\*\shell\QuickPasta"" /f", 0, True
sh.Run "reg.exe delete ""HKCU\Software\Classes\Directory\Background\shell\QuickPasta"" /f", 0, True
Dim cmdStoreRoot: cmdStoreRoot = "HKCU\Software\Microsoft\Windows\CurrentVersion\Explorer\CommandStore\shell"
Call RemoveQP(cmdStoreRoot)
MsgBox "QuickPasta menu removed.", 64, "QuickPasta"

Sub RemoveQP(root)
  On Error Resume Next
  Dim wmi: Set wmi = GetObject("winmgmts:\\.\root\default:StdRegProv")
  Dim arr, k
  wmi.EnumKey &H80000001, Replace(root,"HKCU\",""), arr
  If IsArray(arr) Then
    For Each k In arr
      If Left(k,3) = "QP_" Then sh.Run "reg.exe delete """ & root & "\" & k & """ /f", 0, True
    Next
  End If
  On Error GoTo 0
End Sub
