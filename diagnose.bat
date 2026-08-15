@echo off
title DeepSeek Harness Launcher Diagnostics
cd /d "%~dp0"
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0scripts\diagnose.ps1" > "%TEMP%\deepseek-harness-launcher-diagnostics.txt"
type "%TEMP%\deepseek-harness-launcher-diagnostics.txt"
echo.
echo Saved to: %TEMP%\deepseek-harness-launcher-diagnostics.txt
pause
