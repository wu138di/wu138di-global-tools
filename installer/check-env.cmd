@echo off
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0bootstrap.ps1" -Action Check %*
set RESULT=%ERRORLEVEL%
pause
exit /b %RESULT%
