# SPDX-License-Identifier: Apache-2.0
#Requires -Version 5.1

$ErrorActionPreference = "Stop"
$PSNativeCommandUseErrorActionPreference = $true
Set-StrictMode -Version 3

<#
.Synopsis
  Finds the Unreal Engine script root path.
#>
function Find-UnrealEngineScriptRootPath {
  $uprojectPath = Join-Path -Path $PSScriptRoot -ChildPath "../../UnrealMirror.uproject"
  if (-not (Test-Path -Path $uprojectPath -PathType Leaf)) {
    $errorMessage = "uproject file was not found: $uprojectPath"
    throw $errorMessage
  }

  $uproject = Get-Content -Path $uprojectPath -Raw | ConvertFrom-Json
  $engineAssociation = $uproject.EngineAssociation
  if (-not $engineAssociation) {
    $errorMessage = "EngineAssociation is not set in uproject: $uprojectPath"
    throw $errorMessage
  }

  if ([System.Environment]::OSVersion.Platform -eq [System.PlatformID]::Win32NT) {
    # $IsWindows is not available in PowerShell 5.1, so we use the .NET API to check the platform.
    $installationList = (Get-Content "$env:ProgramData\Epic\UnrealEngineLauncher\LauncherInstalled.dat" | ConvertFrom-Json).InstallationList
    if (-not $installationList) {
      $errorMessage = "Unreal Engine installation list is not found in LauncherInstalled.dat"
      throw $errorMessage
    }
    $installation = $installationList | Where-Object { $_.ArtifactId -eq "UE_${engineAssociation}" }
    if (-not $installation) {
      $errorMessage = "Unreal Engine installation for version $engineAssociation is not found in LauncherInstalled.dat"
      throw $errorMessage
    }
    $installLocation = $installation.InstallLocation
    return "${installLocation}\Engine\Build\BatchFiles"
  }

  if ($IsMacOS) {
    $ueRoot = $env:UE_ROOT
    if (-not ($ueRoot)) {
      $ueRoot = "/Users/Shared/Epic Games/UE_${engineAssociation}/Engine/Build/BatchFiles"
    }
    return $ueRoot
  }

  if ($IsLinux) {
    $ueRoot = $env:UE_ROOT
    if (-not ($ueRoot)) {
        $errorMessage = 'Please set the "UE_ROOT" environment variable.' +
        ' See https://dev.epicgames.com/documentation/unreal-engine/linux-development-quickstart-for-unreal-engine?application_version=5.7#5b-build-a-project-through-the-command-line'
        throw $errorMessage
    }
    return $ueRoot
  }

  $errorMessage = "Unsupported platform: $([System.Environment]::OSVersion.Platform)"
  throw $errorMessage
}

Export-ModuleMember -Function Find-UnrealEngineScriptRootPath
