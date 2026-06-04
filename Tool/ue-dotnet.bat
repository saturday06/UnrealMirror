@echo off
setlocal
set "startup_cd=%cd%"
cd /d "%~dp0.."

for /f "delims=" %%A in (
  'powershell -NoLogo -NoProfile -Command "(Get-Content -Path UnrealMirror.uproject -Raw | ConvertFrom-Json).EngineAssociation"'
) do (
  set "engine_association=%%A"
)

set "registry_path=HKLM:\SOFTWARE\EpicGames\Unreal Engine\%engine_association%"
set "registry_value=InstalledDirectory"

for /f "delims=" %%A in (
  'powershell -NoLogo -NoProfile -Command "(Get-ItemProperty -Path $env:registry_path -Name $env:registry_value).$env:registry_value"'
) do (
  set "engine_root_path=%%A"
)

echo Unreal Engine root path: %engine_root_path%
call "%engine_root_path%\Engine\Build\BatchFiles\GetDotnetPath.bat"

cd /d "%startup_cd%"

set "DOTNET_CLI_UI_LANGUAGE=en"
set "VSLANG=1033"

dotnet %*

endlocal
