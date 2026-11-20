@echo off
rem Starts Rojo for a PERSONAL Studio copy.
rem Never connect this to the shared Team Create place unless you are the
rem integrator, on clean main, using sync-shared-place.cmd instead.
setlocal
cd /d "%~dp0"
for /f %%i in ('git branch --show-current') do set "BRANCH=%%i"
echo Starting Rojo for Dragon Tycoon...
echo Current branch: %BRANCH%
echo Connect this server only to your personal Studio copy.
echo In Studio: Plugins tab ^> Rojo ^> Connect   (localhost : 34872)
echo Leave this window open while you work. Close it to stop syncing.
echo.
if exist "%~dp0.tools\rojo.exe" (
  "%~dp0.tools\rojo.exe" serve dragon-tycoon\default.project.json
) else (
  rojo serve dragon-tycoon\default.project.json
)
pause
