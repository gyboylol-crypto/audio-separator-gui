@echo off
chcp 65001 >nul
"%~dp0.runtime\python\python.exe" -X utf8 "%~dp0app\deploy_models.py"
pause
