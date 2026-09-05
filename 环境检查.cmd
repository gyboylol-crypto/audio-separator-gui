@echo off
chcp 65001 >nul
"%~dp0.runtime\python\python.exe" -I -X utf8 "%~dp0app\diagnose.py"
if errorlevel 1 echo Check failed. See messages above. If Python cannot start, install Microsoft VC++ x64 Runtime.
pause
