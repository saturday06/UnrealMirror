#!/usr/bin/env pwsh
# SPDX-License-Identifier: Apache-2.0
#Requires -Version 7.4

$ErrorActionPreference = "Stop"
$PSNativeCommandUseErrorActionPreference = $true
Set-StrictMode -Version 3

$uprojectPath = Join-Path $PSScriptRoot "..\UnrealMirror.uproject"
if (-not (Test-Path -Path $uprojectPath -PathType Leaf)) {
  Write-Output "uproject file was not found: $uprojectPath"
  exit 1
}

$uproject = Get-Content -Path $uprojectPath -Raw | ConvertFrom-Json
$unrealEngineAssociation = $uproject.EngineAssociation
if (-not $unrealEngineAssociation) {
  Write-Output "EngineAssociation is not set in uproject: $uprojectPath"
  exit 1
}

if ($IsWindows) {
  $registryPath = "HKLM:\SOFTWARE\EpicGames\Unreal Engine\${unrealEngineAssociation}"
  $registryValue = 'InstalledDirectory'

  $unrealEngineRootPath = (Get-ItemProperty -Path $registryPath -Name $registryValue).$registryValue
  if (-not $unrealEngineRootPath) {
    Write-Output "Unreal Engine installation path not found in registry: $registryPath\$registryValue"
    exit 1
  }

  $runUatPath = Join-Path $unrealEngineRootPath 'Engine\Build\BatchFiles\RunUAT.bat'
}
elseif ($IsMacOS) {
  $runUatPath = "/Users/Shared/Epic Games/UE_${unrealEngineAssociation}/Engine/Build/BatchFiles/RunUAT.sh"
}
else {
  throw "Unsupported platform: $($PSVersionTable.Platform)"
}

if (-not (Test-Path -Path $runUatPath -PathType Leaf)) {
  Write-Output "RunUAT was not found: $runUatPath"
  exit 1
}

try {
  & $runUatPath @args
  exit $LASTEXITCODE
}
catch [System.Management.Automation.NativeCommandExitException] {
  exit $_.Exception.ExitCode
}
