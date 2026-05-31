#!/usr/bin/env pwsh
# SPDX-License-Identifier: Apache-2.0
#Requires -Version 7.4

param(
  [string]$TargetPlatform,
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
else {
  throw "Unsupported platform: $($PSVersionTable.Platform)"
}

$projectRootPath = Resolve-Path (Join-Path $PSScriptRoot "..")
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
