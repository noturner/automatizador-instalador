@echo off
powershell.exe -NoProfile -ExecutionPolicy Bypass -Command "Start-Process powershell.exe -ArgumentList '-NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File \"%~dp0boot_config.ps1\"' -Verb RunAs -Wait -WindowStyle Hidden"
exit /b %ERRORLEVEL%
