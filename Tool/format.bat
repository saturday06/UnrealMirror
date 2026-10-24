@echo off

call "%~dp0dotnet\ue-dotnet.bat" tool restore
call "%~dp0dotnet\ue-dotnet.bat" tool run pwsh -- format.ps1
