#!/usr/bin/env pwsh
# SPDX-License-Identifier: Apache-2.0
#Requires -Version 7.4

$ErrorActionPreference = "Stop"
$PSNativeCommandUseErrorActionPreference = $true
Set-StrictMode -Version 3

$scriptFolderPath = Split-Path -Parent $MyInvocation.MyCommand.Path
$projectRootPath = Resolve-Path (Join-Path $scriptFolderPath '..')
Set-Location $projectRootPath
$projectPath = Join-Path $projectRootPath 'UnrealMirror.uproject'
& (Join-Path $scriptFolderPath 'run-uat.ps1') `
  BuildCookRun `
  -noP4 `
  -platform=Win64 `
  -clientconfig=Development `
  -serverconfig=Development `
  -cook `
  -allmaps `
  -build `
  -stage `
  -pak `
  -archive `
  "-project=$projectPath"
exit $LASTEXITCODE
