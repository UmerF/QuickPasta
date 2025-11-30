' Install_QuickPasta.vbs - hybrid installer:
'   • Modern menu: CommandStore + parent SubCommands (ordered)
'   • Classic fallback: parent\shell\00N_* children (ordered)
'   • Clean labels (numbers only in key/ID), single confirmation window

Option Explicit

Dim fso, sh, here, ps1, vbs, ico, cfg
Set fso = CreateObject("Scripting.FileSystemObject")
Set sh  = CreateObject("Wscript.Shell")

here = fso.GetParentFolderName(WScript.ScriptFullName)
ps1  = fso.BuildPath(here, "QuickPasta.ps1")
vbs  = fso.BuildPath(here, "QuickPasta.vbs")
ico  = fso.BuildPath(here, "QuickPasta.ico")
cfg  = fso.BuildPath(here, "profiles.json")

If Not fso.FileExists(ps1) Then MsgBox "Missing QuickPasta.ps1 next to installer.",16,"QuickPasta": WScript.Quit 1
If Not fso.FileExists(vbs) Then MsgBox "Missing QuickPasta.vbs next to installer.",16,"QuickPasta": WScript.Quit 1
If Not fso.FileExists(cfg) Then MsgBox "Missing profiles.json next to installer.",16,"QuickPasta": WScript.Quit 1

Dim namesWithFlags: namesWithFlags = ReadProfileNamesInOrder(cfg)
If IsEmpty(namesWithFlags) Then
  MsgBox "No profiles found in profiles.json.",16,"QuickPasta"
  WScript.Quit 1
End If

Dim names()
Dim symlinkMap: Set symlinkMap = CreateObject("Scripting.Dictionary")
ReDim names(UBound(namesWithFlags))
Dim idx: idx = 0
For idx = 0 To UBound(namesWithFlags)
  Dim parts: parts = Split(namesWithFlags(idx), "|~|")
  Dim nm: nm = Trim(parts(0))
  names(idx) = nm
  Dim flagVal: flagVal = False
  If UBound(parts) >= 1 Then
    flagVal = (LCase(Trim(CStr(parts(1)))) = "true")
  End If
  symlinkMap(nm) = flagVal
Next

' ---- Modern menu: CommandStore entries (QP_001_*, .) ----
Dim cmdStoreRoot: cmdStoreRoot = "HKCU\Software\Microsoft\Windows\CurrentVersion\Explorer\CommandStore\shell"
RegAdd cmdStoreRoot, "", "REG_SZ"
Call NukeQP(cmdStoreRoot)  ' remove only our previous QP_* items

Dim ids(), i
ReDim ids(UBound(names))
For i = 0 To UBound(names)
  Dim id: id = "QP_" & Pad3(i+1) & "_" & SafeKey(names(i))
  ids(i) = id
  Dim cs: cs = cmdStoreRoot & "\" & id
  RegAdd cs, "", "REG_SZ"
  RegWrite cs & "\MUIVerb", names(i), "REG_SZ"
  If fso.FileExists(ico) Then RegWrite cs & "\Icon", ico, "REG_SZ"
  RegAdd cs & "\command", "", "REG_SZ"
  Dim elevFlag: elevFlag = ""
  If symlinkMap.Exists(names(i)) Then
    If symlinkMap(names(i)) = True Then elevFlag = " elevate"
  End If
  Dim ccmd: ccmd = "wscript.exe """ & vbs & """ """ & ps1 & """ """ & names(i) & """ ""%1""" & elevFlag
  ' set (Default)
  RegWrite cs & "\command\", ccmd, "REG_SZ"
Next
Dim idsList: idsList = Join(ids, ";")

' ---- Parents: Directory, Files (*), and Background ----
Dim parents(2)
parents(0) = "HKCU\Software\Classes\Directory\shell\QuickPasta"
parents(1) = "HKCU\Software\Classes\*\shell\QuickPasta"
parents(2) = "HKCU\Software\Classes\Directory\Background\shell\QuickPasta"

For i = 0 To UBound(parents)
  BuildParent parents(i), names, idsList, (i = 2), symlinkMap
Next

' Refresh Explorer menus and finish
On Error Resume Next
sh.Run "rundll32.exe shell32.dll,SHChangeNotify 134217728,0,0,0", 0, False
On Error GoTo 0
MsgBox "QuickPasta menu installed/updated.", 64, "QuickPasta"
WScript.Quit 0

' ================= helpers =================

Sub BuildParent(parentKey, arrNames, idsList, isBackground, symlinkMap)
  ' Recreate parent fresh
  On Error Resume Next
  sh.Run "reg.exe delete """ & parentKey & """ /f", 0, True
  On Error GoTo 0

  RegAdd parentKey, "", "REG_SZ"
  RegWrite parentKey & "\MUIVerb", "Quick Pasta", "REG_SZ"
  If fso.FileExists(ico) Then RegWrite parentKey & "\Icon", ico, "REG_SZ"

  ' Modern path: explicit order via SubCommands (CommandStore IDs)
  RegWrite parentKey & "\SubCommands", idsList, "REG_SZ"

  ' Classic fallback: also create numbered children under parent\shell
  Dim shellKey: shellKey = parentKey & "\shell"
  RegAdd shellKey, "", "REG_SZ"

  Dim n, label, childKey, cmdKey, cmd, ph, elevFlagChild
  If isBackground Then ph = "%V" Else ph = "%1"

  For n = 0 To UBound(arrNames)
    label = arrNames(n)
    childKey = shellKey & "\" & Pad3(n+1) & "_" & SafeKey(label)
    RegAdd childKey, "", "REG_SZ"
    RegWrite childKey & "\MUIVerb", label, "REG_SZ"
    If fso.FileExists(ico) Then RegWrite childKey & "\Icon", ico, "REG_SZ"
    cmdKey = childKey & "\command"
    RegAdd cmdKey, "", "REG_SZ"
    elevFlagChild = ""
    If symlinkMap.Exists(label) Then
      If symlinkMap(label) = True Then elevFlagChild = " elevate"
    End If
    cmd = "wscript.exe """ & vbs & """ """ & ps1 & """ """ & label & """ """ & ph & """" & elevFlagChild
    RegWrite cmdKey & "\", cmd, "REG_SZ"
  Next
End Sub

Function ReadProfileNamesInOrder(jsonPath)
  Dim text, reKeys, matches, i, name, startPos, endPos, block, reSym, out(), outIdx
  text = LoadTextFile(jsonPath)
  Set reKeys = New RegExp
  reKeys.Global = True
  reKeys.Multiline = True
  reKeys.IgnoreCase = False
  reKeys.Pattern = "^\s{2}""([^""]+)""\s*:"
  Set matches = reKeys.Execute(text)
  If matches.Count = 0 Then
    ReadProfileNamesInOrder = Empty
    Exit Function
  End If
  ReDim out(-1)
  outIdx = -1
  For i = 0 To matches.Count - 1
    name = matches(i).SubMatches(0)
    startPos = matches(i).FirstIndex + 1
    If i < matches.Count - 1 Then
      endPos = matches(i+1).FirstIndex + 1
    Else
      endPos = Len(text) + 1
    End If
    block = Mid(text, startPos, endPos - startPos)
    Set reSym = New RegExp
    reSym.Global = False
    reSym.IgnoreCase = True
    reSym.Pattern = """symlink""\s*:\s*true"
    Dim flag : flag = "false"
    If reSym.Test(block) Then flag = "true"
    outIdx = outIdx + 1
    ReDim Preserve out(outIdx)
    out(outIdx) = name & "|~|" & flag
  Next
  ReadProfileNamesInOrder = out
End Function

Function LoadTextFile(path)
  Dim ts
  Set ts = fso.OpenTextFile(path, 1, False)
  LoadTextFile = ts.ReadAll
  ts.Close
End Function

Sub NukeQP(root)
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

Function SafeKey(s)
  Dim re: Set re = New RegExp
  re.Pattern = "[^\w\-]" : re.Global = True
  SafeKey = re.Replace(s, "-")
End Function

Function Pad3(n) : Pad3 = Right("00" & CStr(n), 3) : End Function

Sub RegAdd(path, value, kind) : sh.RegWrite path & "\", value, kind : End Sub
Sub RegWrite(path, value, kind) : sh.RegWrite path, value, kind : End Sub
