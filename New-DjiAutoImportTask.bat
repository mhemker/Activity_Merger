@echo off
REM Double-click this to create the Task Scheduler task. It will prompt for
REM Administrator permission (a UAC popup) since the task requires elevation.
REM
REM Usage: New-DjiAutoImportTask.bat                       (default destination folder)
REM        New-DjiAutoImportTask.bat "D:\Footage\DJI"       (custom destination folder)
REM        New-DjiAutoImportTask.bat -Remove                (remove the task)

set "ARGS=%*"
if not "%~1"=="" (
    if /I "%~1"=="-Remove" (
        set "SCRIPT_ARGS=-Remove"
    ) else (
        set "SCRIPT_ARGS=-DestinationFolder \"%~1\""
    )
) else (
    set "SCRIPT_ARGS="
)

net session >nul 2>&1
if %errorLevel% == 0 (
    powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0New-DjiAutoImportTask.ps1" %SCRIPT_ARGS%
) else (
    powershell.exe -NoProfile -Command "Start-Process powershell -Verb RunAs -ArgumentList '-NoProfile -ExecutionPolicy Bypass -File ""%~dp0New-DjiAutoImportTask.ps1"" %SCRIPT_ARGS%'"
)

pause
