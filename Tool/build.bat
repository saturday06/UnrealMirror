@echo off

cd /d "%~dp0dotnet"

call .\ue-dotnet.bat tool restore
call .\ue-dotnet.bat tool run pwsh -- format.ps1
call .\ue-dotnet.bat tool run pwsh -- run-uat-build-cook-run.ps1 %*
