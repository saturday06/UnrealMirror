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
$vcVersion = "vc143"
$osxDeploymentTarget = "14.0"
$cmakeVersion = "4.3.3"
$bazelVersion = "8.7.0"

Write-Output "Target Platform: $TargetPlatform"
Write-Output "Target Configuration: $TargetConfiguration"

$preferReleaseSetup = $true
if ($TargetConfiguration -in @(
    "Debug",
    "Debug Editor",
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
    & (Join-Path -Path $PSScriptRoot -ChildPath "format.ps1")
  }
  catch {
    Write-Output $_
  }
}

if ($IsWindows) {
  $cmakeGenerator = $vsCmakeGenerator
}
elseif ($IsMacOS) {
  $cmakeGenerator = "Xcode"
}
else {
  $cmakeGenerator = "Unix Makefiles"
}

$processArchitecture = [System.Runtime.InteropServices.RuntimeInformation]::ProcessArchitecture
switch ($processArchitecture) {
  "X64" {
    $bazelArchitecture = "x86_64"
    $cmakeArchitecture = "x86_64"
  }
  "Arm64" {
    $bazelArchitecture = "arm64"
    $cmakeArchitecture = "arm64"
  }
  default { throw "Unsupported Process Architecture: ${processArchitecture}" }
}

$cmakeFolderPath = Join-Path -Path $PSScriptRoot -ChildPath "cmake"
$cmakeDistributionPath = Join-Path -Path $cmakeFolderPath -ChildPath "distribution"
New-Item -ItemType Directory $cmakeDistributionPath -Force
if ($IsWindows) {
  $bazelUrl = "https://github.com/bazelbuild/bazel/releases/download/${bazelVersion}/bazel-${bazelVersion}-windows-${bazelArchitecture}.exe"
  $bazelChmodPlusX = $false
  $cmakeUrl = "https://github.com/Kitware/CMake/releases/download/v${cmakeVersion}/cmake-${cmakeVersion}-windows-${cmakeArchitecture}.zip"
  $cmakePathPattern = Join-Path -Path $cmakeDistributionPath -ChildPath "*" -AdditionalChildPath "bin", "cmake.exe"
}
elseif ($IsMacOS) {
  $bazelUrl = "https://github.com/bazelbuild/bazel/releases/download/${bazelVersion}/bazel-${bazelVersion}-darwin-${bazelArchitecture}"
  $bazelChmodPlusX = $true
  $cmakeUrl = "https://github.com/Kitware/CMake/releases/download/v${cmakeVersion}/cmake-${cmakeVersion}-macos-universal.tar.gz"
  $cmakePathPattern = Join-Path -Path $cmakeDistributionPath -ChildPath "*" -AdditionalChildPath "CMake.app", "Contents", "bin", "cmake"
}
elseif ($IsLinux) {
  $bazelUrl = "https://github.com/bazelbuild/bazel/releases/download/${bazelVersion}/bazel-${bazelVersion}-linux-${bazelArchitecture}"
  $bazelChmodPlusX = $true
  $cmakeUrl = "https://github.com/Kitware/CMake/releases/download/v${cmakeVersion}/cmake-${cmakeVersion}-linux-${cmakeArchitecture}.tar.gz"
  $cmakePathPattern = Join-Path -Path $cmakeDistributionPath -ChildPath "*" -AdditionalChildPath "bin", "cmake"
}
else {
  Write-Output "Unsupported platform: $($PSVersionTable.Platform)"
  exit 1
}

$bazelFileName = Split-Path -Leaf ([System.Uri]::new($bazelUrl)).AbsolutePath
$bazelFolderPath = Join-Path -Path $PSScriptRoot -ChildPath "bazel"
New-Item -ItemType Directory $bazelFolderPath -Force
$bazel = Join-Path -Path $bazelFolderPath -ChildPath $bazelFileName
if (-not (Test-Path $bazel)) {
  Write-Output "Downloading ${bazelUrl}"
  Invoke-RestMethod -Uri $bazelUrl -OutFile $bazel
}
if ($bazelChmodPlusX) {
  & chmod +x $bazel
}
Write-Output "Using bazel: $bazel"
& $bazel --version

$cmakeArchiveFileName = Split-Path -Leaf ([System.Uri]::new($cmakeUrl)).AbsolutePath
$cmakeArchiveFilePath = Join-Path -Path $cmakeFolderPath -ChildPath $cmakeArchiveFileName
if (-not (Test-Path $cmakeArchiveFilePath)) {
  Write-Output "Downloading ${cmakeUrl}"
  Invoke-RestMethod -Uri $cmakeUrl -OutFile $cmakeArchiveFilePath
}
if (-not (Get-ChildItem $cmakePathPattern)) {
  if ($cmakeArchiveFilePath.EndsWith(".zip")) {
    Expand-Archive -Path $cmakeArchiveFilePath -DestinationPath $cmakeDistributionPath -Force
  }
  else {
    & tar xf $cmakeArchiveFilePath -C $cmakeDistributionPath
  }
}
$cmakePaths = Get-ChildItem $cmakePathPattern
if (-not $cmakePaths) {
  throw "Failed to setup local cmake: ${cmakePathPattern} not found"
}
$cmake = $cmakePaths[0].FullName

Write-Output "Using CMake: $cmake"
& $cmake --version

$assimpSourceFolderPath = Join-Path -Path $PSScriptRoot -ChildPath "VRM4U" -AdditionalChildPath "assimp"
if (-not (Test-Path (Join-Path -Path $assimpSourceFolderPath -ChildPath "Readme.md"))) {
  git -C $PSScriptRoot submodule update --init --recursive
}

$debugAssimpBuildFolderPath = Join-Path -Path $assimpSourceFolderPath -ChildPath "build" -AdditionalChildPath "Debug"
New-Item -ItemType Directory $debugAssimpBuildFolderPath -Force

$releaseAssimpBuildFolderPath = Join-Path -Path $assimpSourceFolderPath -ChildPath "build" -AdditionalChildPath "Release"
New-Item -ItemType Directory $releaseAssimpBuildFolderPath -Force

$buildSharedLibs = $IsWindows ? "ON" : "OFF"
$vrm4uAssimpFolderPath = Join-Path -Path $PSScriptRoot -ChildPath ".." -AdditionalChildPath "Plugins", "VRM4U", "ThirdParty", "assimp"
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
