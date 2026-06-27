@echo off
setlocal
set "startup_cd=%cd%"
cd /d "%~dp0..\.."
set "PSModulePath=" & rem In default pwsh to powershell or powershell to pwsh causes module load error

for /f "delims=" %%A in (
  'powershell -NoLogo -NoProfile -ExecutionPolicy RemoteSigned -Command "Import-Module .\Tool\dotnet\module.psm1; Find-UnrealEngineScriptRootPath"'
) do (
  set "unreal_engine_script_root_path=%%A"
)
if "%unreal_engine_script_root_path: =%"=="" (
  echo Failed to find Unreal Engine Script Root Directory
  exit /b 1
)

call "%unreal_engine_script_root_path%\GetDotnetPath.bat"

cd /d "%startup_cd%"

set "DOTNET_CLI_TELEMETRY_OPTOUT=1"
set "DOTNET_CLI_UI_LANGUAGE=en"
set "VSLANG=1033"

dotnet %*

endlocal
