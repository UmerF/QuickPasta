' QuickPasta.vbs — hidden launcher
Option Explicit
Dim sh, args, ps1, profile, target, cmd
Set sh   = CreateObject("Wscript.Shell")
Set args = Wscript.Arguments

If args.Count < 3 Then
  WScript.Quit 1
End If

ps1     = args(0)
profile = args(1)
target  = args(2)

cmd = "powershell.exe -NoProfile -WindowStyle Hidden -ExecutionPolicy Bypass -File """ & ps1 & """ -Profile """ & profile & """ -Target """ & target & """"
sh.Run cmd, 0, True   ' 0 = hidden, True = wait
