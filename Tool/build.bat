@echo off

cd /d "%~dp0"

call .\ue-dotnet.bat tool restore
call .\ue-dotnet.bat tool run pwsh -- format.ps1
call .\ue-dotnet.bat tool run pwsh -- uat-build-cook-run.ps1 %*
