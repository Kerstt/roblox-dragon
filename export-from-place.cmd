@echo off
rem Copies every script out of a place file into this folder (the fallback when
rem live sync didn't pick something up, e.g. a brand-new script).
rem   1. In Studio: File > Save to File As > "Roblox XML Place Files (*.rbxlx)".
rem   2. Drag that .rbxlx file onto this file, or just double-click to use the
rem      default location below.
rem   3. Then run push.cmd.
setlocal
cd /d "%~dp0"
set "PLACE=%~1"
if "%PLACE%"=="" set "PLACE=%USERPROFILE%\OneDrive\Documents\DragonTycoon.rbxlx"
if not exist "%PLACE%" (
  echo Can't find "%PLACE%".
  echo Save the place as .rbxlx first, then drag it onto this file.
  pause
  exit /b 1
)
python -I scripts\extract_scripts.py "%PLACE%" dragon-tycoon\src || (pause & exit /b 1)
echo.
echo What changed:
git status --short dragon-tycoon
pause
