@echo off
setlocal
set "HERE=%~dp0"

rem  "debug" keeps the console open so errors are visible.
if /I "%~1"=="debug" (
    powershell.exe -NoProfile -ExecutionPolicy Bypass -STA -File "%HERE%AW2521HFL-Control.ps1" -ShowOnStart
    goto :eof
)

if exist "%HERE%AW2521HFL-Control.vbs" (
    start "" wscript.exe "%HERE%AW2521HFL-Control.vbs" show
) else (
    start "" powershell.exe -NoProfile -ExecutionPolicy Bypass -STA -WindowStyle Hidden -File "%HERE%AW2521HFL-Control.ps1" -ShowOnStart
)
