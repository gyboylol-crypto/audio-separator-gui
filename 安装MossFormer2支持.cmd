@echo off
chcp 65001 >nul
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0setup-mossformer.ps1"
if errorlevel 1 pause

