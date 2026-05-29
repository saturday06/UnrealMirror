@echo off
setlocal

set "registry_path=HKLM\SOFTWARE\EpicGames\Unreal Engine\5.7"
set "registry_value=InstalledDirectory"
set "unreal_engine_root_path="
for /f "usebackq delims=" %%A in (
  `powershell -NoProfile -Command "(Get-ItemProperty ('Registry::' + $env:registry_path)).$env:registry_value"`
) do (
  set "unreal_engine_root_path=%%A"
)

if not defined unreal_engine_root_path (
  >&2 echo RunUAT.bat was not found. Check %registry_path%\%registry_value%.
  exit /b 1
)

set "run_uat_path=%unreal_engine_root_path%\Engine\Build\BatchFiles\RunUAT.bat"
if not exist "%run_uat_path%" (
  >&2 echo RunUAT.bat was not found: %run_uat_path%
  exit /b 1
)

call "%run_uat_path%" %*
set "exit_code=%ERRORLEVEL%"

endlocal & exit /b %exit_code%
