#!/usr/bin/env pwsh
# SPDX-License-Identifier: Apache-2.0
#Requires -Version 7.6

$ErrorActionPreference = "Stop"
$PSNativeCommandUseErrorActionPreference = $true
Set-StrictMode -Version 3

Import-Module -Name "${PSScriptRoot}\module.psm1"

$unrealEngineScriptRootPath = Find-UnrealEngineScriptRootPath

if ($IsWindows) {
  $runUatPath = Join-Path $unrealEngineScriptRootPath "RunUAT.bat"
}
elseif ($IsMacOS) {
  $runUatPath = Join-Path $unrealEngineScriptRootPath "RunUAT.sh"
}
elseif ($IsLinux) {
  $runUatPath = Join-Path $unrealEngineScriptRootPath "RunUAT.sh"
}
else {
  $errorMessage = "Unsupported platform: $($PSVersionTable.Platform)"
  throw $errorMessage
}

if (-not (Test-Path -Path $runUatPath -PathType Leaf)) {
  Write-Output "RunUAT was not found: ${runUatPath}"
  exit 1
}

try {
  & $runUatPath @args
  exit $LASTEXITCODE
}
catch [System.Management.Automation.NativeCommandExitException] {
  exit $_.Exception.ExitCode
}
