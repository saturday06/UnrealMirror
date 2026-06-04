#!/usr/bin/env pwsh
# SPDX-License-Identifier: Apache-2.0
#Requires -Version 7.4

$ErrorActionPreference = "Stop"
$PSNativeCommandUseErrorActionPreference = $true
Set-StrictMode -Version 3

$config = Import-PowerShellDataFile (Join-Path -Path $PSScriptRoot -ChildPath "config.psd1")
$vsVersionRange = $config.VsVersionRange

$clangFormat = $null
if ($IsWindows) {
  $vswhere = "${env:ProgramFiles(x86)}\Microsoft Visual Studio\Installer\vswhere.exe"
  if (Test-Path $vswhere) {
    $vsInstallationPath = $null
    try {
      $vsInstallationPath = & $vswhere `
        -version $vsVersionRange `
        -requires Microsoft.VisualStudio.Component.VC.Llvm.Clang `
        -property installationPath
    }
    catch [System.Management.Automation.NativeCommandExitException] {
      Write-Output "Visual Studio was not found in registry: ${vswhere} -version ${vsVersionRange} -property installationPath"
    }
    if ($vsInstallationPath) {
      $clangFormat = Join-Path $vsInstallationPath "VC\Tools\Llvm\x64\bin\clang-format.exe"
    }
  }
}
elseif ($IsMacOS) {
  try {
    $clangFormat = & xcrun --find clang-format
  }
  catch [System.Management.Automation.NativeCommandExitException] {
    Write-Output "clang-format was not found in xcrun"
  }
}
if (-not $clangFormat -or -not (Test-Path $clangFormat)) {
  $clangFormat = (Get-Command clang-format).Source
}

Push-Location $PSScriptRoot
try {
  Write-Output "Formatting C/C++ files..."
  Get-ChildItem ../Source -Recurse -File -Include *.c, *.cpp, *.h | ForEach-Object {
    Write-Output "Formatting: $($_.FullName)"
    & $clangFormat -i $_.FullName
  }

  Write-Output "Formatting C# files..."
  & dotnet tool restore
  & dotnet tool run csharpier format ../Source
}
finally {
  Pop-Location
}
