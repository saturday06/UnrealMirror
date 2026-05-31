#!/usr/bin/env pwsh
# SPDX-License-Identifier: Apache-2.0
#Requires -Version 7.4

$ErrorActionPreference = "Stop"
$PSNativeCommandUseErrorActionPreference = $true
Set-StrictMode -Version 3

$env:DOTNET_CLI_UI_LANGUAGE = "en"

if ($IsWindows) {
  $vsVersionRange = "[17.0,18.0)"
  $vswhere = "${env:ProgramFiles(x86)}\Microsoft Visual Studio\Installer\vswhere.exe"
  if (-not (Test-Path $vswhere)) {
    throw "vswhere.exe was not found: $vswhere"
  }
  $vsInstallationPath = & $vswhere -version $vsVersionRange -property installationPath
  if (-not $vsInstallationPath) {
    throw "Visual Studio was not found"
  }
  $clangFormat = Join-Path $vsInstallationPath "VC\Tools\Llvm\x64\bin\clang-format.exe"
}
elseif ($IsMacOS) {
  $clangFormat = & xcrun --find clang-format
}
else {
  $clangFormat = (Get-Command clang-format).Source
}
if (-not (Test-Path $clangFormat)) {
  throw "clang-format.exe was not found: $clangFormat"
}

Push-Location $PSScriptRoot
try {
  Write-Output 'Formatting C/C++ files...'
  Get-ChildItem ../Source -Recurse -File -Include *.c, *.cpp, *.h | ForEach-Object {
    Write-Output "Formatting: $($_.FullName)"
    & $clangFormat -i $_.FullName
  }

  Write-Output 'Formatting C# files...'
  & dotnet tool restore
  & dotnet tool run csharpier format ../Source
}
finally {
  Pop-Location
}
