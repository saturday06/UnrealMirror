#!/usr/bin/env pwsh
# SPDX-License-Identifier: Apache-2.0
#Requires -Version 7.4

param(
  [ValidateSet("Android", "IOS", "Linux", "LinuxArm64", "Mac", "Win64")]
  [string]$TargetPlatform,
  [ValidateSet("Debug", "DebugGame", "Development", "Test", "Shipping")]
  [string]$TargetConfiguration = "Shipping"
)

$ErrorActionPreference = "Stop"
$PSNativeCommandUseErrorActionPreference = $true
Set-StrictMode -Version 3

if ($IsWindows) {
  if (-not ($TargetPlatform)) {
    $TargetPlatform = "Win64"
  }
}
elseif ($IsMacOS) {
  if (-not ($TargetPlatform)) {
    $TargetPlatform = "Mac"
  }
}
elseif ($IsLinux) {
  if (-not ($TargetPlatform)) {
    if ([System.Runtime.InteropServices.RuntimeInformation]::ProcessArchitecture -eq "Arm64") {
      $TargetPlatform = "LinuxArm64"
    }
    else {
      $TargetPlatform = "Linux"
    }
  }
}
else {
  $errorMessage = "Unsupported platform: $($PSVersionTable.Platform)"
  throw $errorMessage
}

$projectRootPath = Resolve-Path (Join-Path -Path $PSScriptRoot -ChildPath ".." -AdditionalChildPath "..")
$projectPath = Join-Path $projectRootPath "UnrealMirror.uproject"

Push-Location $projectRootPath
try {
  & (Join-Path $PSScriptRoot "run-uat.ps1") `
    BuildCookRun `
    -noP4 `
    "-platform=${TargetPlatform}" `
    "-clientconfig=${TargetConfiguration}" `
    "-serverconfig=${TargetConfiguration}" `
    -cook `
    -allmaps `
    -build `
    -stage `
    -pak `
    -archive `
    "-project=${projectPath}"
  exit $LASTEXITCODE
}
finally {
  Pop-Location
}
