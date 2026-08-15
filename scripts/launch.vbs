Dim fso, shell, scriptDir, psScript, cmd
Set fso = CreateObject("Scripting.FileSystemObject")
scriptDir = fso.GetParentFolderName(WScript.ScriptFullName)
psScript = fso.BuildPath(scriptDir, "launch.ps1")

cmd = "powershell.exe -ExecutionPolicy Bypass -NoProfile -WindowStyle Hidden -File """ & psScript & """"
Set shell = CreateObject("WScript.Shell")
shell.Run cmd, 0, False
