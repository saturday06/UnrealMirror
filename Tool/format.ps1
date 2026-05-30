#!/usr/bin/env pwsh
# SPDX-License-Identifier: Apache-2.0
#Requires -Version 7.4

$ErrorActionPreference = "Stop"
$PSNativeCommandUseErrorActionPreference = $true
Set-StrictMode -Version 3

$scriptFolderPath = Split-Path -Parent $MyInvocation.MyCommand.Path
$repositoryRootPath = Resolve-Path (Join-Path $scriptFolderPath '..')

Write-Output 'Formatting C# files...'
Set-Location $scriptFolderPath
& dotnet tool restore
& dotnet tool run csharpier format ../Source

Write-Output 'Formatting C/C++ files...'
Set-Location $repositoryRootPath
if ($IsWindows) {
  $vswhere = "${env:ProgramFiles(x86)}\Microsoft Visual Studio\Installer\vswhere.exe"
  if (-not (Test-Path $vswhere)) {
    throw "vswhere.exe was not found: $vswhere"
  }
  $vsInstallPath = & $vswhere `
    -latest `
    -products * `
    -requires Microsoft.VisualStudio.Component.VC.Llvm.Clang `
    -property installationPath
  if (-not $vsInstallPath) {
    throw "Clang for Visual Studio was not found"
  }
  $clangFormat = Join-Path $vsInstallPath "VC\Tools\Llvm\x64\bin\clang-format.exe"
}
elseif ($IsMacOS) {
  $clangFormat = & xcrun --find clang-format
}
elseif ($IsLinux) {
  $clangFormat = & which clang-format
}
else {
  throw "Unsupported platform: $($PSVersionTable.Platform)"
}

if (-not (Test-Path $clangFormat)) {
  throw "clang-format.exe was not found: $clangFormat"
}

Get-ChildItem -Path Source -Recurse -File -Include *.c, *.cpp, *.h | ForEach-Object {
  Write-Output "Formatting: $($_.FullName)"
  & $clangFormat -i $_.FullName
}
