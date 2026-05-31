#!/usr/bin/env pwsh
# SPDX-License-Identifier: Apache-2.0
#Requires -Version 7.4

param(
  [string]$TargetPlatform,
  [string]$TargetConfiguration
)

$ErrorActionPreference = "Stop"
$PSNativeCommandUseErrorActionPreference = $true
Set-StrictMode -Version 3

$vsCmakeGenerator = "Visual Studio 17 2022"
$vsVersionRange = "[17.0,18.0)"
$vcVersion = "vc143"
$osxDeploymentTarget = "14.0"

Write-Output "Target Platform: $TargetPlatform"
Write-Output "Target Configuration: $TargetConfiguration"

$preferReleaseSetup = $true
if ($TargetConfiguration -in @(
    "DebugGame",
    "DebugGame Editor",
    "Development",
    "Development Editor"
  )) {
  $preferReleaseSetup = $false
}
Write-Output "Prefer Release Setup: $preferReleaseSetup"

Write-Output "Environment Variables:"
Get-ChildItem Env: | Sort-Object Name | ForEach-Object {
  Write-Output "  $($_.Name)=$($_.Value)"
}

& {
  try {
    & (Join-Path -Path $PSScriptRoot -ChildPath ".." -AdditionalChildPath "format.ps1")
  }
  catch {
    Write-Output $_
  }
}

if ($IsWindows) {
  $cmakeGenerator = $vsCmakeGenerator
  $vswhere = "${env:ProgramFiles(x86)}\Microsoft Visual Studio\Installer\vswhere.exe"
  if (-not (Test-Path $vswhere)) {
    throw "vswhere.exe was not found: $vswhere"
  }
  $vsInstallationPath = & $vswhere -version $vsVersionRange -property installationPath
  if (-not $vsInstallationPath) {
    throw "Visual Studio was not found"
  }
  $cmake = Join-Path -Path $vsInstallationPath -ChildPath "Common7\IDE\CommonExtensions\Microsoft\CMake\CMake\bin\cmake.exe"
}
elseif ($IsMacOS) {
  $cmakeGenerator = "Xcode"
  $cmake = & zsh -lc "which cmake"
}
else {
  $cmakeGenerator = "Unix Makefiles"
  $cmake = & bash -lc "which cmake"
}

if (-not (Test-Path $cmake)) {
  throw "cmake.exe was not found: $cmake"
}

$assimpSourceFolderPath = Join-Path -Path $PSScriptRoot -ChildPath "assimp"
if (-not (Test-Path (Join-Path -Path $assimpSourceFolderPath -ChildPath "Readme.md"))) {
  git -C $PSScriptRoot submodule update --init --recursive
}

$debugAssimpBuildFolderPath = Join-Path -Path $assimpSourceFolderPath -ChildPath "build" -AdditionalChildPath "Debug"
New-Item -ItemType Directory $debugAssimpBuildFolderPath -Force

$releaseAssimpBuildFolderPath = Join-Path -Path $assimpSourceFolderPath -ChildPath "build" -AdditionalChildPath "Release"
New-Item -ItemType Directory $releaseAssimpBuildFolderPath -Force

$buildSharedLibs = $IsWindows ? "ON" : "OFF"
$vrm4uAssimpFolderPath = Join-Path -Path $PSScriptRoot -ChildPath ".." -AdditionalChildPath "..", "Plugins", "VRM4U", "ThirdParty", "assimp"
$macStaticLibPath = Join-Path -Path $vrm4uAssimpFolderPath -ChildPath "lib" -AdditionalChildPath "Mac", "libassimp.a"

New-Item -ItemType Directory (Join-Path -Path $vrm4uAssimpFolderPath -ChildPath "bin" -AdditionalChildPath "x64") -Force
New-Item -ItemType Directory (Join-Path -Path $vrm4uAssimpFolderPath -ChildPath "lib" -AdditionalChildPath "x64", "Debug") -Force
New-Item -ItemType Directory (Join-Path -Path $vrm4uAssimpFolderPath -ChildPath "lib" -AdditionalChildPath "x64", "Release") -Force

if (-not (Test-Path (Join-Path -Path $debugAssimpBuildFolderPath -ChildPath "CMakeCache.txt"))) {
  & $cmake `
    -G $cmakeGenerator `
    -DASSIMP_BUILD_ALL_EXPORTERS_BY_DEFAULT=OFF `
    -DASSIMP_WARNINGS_AS_ERRORS=OFF `
    "-DBUILD_SHARED_LIBS=${buildSharedLibs}" `
    "-DCMAKE_OSX_DEPLOYMENT_TARGET=${osxDeploymentTarget}" `
    -DCMAKE_BUILD_TYPE=Debug `
    -B $debugAssimpBuildFolderPath `
    -S $assimpSourceFolderPath
}
& $cmake --build $debugAssimpBuildFolderPath --config Debug
if ($IsWindows) {
  $debugDllPath = Join-Path -Path $vrm4uAssimpFolderPath -ChildPath "bin" -AdditionalChildPath "x64", "assimp-${vcVersion}-mtd.dll"
  if (-not (Test-Path $debugDllPath)) {
    Copy-Item (Join-Path -Path $debugAssimpBuildFolderPath -ChildPath "bin" -AdditionalChildPath "Debug", "assimp-${vcVersion}-mtd.dll") $debugDllPath
  }
  $debugPdbPath = Join-Path -Path $vrm4uAssimpFolderPath -ChildPath "bin" -AdditionalChildPath "x64", "assimp-${vcVersion}-mtd.pdb"
  if (-not (Test-Path $debugPdbPath)) {
    Copy-Item (Join-Path -Path $debugAssimpBuildFolderPath -ChildPath "bin" -AdditionalChildPath "Debug", "assimp-${vcVersion}-mtd.pdb") $debugPdbPath
  }
  $debugLibPath = Join-Path -Path $vrm4uAssimpFolderPath -ChildPath "lib" -AdditionalChildPath "x64", "Debug", "assimp-${vcVersion}-mtd.lib"
  if (-not(Test-Path $debugLibPath)) {
    Copy-Item (Join-Path -Path $debugAssimpBuildFolderPath -ChildPath "lib" -AdditionalChildPath "Debug", "assimp-${vcVersion}-mtd.lib") $debugLibPath
  }
}
elseif ($IsMacOS) {
  if (-not ($preferReleaseSetup)) {
    Copy-Item (Join-Path -Path $debugAssimpBuildFolderPath -ChildPath "lib" -AdditionalChildPath "Debug", "libassimpd.a") $macStaticLibPath
  }
}
else {
  Write-Output "Debug build is not supported on this platform: $($PSVersionTable.Platform)"
}

if (-not (Test-Path (Join-Path -Path $releaseAssimpBuildFolderPath -ChildPath "CMakeCache.txt"))) {
  & $cmake `
    -G $cmakeGenerator `
    -DASSIMP_BUILD_ALL_EXPORTERS_BY_DEFAULT=OFF `
    -DASSIMP_WARNINGS_AS_ERRORS=OFF `
    "-DBUILD_SHARED_LIBS=${buildSharedLibs}" `
    "-DCMAKE_OSX_DEPLOYMENT_TARGET=${osxDeploymentTarget}" `
    -DCMAKE_BUILD_TYPE=Release `
    -B $releaseAssimpBuildFolderPath `
    -S $assimpSourceFolderPath
}
& $cmake --build $releaseAssimpBuildFolderPath --config Release

if ($IsWindows) {
  $releaseDllPath = Join-Path -Path $vrm4uAssimpFolderPath -ChildPath "bin" -AdditionalChildPath "x64", "assimp-${vcVersion}-mt.dll"
  if (-not (Test-Path $releaseDllPath)) {
    Copy-Item (Join-Path -Path $releaseAssimpBuildFolderPath -ChildPath "bin" -AdditionalChildPath "Release", "assimp-${vcVersion}-mt.dll") $releaseDllPath
  }
  $releasePdbPath = Join-Path -Path $vrm4uAssimpFolderPath -ChildPath "bin" -AdditionalChildPath "x64", "assimp-${vcVersion}-mt.pdb"
  if (-not (Test-Path $releasePdbPath)) {
    Copy-Item (Join-Path -Path $releaseAssimpBuildFolderPath -ChildPath "bin" -AdditionalChildPath "Release", "assimp-${vcVersion}-mt.pdb") $releasePdbPath
  }
  $releaseLibPath = Join-Path -Path $vrm4uAssimpFolderPath -ChildPath "lib" -AdditionalChildPath "x64", "Release", "assimp-${vcVersion}-mt.lib"
  if (-not (Test-Path $releaseLibPath)) {
    Copy-Item (Join-Path -Path $releaseAssimpBuildFolderPath -ChildPath "lib" -AdditionalChildPath "Release", "assimp-${vcVersion}-mt.lib") $releaseLibPath
  }
}
elseif ($IsMacOS) {
  if ($preferReleaseSetup) {
    Copy-Item (Join-Path -Path $releaseAssimpBuildFolderPath -ChildPath "lib" -AdditionalChildPath "Release", "libassimp.a") $macStaticLibPath
  }
}
else {
  Write-Output "Release build is not supported on this platform: $($PSVersionTable.Platform)"
}

$vrm4uAssimpIncludeFolderPath = Join-Path -Path $vrm4uAssimpFolderPath -ChildPath "include" -AdditionalChildPath "assimp"
Remove-Item $vrm4uAssimpIncludeFolderPath -Recurse -Force
New-Item -ItemType Directory -Path $vrm4uAssimpIncludeFolderPath -Force
Copy-Item (Join-Path -Path $assimpSourceFolderPath -ChildPath "include" -AdditionalChildPath "assimp", "*") $vrm4uAssimpIncludeFolderPath -Recurse -Force
if ($preferReleaseSetup) {
  $preferedAssimpBuildFolderPath = $releaseAssimpBuildFolderPath
}
else {
  $preferedAssimpBuildFolderPath = $debugAssimpBuildFolderPath
}
Copy-Item (Join-Path -Path $preferedAssimpBuildFolderPath -ChildPath "include" -AdditionalChildPath "assimp", "*") $vrm4uAssimpIncludeFolderPath -Recurse -Force
