#!/usr/bin/env pwsh
# SPDX-License-Identifier: Apache-2.0
#Requires -Version 7.4

param(
  [switch]$shipping
)

$ErrorActionPreference = "Stop"
$PSNativeCommandUseErrorActionPreference = $true
Set-StrictMode -Version 3

if ($IsWindows) {
  $platform = "Win64"
}
elseif ($IsMacOS) {
  $platform = "Mac"
}
else {
  throw "Unsupported platform: $($PSVersionTable.Platform)"
}

$scriptFolderPath = Split-Path -Parent $MyInvocation.MyCommand.Path
$projectRootPath = Resolve-Path (Join-Path $scriptFolderPath '..')
Set-Location $projectRootPath
$projectPath = Join-Path $projectRootPath 'UnrealMirror.uproject'
$buildConfiguration = if ($shipping) { 'Shipping' } else { 'Development' }
& (Join-Path $scriptFolderPath 'run-uat.ps1') `
  BuildCookRun `
  -noP4 `
  "-platform=$platform" `
  "-clientconfig=$buildConfiguration" `
  "-serverconfig=$buildConfiguration" `
  -cook `
  -allmaps `
  -build `
  -stage `
  -pak `
  -archive `
  "-project=$projectPath"
exit $LASTEXITCODE
