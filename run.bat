@echo off
REM Copilot Voice launcher for Windows.
setlocal
cd /d "%~dp0"
where py >nul 2>nul
if %errorlevel%==0 (
  py copilot_voice.py %*
) else (
  python copilot_voice.py %*
)
