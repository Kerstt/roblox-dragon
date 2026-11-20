@echo off
rem Saves your changes to GitHub: double-click, type what you changed, press Enter.
setlocal
cd /d "%~dp0"
git add -A
git diff --cached --quiet
if %errorlevel%==0 (
  echo Nothing new to push.
  pause
  exit /b 0
)
echo Changed files:
git status --short
echo.
set "MSG="
set /p "MSG=What did you change? "
if "%MSG%"=="" set "MSG=Update from Roblox Studio"
git commit -q -m "%MSG%" || goto :failed
git pull --rebase -q || goto :failed
git push -q || goto :failed
echo.
echo Pushed to GitHub!
pause
exit /b 0

:failed
echo.
echo Something went wrong (see the message above). Nothing was lost; ask for help.
pause
exit /b 1
