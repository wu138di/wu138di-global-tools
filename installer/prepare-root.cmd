@echo off
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0bootstrap.ps1" -Action PrepareRoot %*
set RESULT=%ERRORLEVEL%
pause
exit /b %RESULT%
