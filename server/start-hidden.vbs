' Pokreće server bez prozora: Planer zadataka zove wscript.exe s ovom skriptom (vidi autostart.ps1).
' Argument: putanja do node.exe. Izlaz servera ide u server\logs\server.log.
' Čeka da server stane, pa čuvar u Planeru (IgnoreNew) zna radi li još.
Set fso = CreateObject("Scripting.FileSystemObject")
dir = fso.GetParentFolderName(WScript.ScriptFullName)
q = Chr(34)
cmd = "cmd /c " & q & q & WScript.Arguments(0) & q & " " & q & dir & "\server.mjs" & q & " >> " & q & dir & "\logs\server.log" & q & " 2>&1" & q
CreateObject("WScript.Shell").Run cmd, 0, True
