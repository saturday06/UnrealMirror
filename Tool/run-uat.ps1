#!/usr/bin/env pwsh
# SPDX-License-Identifier: Apache-2.0
#Requires -Version 7.4

$ErrorActionPreference = "Stop"
$PSNativeCommandUseErrorActionPreference = $true
Set-StrictMode -Version 3

$registryPath = 'HKLM:\SOFTWARE\EpicGames\Unreal Engine\5.7'
$registryValue = 'InstalledDirectory'

$unrealEngineRootPath = (Get-ItemProperty -Path $registryPath -Name $registryValue).$registryValue
if (-not $unrealEngineRootPath) {
  Write-Output "Unreal Engine installation path not found in registry: $registryPath\$registryValue"
  exit 1
}

$runUatPath = Join-Path $unrealEngineRootPath 'Engine\Build\BatchFiles\RunUAT.bat'
if (-not (Test-Path -Path $runUatPath -PathType Leaf)) {
  Write-Output "RunUAT.bat was not found: $runUatPath"
  exit 1
}

try {
  & $runUatPath @args
  exit $LASTEXITCODE
}
catch [System.Management.Automation.NativeCommandExitException] {
  exit $_.Exception.ExitCode
}
