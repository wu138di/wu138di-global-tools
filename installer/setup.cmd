@echo off
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0bootstrap.ps1" -Action Install %*
set RESULT=%ERRORLEVEL%
pause
exit /b %RESULT%
