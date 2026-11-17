' Starts AW2521HFL Control with no console window.
' Pass "show" to open the panel immediately; with no argument it starts in the tray only.

Option Explicit

Dim shell, here, extra, command
Set shell = CreateObject("WScript.Shell")
here = Left(WScript.ScriptFullName, InStrRev(WScript.ScriptFullName, "\"))

extra = ""
If WScript.Arguments.Count > 0 Then
    If LCase(WScript.Arguments(0)) = "show" Then extra = " -ShowOnStart"
End If

command = "powershell.exe -NoProfile -ExecutionPolicy Bypass -STA -WindowStyle Hidden -File """ _
        & here & "AW2521HFL-Control.ps1""" & extra

shell.CurrentDirectory = here
shell.Run command, 0, False
