#!/usr/bin/env pwsh
# SPDX-License-Identifier: Apache-2.0
#Requires -Version 7.6

$ErrorActionPreference = "Stop"
$PSNativeCommandUseErrorActionPreference = $true
Set-StrictMode -Version 3

$uprojectPath = Join-Path -Path $PSScriptRoot -ChildPath "..", "..", "UnrealMirror.uproject"
if (-not (Test-Path -Path $uprojectPath -PathType Leaf)) {
  Write-Output "uproject file was not found: $uprojectPath"
  exit 1
}

$uproject = Get-Content -Path $uprojectPath -Raw | ConvertFrom-Json
$engineAssociation = $uproject.EngineAssociation
if (-not $engineAssociation) {
  Write-Output "EngineAssociation is not set in uproject: $uprojectPath"
  exit 1
}

if ($IsWindows) {
  $registryPath = "HKCU:\SOFTWARE\Epic Games\Unreal Engine\Builds"
  $engineInstalledPath = (Get-ItemProperty -Path $registryPath -Name $engineAssociation).$engineAssociation
  if (-not $engineInstalledPath) {
    Write-Output "Unreal Engine installation path not found in registry: $registryPath\$engineAssociation"
    exit 1
  }

  $runUatPath = Join-Path $engineInstalledPath "Engine\Build\BatchFiles\RunUAT.bat"
}
elseif ($IsMacOS) {
  $ueRoot = $env:UE_ROOT
  if (-not ($ueRoot)) {
    if ($engineAssociation -eq "{319F7083-488A-3A0F-0A6A-2E8235E8900D}") {
      $ueRoot = "/Users/Shared/Epic Games/UE_5.8/Engine/Build/BatchFiles"
    }
  }
  $runUatPath = Join-Path $ueRoot "RunUAT.sh"
}
elseif ($IsLinux) {
  $ueRoot = $env:UE_ROOT
  if (-not ($ueRoot)) {
    $errorMessage = 'Please set the "UE_ROOT" environment variable.' +
    ' See https://dev.epicgames.com/documentation/unreal-engine/linux-development-quickstart-for-unreal-engine?application_version=5.7#5b-build-a-project-through-the-command-line'
    throw $errorMessage
  }
  $runUatPath = Join-Path $ueRoot "RunUAT.sh"
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
