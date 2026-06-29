' Copilot Voice launcher - double-click to start the voice assistant.
Set fso = CreateObject("Scripting.FileSystemObject")
Set sh  = CreateObject("WScript.Shell")
scriptDir = fso.GetParentFolderName(WScript.ScriptFullName)
ps1 = scriptDir & "\CopilotVoice.ps1"
sh.CurrentDirectory = scriptDir
sh.Run "powershell.exe -NoProfile -ExecutionPolicy Bypass -NoExit -File """ & ps1 & """", 1, False
