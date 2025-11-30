' QuickPasta.vbs — hidden launcher
Option Explicit
Dim sh, args, ps1, profile, target, cmd, elevate, shellApp
Set sh   = CreateObject("Wscript.Shell")
Set args = Wscript.Arguments
Set shellApp = CreateObject("Shell.Application")

If args.Count < 3 Then
  WScript.Quit 1
End If

ps1     = args(0)
profile = args(1)
target  = args(2)
elevate = False
If args.Count >= 4 Then elevate = (LCase(args(3)) = "elevate")

If elevate Then
  Dim psArgs
  psArgs = "-NoProfile -NonInteractive -NoLogo -WindowStyle Hidden -ExecutionPolicy Bypass -File """ & ps1 & """ -Profile """ & profile & """ -Target """ & target & """"
  shellApp.ShellExecute "powershell.exe", psArgs, "", "runas", 0
  WScript.Quit
End If

cmd = "powershell.exe -NoProfile -NonInteractive -NoLogo -WindowStyle Hidden -ExecutionPolicy Bypass -File """ & ps1 & """ -Profile """ & profile & """ -Target """ & target & """"
sh.Run cmd, 0, True   ' 0 = hidden, True = wait
