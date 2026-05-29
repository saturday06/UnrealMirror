@echo off
setlocal

cd /d "%~dp0.."

call "%~dp0\call-run-uat.bat" ^
  BuildCookRun ^
  -noP4 ^
  -platform=Win64 ^
  -clientconfig=Development ^
  -serverconfig=Development ^
  -cook ^
  -allmaps ^
  -build ^
  -stage ^
  -pak ^
  -archive ^
  "-project=%cd%\UnrealMirror.uproject"

endlocal
