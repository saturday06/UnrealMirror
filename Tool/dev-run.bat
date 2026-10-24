@echo off

call .\ue-dotnet.bat tool restore
call .\ue-dotnet.bat tool run pwsh -- format.ps1
call .\ue-dotnet.bat tool run pwsh -- dev-run.ps1 %*
