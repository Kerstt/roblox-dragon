@echo off
rem Connects Roblox Studio to this folder with Rojo.
rem   1. Double-click this file (leave the window open while you work).
rem   2. In Studio: Plugins tab > Rojo > Connect.
rem With "Two-Way Sync" on in the Rojo plugin's settings, script edits you make
rem in Studio are written into the files here. Edits to the files are sent to Studio.
cd /d "%~dp0"
echo Starting Rojo for Dragon Tycoon...
echo In Studio: Plugins tab ^> Rojo ^> Connect   (localhost : 34872)
echo Leave this window open while you work. Close it to stop syncing.
echo.
"%~dp0.tools\rojo.exe" serve dragon-tycoon
pause
